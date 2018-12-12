#import <Foundation/Foundation.h>

#import "DVGPlayerUxDataPusher.h"
#import "DVGPlayerChunkLoader.h"
#import "DVGPlayerFileUtils.h"
#import "DVGLLPlayerView.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
// http://iphonedevwiki.net/index.php/Unix_sockets
// http://ddeville.me/2015/02/interprocess-communication-on-ios-with-berkeley-sockets
// https://github.com/ddeville/LLBSDMessaging/blob/master/LLBSDMessaging/LLBSDConnection.m
static const int kLLBSDServerConnectionsBacklog = 1024;

// TBD: cleanup downloaded data after 10 minutes

@interface DVGPlayerUxDataPusher ()
@property (assign, atomic) dispatch_fd_t unixfd;
@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) dispatch_source_t listeningSource;
@property (strong, nonatomic) NSMutableDictionary* clientChannels;
@end

@implementation DVGPlayerUxDataPusher

- (void)llhlsDataInit:(NSMutableDictionary*)taskData socket:(NSString*)socpath uri:(NSString*)unixpath {
    if(self.queue == NULL){
        self.clientChannels = @{}.mutableCopy;
        self.queue = dispatch_queue_create("com.vidlib.llhls.serial-queue", DISPATCH_QUEUE_SERIAL);
        const char *socket_path = [socpath cStringUsingEncoding:NSUTF8StringEncoding];
        dispatch_fd_t fd = socket(AF_UNIX, SOCK_STREAM, 0);
        self.unixfd = fd;
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, socket_path, 90);// MIN(strlen(socket_path),MIN(90,sizeof(addr.sun_path))) - 1
        unlink(addr.sun_path);
        int r = -1;
        while(r != 0) {
            r = bind(fd, (struct sockaddr*)&addr, sizeof(addr));
            usleep(200 * 1000);
        }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        int flags = fcntl(fd, F_GETFL, 0);
        r = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        r = -1;
        while(r != 0) {
            r = listen(fd, kLLBSDServerConnectionsBacklog);
            usleep(200 * 1000);
        }
        self.listeningSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.queue);
        dispatch_source_set_event_handler(self.listeningSource, ^ {
            [self acceptNewConnection];
        });
        dispatch_resume(self.listeningSource);
    }
    dispatch_async(self.queue, ^{
        NSMutableDictionary* prevdata = self.clientChannels[unixpath];
        if(prevdata != nil){
            for(NSString* key in prevdata){
                taskData[key] = prevdata[key];
            }
        }
        self.clientChannels[unixpath] = taskData;
    });
}

- (void)acceptNewConnection
{
    struct sockaddr client_addr;
    socklen_t client_addrlen = sizeof(client_addr);
    dispatch_fd_t client_fd = accept(self.unixfd, &client_addr, &client_addrlen);
    if (client_fd < 0) {
        return;
    }
    dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, client_fd, self.queue, ^ (__unused int error) {});
    dispatch_io_set_low_water(channel, 1);
    dispatch_io_set_high_water(channel, SIZE_MAX);
    VLLog(@"DVGPlayerChunkLoader: acceptNewConnection client_fd = %i channel = %i", client_fd, channel);
    char buffer[4096] = {0};
    long len = recv(client_fd, buffer, sizeof(buffer), 0);
    if(len <= 0){
        usleep(200 * 1000);
        // second chance... llhls send data almost immediately
        len = recv(client_fd, buffer, sizeof(buffer), 0);
    }
    VLLog(@"DVGPlayerChunkLoader: acceptNewConnection readlen = %i, client_fd = %i channel = %i", len, client_fd, channel);
    NSString *requestedURI = [[NSString alloc] initWithUTF8String:buffer];
    if([requestedURI length] == 0){
        VLLog(@"DVGPlayerUxDataPusher: acceptNewConnection unknown URI, client_fd = %i, %@", client_fd, requestedURI);
        dispatch_io_close(channel, 0);
        return;
    }
    if(self.clientChannels[requestedURI] == nil){
        // Player requesting chunks, that will be preloaded later
        self.clientChannels[requestedURI] = @{}.mutableCopy;
    }
    NSMutableDictionary* channelData = self.clientChannels[requestedURI];
    channelData[@"llhls_datasent"] = @(0);
    channelData[@"llhls_clientsocket"] = @(client_fd);
    channelData[@"llhls_channel"] = channel;
    VLLog(@"DVGPlayerChunkLoader: acceptNewConnection done client_fd = %i, %@", client_fd, requestedURI);
    [self llhlsDataChange:requestedURI finalLength:0];
}

- (void)llhlsDataChange:(NSString*)uri finalLength:(NSInteger)finalLen {
    //VLLog(@"DVGPlayerChunkLoader: llhlsDataChange %@ %i", uri, finalLen);
    dispatch_async(self.queue, ^{
        NSMutableDictionary* channelData = self.clientChannels[uri];
        if(channelData == nil){
            VLLog(@"DVGPlayerChunkLoader: llhlsDataChange %@ ignored, no channelData", uri);
            return;
        }
        if(finalLen > 0){
            channelData[@"llhls_datafinallen"] = @(finalLen);
        }
        dispatch_io_t channel = channelData[@"llhls_channel"];
        if(channel == nil){
            // No one connected yet
            //VLLog(@"DVGPlayerChunkLoader: llhlsDataChange %@ ignored, no clients", uri);
            return;
        }
        NSInteger alreadySent = [channelData[@"llhls_datasent"] integerValue];
        NSMutableData* llhlsData = [channelData objectForKey:@"data"];
        if(llhlsData != nil && llhlsData.length > alreadySent){
            //VLLog(@"DVGPlayerChunkLoader: llhlsDataChange %@ sending data", uri);
            // Some data to send
            NSData* messageData = nil;
            @synchronized (llhlsData) {
                messageData = [llhlsData subdataWithRange:NSMakeRange(alreadySent, llhlsData.length-alreadySent)];
            }
            NSInteger mdlen = messageData.length;
            channelData[@"llhls_inwrite"] = @(1);
            channelData[@"llhls_datasent"] = @(alreadySent+mdlen);
            //messageData = [@"XXXTEST" dataUsingEncoding:NSUTF8StringEncoding];
            dispatch_data_t message_data = dispatch_data_create([messageData bytes], mdlen, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            dispatch_io_write(channel, 0, message_data, self.queue, ^ (bool done2, __unused dispatch_data_t data2, int write_error2) {
                //VLLog(@"DVGPlayerUxDataPusher: dispatch_io_write, uri=%@, len2wr=%lu err=%i", uri, mdlen, write_error2);
                //if(write_error2){// 89 is OK
                //    VLLog(@"DVGPlayerUxDataPusher: dispatch_io_write error %i, uri=%@", write_error2, uri);
                //}
                // If all sent - closing channel
                NSInteger channelfnl = [channelData[@"llhls_datafinallen"] integerValue];
                NSInteger channelsnt = [channelData[@"llhls_datasent"] integerValue];
                //VLLog(@"DVGPlayerUxDataPusher: dispatch_io_write, test4closeInner %lu - %li",channelsnt,channelfnl);
                if(channelfnl > 0 && channelsnt >= channelfnl){
                    [self llhlsDataReset:uri];
                }
                channelData[@"llhls_inwrite"] = @(0);
            });
        }else{
            //VLLog(@"DVGPlayerChunkLoader: llhlsDataChange %@ nothing to send, data=%lu, alreadySent=%lu", uri, llhlsData.length, alreadySent);
            if([channelData[@"llhls_inwrite"] integerValue] == 0){
                // if no pending write - closing cahnnel
                NSInteger channelfnl = [channelData[@"llhls_datafinallen"] integerValue];
                NSInteger channelsnt = [channelData[@"llhls_datasent"] integerValue];
                //VLLog(@"DVGPlayerUxDataPusher: dispatch_io_write, test4closeOuter %lu - %li",channelsnt,channelfnl);
                if(channelfnl > 0 && channelsnt >= channelfnl){
                    [self llhlsDataReset:uri];
                }
            }
        }
    });
}

- (void)llhlsDataReset:(NSString*)uri {
    NSMutableDictionary* channelData = self.clientChannels[uri];
    dispatch_io_t channel = channelData[@"llhls_channel"];
    dispatch_fd_t client_fd = (int)[channelData[@"llhls_clientsocket"] integerValue];
    VLLog(@"DVGPlayerUxDataPusher: llhlsDataReset uri = %@ client_fd = %i channel = %i", uri, client_fd, channel);
    if(channel != nil){
        [channelData removeObjectForKey:@"llhls_channel"];
        [channelData removeObjectForKey:@"llhls_clientsocket"];
        dispatch_io_close(channel, 0);
        if(client_fd != 0){
            close(client_fd);
        }
    }
}

- (void)collectGarbage {
    if(self.queue == nil){
        return;
    }
    dispatch_async(self.queue, ^{
        double now_ts = CACurrentMediaTime();
        NSArray* allUris = [self.clientChannels allKeys];
        for(NSString* uri in allUris){
            NSMutableDictionary* channelData = self.clientChannels[uri];
            double keepTill = [channelData[@"keepTill"] doubleValue];
            if(keepTill < 1.0){
                channelData[@"keepTill"] = @(now_ts+kPlayerStreamChunksPrefetchTtlSec);
            }else{
                if(now_ts > keepTill){
                    if([channelData[@"llhls_inwrite"] integerValue] == 0){
                        // Chunk can be removed
                        [self.clientChannels removeObjectForKey:uri];
                    }
                }
            }
        }
    });
}

- (void)resetAll {
    NSArray* allUris = [self.clientChannels allKeys];
    for(NSString* uri in allUris){
        [self llhlsDataReset:uri];
    }
}

- (void)dealloc {
    [self resetAll];
}

@end
