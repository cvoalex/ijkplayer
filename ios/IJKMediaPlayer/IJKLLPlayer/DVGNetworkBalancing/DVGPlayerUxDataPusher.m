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
    VLLog(@"DVGPlayerUxDataPusher: acceptNewConnection channel = %i/%i", channel, client_fd);
    char buffer[4096] = {0};
    long len = recv(client_fd, buffer, sizeof(buffer), 0);
    if(len <= 0){
        usleep(200 * 1000);
        // second chance... llhls send data almost immediately
        len = recv(client_fd, buffer, sizeof(buffer), 0);
    }
    if(len <= 0){
        VLLog(@"DVGPlayerUxDataPusher: acceptNewConnection: ERROR = %i, channel = %i/%i", len, channel, client_fd);
    }
    NSString *requestedURI = [[NSString alloc] initWithUTF8String:buffer];
    if([requestedURI length] == 0){
        VLLog(@"DVGPlayerUxDataPusher: acceptNewConnection unknown URI, channel = %i/%i, %@", channel, client_fd, requestedURI);
        dispatch_io_close(channel, 0);
        close(client_fd);
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
    VLLog(@"DVGPlayerUxDataPusher: acceptNewConnection done, channel = %i/%i, %@", channel, client_fd, requestedURI);
    [self llhlsDataChange:requestedURI finalLength:0];
}

- (void)llhlsDataChange:(NSString*)uri finalLength:(NSInteger)finalLen {
    //VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ %i", uri, finalLen);
    dispatch_async(self.queue, ^{
        NSMutableDictionary* channelData = self.clientChannels[uri];
        if(channelData == nil){
            VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ ignored, no channelData", uri);
            return;
        }
        if(finalLen != 0){
            channelData[@"llhls_datafinallen"] = @(finalLen);
        }
        dispatch_io_t channel = channelData[@"llhls_channel"];
        if(channel == nil){
            // No one connected yet
            //VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ ignored, no clients", uri);
            return;
        }
        NSInteger alreadySent = [channelData[@"llhls_datasent"] integerValue];
        NSMutableData* llhlsData = [channelData objectForKey:@"data"];
        if(llhlsData != nil){
            if(llhlsData.length > alreadySent){
                //VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ sending data", uri);
                // Some data to send
                NSData* messageData = nil;
                @synchronized (llhlsData) {
                    messageData = [llhlsData subdataWithRange:NSMakeRange(alreadySent, llhlsData.length-alreadySent)];
                }
                NSInteger mdlen = messageData.length;
                //channelData[@"llhls_noresetTill"] = @(CACurrentMediaTime()+1.0);
                channelData[@"llhls_datasent"] = @(alreadySent+mdlen);
                channelData[@"llhls_inwrite"] = @([channelData[@"llhls_inwrite"] integerValue]+1);
                dispatch_data_t message_data = dispatch_data_create([messageData bytes], mdlen, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                dispatch_io_write(channel, 0, message_data, self.queue, ^ (bool done2, __unused dispatch_data_t data2, int write_error2) {
                   // VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ data sent (%lu of %lu, done=%i, err=%i)", uri,
                   //       [channelData[@"llhls_datasent"] integerValue], [channelData[@"llhls_datafinallen"] integerValue], done2, write_error2);
                    if(done2){
                        if(write_error2 != 0){
                            VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ ERROR (%lu of %lu, done=%i, err=%i)", uri,
                                  [channelData[@"llhls_datasent"] integerValue], [channelData[@"llhls_datafinallen"] integerValue], done2, write_error2);
                        }
                        //channelData[@"llhls_noresetTill"] = @(0);
                        channelData[@"llhls_inwrite"] = @([channelData[@"llhls_inwrite"] integerValue]-1);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self llhlsDataResetIfNeeded:uri forced:0];
                        });
                    }
                });
            }
        }
        if(finalLen != 0){
            // Close channels now, if possible
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self llhlsDataResetIfNeeded:uri forced:0];
            });
        }
    });
}

- (BOOL)llhlsDataResetIfNeeded:(NSString*)uri forced:(int)forced {
    NSMutableDictionary* channelData = self.clientChannels[uri];
    if(channelData == nil){
        return YES;
    }
    if(forced < 2 && [channelData[@"llhls_inwrite"] integerValue] != 0){
        // Too early
        return NO;
    }
    //double now_ts = CACurrentMediaTime();
    //double noresetTill = [channelData[@"llhls_noresetTill"] doubleValue];
    //if(forced < 2 && now_ts < noresetTill){
    //    // Too early
    //    return NO;
    //}
    // if no pending write - closing cahnnel
    NSInteger channelfnl = [channelData[@"llhls_datafinallen"] integerValue];
    NSInteger channelsnt = [channelData[@"llhls_datasent"] integerValue];
    dispatch_io_t channel = channelData[@"llhls_channel"];
    dispatch_fd_t client_fd = (int)[channelData[@"llhls_clientsocket"] integerValue];
    if(channel != nil){
        if(forced > 0 || (channelfnl > 0 && channelsnt >= channelfnl) || channelfnl < 0){
            VLLog(@"DVGPlayerUxDataPusher: llhlsDataReset uri = %@, channel = %i/%i (%lu of %lu)", uri, channel, client_fd, channelsnt, channelfnl);
            [channelData removeObjectForKey:@"llhls_channel"];
            [channelData removeObjectForKey:@"llhls_clientsocket"];
            channelData[@"llhls_datasent"] = @(0);// To allow resends
            dispatch_async(self.queue, ^{
                dispatch_io_close(channel, 0);
                close(client_fd);
            });
        }
    }
    return YES;
}

- (void)collectGarbage {
    if(self.queue == nil){
        return;
    }
    dispatch_async(self.queue, ^{
        double now_ts = CACurrentMediaTime();
        NSArray* allUris = [self.clientChannels allKeys];
        NSInteger openChannels = 0;
        for(NSString* uri in allUris){
            NSMutableDictionary* channelData = self.clientChannels[uri];
            if(channelData[@"llhls_channel"] != nil){
                openChannels++;
            }
            double keepTill = [channelData[@"keepTill"] doubleValue];
            if(keepTill < 1.0){
                // Too early
                channelData[@"keepTill"] = @(now_ts+kPlayerStreamChunksPrefetchTtlSec);
                continue;
            }
            if(now_ts > keepTill){
                // data can be completely removed
                if([self llhlsDataResetIfNeeded:uri forced:1]){
                    [self.clientChannels removeObjectForKey:uri];
                }
            }else{
                [self llhlsDataResetIfNeeded:uri forced:0];
            }
        }
        VLLog(@"DVGPlayerUxDataPusher: collectGarbage: openedChannels: %li",openChannels);
    });
}

- (void)llhlsDataResetAll {
    if(self.queue == nil){
        return;
    }
    dispatch_sync(self.queue, ^{
        NSInteger openChannels = 0;
        NSArray* allUris = [self.clientChannels allKeys];
        for(NSString* uri in allUris){
            NSMutableDictionary* channelData = self.clientChannels[uri];
            if(channelData[@"llhls_channel"] != nil){
                openChannels++;
            }
            [self llhlsDataResetIfNeeded:uri forced:2];
        }
        VLLog(@"DVGPlayerUxDataPusher: llhlsDataResetAll: killing channels: %li/%lu",openChannels, [allUris count]);
        [self.clientChannels removeAllObjects];
    });
}

- (void)dealloc {
    [self llhlsDataResetAll];
}

@end
