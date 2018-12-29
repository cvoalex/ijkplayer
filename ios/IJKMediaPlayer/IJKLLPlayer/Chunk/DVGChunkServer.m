//
//  DVGChunkServer.m
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/27/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IJKMediaFramework/IJKMediaFramework-Swift.h>

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

#import "DVGChunkServer.h"
#define VLLog(frmt, ...) [VLLogger LogFormat:frmt, ##__VA_ARGS__]
@interface VLLogger: NSObject
+ (NSString*)LogFormat:(NSString *)format, ...;
+ (NSString*)GetLogs:(BOOL)andReset;
@end

static const int kLLBSDServerConnectionsBacklog = 1024;

@interface DVGChunkServer ()
@property (assign, atomic) dispatch_fd_t unixfd;
@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) dispatch_source_t listeningSource;
@property (strong, nonatomic) NSMutableDictionary* clientChannels;
@property (strong, nonatomic) NSMutableDictionary* chunksStatus;
@end

@implementation DVGChunkServer
- (void)run:(NSString* _Nonnull)socketPath {
    if(self.listeningSource == nil){
        self.clientChannels = @{}.mutableCopy;
        self.chunksStatus = @{}.mutableCopy;
        self.queue = dispatch_queue_create("com.vidlib.llhls.serial-queue", DISPATCH_QUEUE_SERIAL);
        const char *socket_path = [socketPath cStringUsingEncoding:NSUTF8StringEncoding];
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
        __weak DVGChunkServer* wself = self;
        self.listeningSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.queue);
        dispatch_source_set_cancel_handler(self.listeningSource, ^ {
            VLLog(@"DVGChunkServer: llhlsUnixPusherInit server cancelled");
            if(wself.unixfd != 0){
                close(wself.unixfd);
                wself.unixfd = 0;
            }
        });
        dispatch_source_set_event_handler(self.listeningSource, ^ {
            [self acceptNewConnection];
        });
        dispatch_resume(self.listeningSource);
        VLLog(@"DVGChunkServer: llhlsUnixPusherInit server for [%s], fd=%i", addr.sun_path, self.unixfd);
        [self.delegate unixServerReady];
    }
    
}

- (void)acceptNewConnection
{
    // dispatch_async(self.queue, ^{ // already in queue
    struct sockaddr client_addr;
    socklen_t client_addrlen = sizeof(client_addr);
    dispatch_fd_t client_fd = accept(self.unixfd, &client_addr, &client_addrlen);
    if (client_fd < 0) {
        return;
    }
    dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, client_fd, self.queue, ^ (__unused int error) {
        //VLLog(@"DVGPlayerUxDataPusher: acceptNewConnection channel close %i, channel = ?/%i", error, client_fd);
        close(client_fd);
    });
    dispatch_io_set_low_water(channel, 1);
    dispatch_io_set_high_water(channel, SIZE_MAX);
    VLLog(@"DVGChunkServer: acceptNewConnection channel = %i/%i", channel, client_fd);
    char buffer[4096] = {0};
    long len = recv(client_fd, buffer, sizeof(buffer), 0);
    if(len <= 0){
        usleep(200 * 1000);
        // second chance... llhls send data almost immediately
        len = recv(client_fd, buffer, sizeof(buffer), 0);
    }
    if(len <= 0){
        VLLog(@"DVGChunkServer: acceptNewConnection: ERROR = %i, channel = %i/%i", len, channel, client_fd);
    }
    NSString *requestedURI = [[NSString alloc] initWithUTF8String:buffer];
    if([requestedURI length] == 0){
        VLLog(@"DVGChunkServer: acceptNewConnection unknown URI, channel = %i/%i, %@", channel, client_fd, requestedURI);
        dispatch_io_close(channel, DISPATCH_IO_STOP);
        return;
    }
    if(self.clientChannels[requestedURI] == nil){
        // Player requesting chunks, that will be preloaded later
        self.clientChannels[requestedURI] = @{}.mutableCopy;
    }
    
    NSMutableDictionary* channelData = self.clientChannels[requestedURI];
    channelData[@"dataSent"] = @(0);
    channelData[@"connectionTimestamp"] = @([[NSDate date] timeIntervalSince1970]);
    channelData[@"socket"] = channel;
    channelData[@"finalLen"] = @(0);
    channelData[@"inWrite"] = @(0);
    channelData[@"closePending"] = @(0);
    VLLog(@"DVGChunkServer: acceptNewConnection done, channel = %i/%i, %@", channel, client_fd, requestedURI);
    [self writeData:requestedURI];
}

- (void)hasNewData:(NSString* _Nonnull)key {
    [self writeData:key];
//    NSMutableDictionary* metaDict = self.clientChannels[key];
//    if(metaDict != nil){
//        dispatch_io_t socket = metaDict[@"socket"];
//        NSInteger sent = [metaDict[@"dataSent"] integerValue];
//        [self writeData:key to:socket dataSent:sent];
//    }
//    dispatch_async(self.queue, ^{
//
//    });
}

- (void)endDataTransmission:(NSString* _Nonnull)key {
    // setup flag for data transmission status. 1 - downloaded, 2 - sent via unix
    dispatch_async(self.queue, ^{
        VLLog(@"DVGChunkServer: endDataTransmission for %@", key);
        NSMutableDictionary* metaDict = self.clientChannels[key];
        NSInteger inWrite = [metaDict[@"inWrite"] integerValue];
        metaDict[@"finalLen"] = @(1);
        if (metaDict != nil && [metaDict[@"inWrite"] integerValue] == 0) {
            __weak DVGChunkServer* wself = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [wself closeDataConnection:key];
            });
        }
    });
    // clean chunksStatus
//    NSArray* allUris = [self.chunksStatus allKeys];
//    NSInteger openChannels = 0;
//    for(NSString* uri in allUris){
//        int status = [self.chunksStatus[uri] intValue];
//        if (status == 2) {
//            [self.chunksStatus removeObjectForKey:uri];
//        }
//    }
}

- (void)closeDataConnection:(NSString* _Nonnull)key {
    dispatch_async(self.queue, ^{
        NSMutableDictionary* metaDict = self.clientChannels[key];
        if(metaDict != nil){
            dispatch_io_t socket = metaDict[@"socket"];
            dispatch_io_close(socket, DISPATCH_IO_STOP);
            [self.clientChannels removeObjectForKey:key];
            VLLog(@"DVGChunkServer: close socket for %@", key);
        }
    });
}

- (void)writeData:(NSString* _Nonnull)key {
    dispatch_async(self.queue, ^{
        NSMutableDictionary* metaDict = self.clientChannels[key];
        if(metaDict == nil) { return; }
        dispatch_io_t socket = metaDict[@"socket"];
        NSInteger sent = [metaDict[@"dataSent"] integerValue];
        NSInteger finalLen = [metaDict[@"finalLen"] integerValue];
        NSInteger inWrite = [metaDict[@"inWrite"] integerValue];
        NSInteger closePending = [metaDict[@"closePending"] integerValue];
        
        //NSData* data = [self.delegate requestData:key dataSent:sent];
        NSData* data = [self.delegate requestData:key];
        if(data == nil){return;}
        if(data.length <= sent) { return; }
        VLLog(@"DVGChunkServer: data range from %i to %i for %@", sent, data.length-sent, key);
        NSData* messageData = [data subdataWithRange:NSMakeRange(sent, data.length-sent)];
        if (messageData == nil || messageData.length == 0) {
            // no data to sent
            VLLog(@"DVGChunkServer: data is nil status for %@", key);
            return;
        }
        
        NSInteger mdlen = messageData.length;
        
        metaDict[@"inWrite"] = @([metaDict[@"inWrite"] integerValue]+1);
        metaDict[@"dataSent"] = @(sent+mdlen);
        __weak DVGChunkServer* wself = self;
        __weak NSMutableDictionary* weakMetaDict = metaDict;
        dispatch_data_t message_data = dispatch_data_create([messageData bytes], mdlen, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        dispatch_io_write(socket, 0, message_data, self.queue, ^ (bool done2, __unused dispatch_data_t data2, int write_error2) {
            if(done2){
                if(write_error2 != 0){
                    VLLog(@"DVGChunkServer: writeData error");
                }
                VLLog(@"DVGChunkServer: write finished data is %i for %@", mdlen, key);
                weakMetaDict[@"inWrite"] = @([weakMetaDict[@"inWrite"] integerValue]-1);
                dispatch_async(self.queue, ^{
                    NSInteger inWrite = [metaDict[@"inWrite"] integerValue];
                    NSInteger finalLen = [metaDict[@"finalLen"] integerValue];
                    if (inWrite == 0 && finalLen != 0) {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [wself closeDataConnection:key];
                        });
                    }
                });
            }
        });
    });
}

- (void)writeData:(NSString* _Nonnull)key to:(dispatch_io_t)socket dataSent:(NSInteger)offset {
    dispatch_async(self.queue, ^{
        if(socket == nil){ return;}
        NSInteger status = [self.chunksStatus[key] integerValue];
        NSData* data = [self.delegate requestData:key dataSent:offset];
        NSInteger mdlen = data.length;
        VLLog(@"DVGChunkServer: chunksStatus %@", self.chunksStatus);
        if (data == nil) {
            // no data to sent
            VLLog(@"DVGChunkServer: data is nil status is %i for %@", status, key);
            if (status == 1) {
                // all data has been sent, clean dict, close socket
                VLLog(@"DVGChunkServer: status is 1 for %@", key);
                [self.chunksStatus removeObjectForKey:key];
                [self closeDataConnection:key];
            }
            return;
        }
        
        // Update data sent
        NSMutableDictionary* metaDict = self.clientChannels[key];
        if(metaDict != nil){
            //NSInteger dataSent = [metaDict[@"dataSent"] integerValue];
            NSInteger newDataSent = mdlen;
            metaDict[@"dataSent"] = @(newDataSent);
        }
        
        __weak DVGChunkServer* wself = self;
        dispatch_data_t message_data = dispatch_data_create([data bytes], mdlen, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        dispatch_io_write(socket, 0, message_data, self.queue, ^ (bool done2, __unused dispatch_data_t data2, int write_error2) {
            if(done2){
                if(write_error2 != 0){
                    VLLog(@"DVGChunkServer: writeData error");
                }
                VLLog(@"DVGChunkServer: write finished data %i status is %i for %@", mdlen, status, key);
                VLLog(@"DVGChunkServer: metaDict %@", metaDict);
                dispatch_async(wself.queue, ^{
                    NSInteger statusNow = [wself.chunksStatus[key] integerValue];
                    if (statusNow == 1) {
                        VLLog(@"DVGChunkServer: write finished ready to clear for %@", mdlen, status, key);
                        // all data has been sent, clean dict, close socket
                        [wself.chunksStatus removeObjectForKey:key];
                        //wself.chunksStatus.chunksStatus[key] = @(2);
                        [wself closeDataConnection:key];
                    }
                });
            }
        });
    });
}

//- (void)llhlsDataChange:(NSString*)uri finalLength:(NSInteger)finalLen {
//    //VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ %i", uri, finalLen);
//    dispatch_async(self.queue, ^{
//        double now_ts = CACurrentMediaTime();
//        NSMutableDictionary* channelData = self.clientChannels[uri];
//        if(channelData == nil){
//            //VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ ignored, no channelData", uri);
//            return;
//        }
//        if(finalLen != 0){
//            channelData[@"llhls_datafinallen"] = @(finalLen);
//        }
//        double keepTill = [channelData[@"keepTill"] doubleValue];
//        if(keepTill > 0.0){
//            // Too early
//            channelData[@"keepTill"] = @(now_ts+kPlayerStreamChunksPrefetchTtlSec);
//        }
//        dispatch_io_t channel = channelData[@"llhls_channel"];
//        if(channel == nil){
//            // No one connected yet
//            //VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ ignored, no clients", uri);
//            return;
//        }
//        NSInteger alreadySent = [channelData[@"llhls_datasent"] integerValue];
//        NSMutableData* llhlsData = [channelData objectForKey:@"data"];
//        if(llhlsData != nil){
//            if(llhlsData.length > alreadySent){
//                // Some data to send
//                NSData* messageData = nil;
//                @synchronized (llhlsData) {
//                    messageData = [llhlsData subdataWithRange:NSMakeRange(alreadySent, llhlsData.length-alreadySent)];
//                }
//                NSInteger mdlen = messageData.length;
//                if(CACurrentMediaTime() > [channelData[@"llhls_datasent_logts"] doubleValue] || finalLen != 0){
//                    channelData[@"llhls_datasent_logts"] = @(CACurrentMediaTime()+0.1);
//                    VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ sending data len=%li", uri, mdlen);
//                }
//                //channelData[@"llhls_noresetTill"] = @(CACurrentMediaTime()+1.0);
//                self.statConsumedBytes += mdlen;
//                channelData[@"llhls_datasent"] = @(alreadySent+mdlen);
//                channelData[@"llhls_inwrite"] = @([channelData[@"llhls_inwrite"] integerValue]+1);
//                __weak DVGPlayerUxDataPusher* wself = self;
//                __weak NSMutableDictionary* wchannelData = channelData;
//                dispatch_data_t message_data = dispatch_data_create([messageData bytes], mdlen, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
//                dispatch_io_write(channel, 0, message_data, self.queue, ^ (bool done2, __unused dispatch_data_t data2, int write_error2) {
//                    // VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ data sent (%lu of %lu, done=%i, err=%i)", uri,
//                    //       [channelData[@"llhls_datasent"] integerValue], [channelData[@"llhls_datafinallen"] integerValue], done2, write_error2);
//                    if(done2){
//                        if(write_error2 != 0){
//                            VLLog(@"DVGPlayerUxDataPusher: llhlsDataChange %@ ERROR (%lu of %lu, done=%i, err=%i)", uri,
//                                  [channelData[@"llhls_datasent"] integerValue], [wchannelData[@"llhls_datafinallen"] integerValue], done2, write_error2);
//                        }
//                        wchannelData[@"llhls_inwrite"] = @([wchannelData[@"llhls_inwrite"] integerValue]-1);
//                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                            [wself llhlsDataResetIfNeeded:uri forced:0 sync:YES];
//                        });
//                    }
//                });
//            }
//        }
//        if(finalLen != 0){
//            // Close channels now, if possible
//            __weak DVGChunkServer* wself = self;
//            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                [wself llhlsDataResetIfNeeded:uri forced:0 sync:YES];
//            });
//        }
//    });
//}

//- (BOOL)llhlsDataResetIfNeeded:(NSString*)uri forced:(int)forced sync:(BOOL)snk {
//    __block BOOL result = YES;
//    dispatch_block_t doCheck = ^{
//        NSMutableDictionary* channelData = self.clientChannels[uri];
//        if(channelData == nil){
//            result = YES;
//            return;
//        }
//        NSInteger channelfnl = [channelData[@"llhls_datafinallen"] integerValue];
//        NSInteger channelsnt = [channelData[@"llhls_datasent"] integerValue];
//        dispatch_io_t channel = channelData[@"llhls_channel"];
//        NSInteger isInWrite = [channelData[@"llhls_inwrite"] integerValue];
//        if(forced < 2 && isInWrite != 0){
//            // Too early
//            result = NO;
//            return;
//        }
//        // if no pending write - closing channel
//        if(channel != nil){
//            if(forced > 0 || (channelfnl > 0 && channelsnt >= channelfnl) || channelfnl < 0){
//                VLLog(@"DVGPlayerUxDataPusher: llhlsDataReset uri = %@, channel = %i (%li of %li)", uri, channel, channelsnt, channelfnl);
//                [channelData removeObjectForKey:@"llhls_channel"];
//                //[channelData removeObjectForKey:@"llhls_clientsocket"];
//                channelData[@"llhls_datasent"] = @(0);// To allow resends
//                dispatch_io_close(channel, DISPATCH_IO_STOP);
//            }
//        }
//    };
//    if(snk){
//        dispatch_sync(self.queue, doCheck);
//    }else{
//        doCheck();
//    }
//    return result;
//}

- (void)finalizeThis {
    if(self.clientChannels == nil){
        return;
    }
    self.statConsumedBytes = 0;
    //[self llhlsDataFlushAllConnections];
    [self.clientChannels removeAllObjects];
    self.clientChannels = nil;
    if(self.listeningSource != nil){
        dispatch_source_cancel(self.listeningSource);
        self.listeningSource = nil;
    }
}

- (void)dealloc {
    [self finalizeThis];
}
@end
