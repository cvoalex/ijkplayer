#import <Foundation/Foundation.h>
#import "DVGLLPlayerView.h"
#import "DVGPlayerChunkLoader.h"
#import "DVGPlayerFileUtils.h"
#import "DVGPlayerUxDataPusher.h"
#import "DVGPlayerServerChecker.h"
#define kDVGPlayerLoaderCacheFolder @"playerloader"

@interface DVGPlayerChunkLoader () <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
//@property (atomic,strong) AFxJSONResponseSerializer* httpManagerSerializer;
//@property (atomic,strong) AFxHTTPSessionManager* httpManager;
@property (atomic, strong) NSMutableArray* filelist;
@property (atomic, strong) NSMutableDictionary* downloaderDatas;
@property (atomic, strong) NSDictionary* downloaderTimingMap;
@property (atomic, strong) NSTimer *trackTimer;
@property (atomic, assign) NSInteger activeDownloads;
@property (atomic, assign) NSInteger filelistChunkNext;
@property (atomic, assign) double filelistStartTs;
@property (atomic, assign) double filelistLastDnTs;
@property (atomic, assign) double chunkDuration;
@property (atomic, assign) double chunkLoadingTimeout;
@property (atomic, assign) double unixpusherGarbageColTs;
@property (atomic, strong) DVGPlayerUxDataPusher* unixpusher;
@property (atomic, assign) NSInteger statDownloadedBytes;
//@property (atomic, assign) double statChunkDownloadTime;
@property (atomic, strong) NSMutableArray* statDataPoints;
@end

@implementation DVGPlayerChunkLoader
+ (void) initialize {
    static int isCachesChecked = 0;
    if (isCachesChecked == 0) {
        isCachesChecked++;
        
        // Once-only initializion
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString* cachePath = [DVGPlayerFileUtils cachePathForKey:kDVGPlayerLoaderCacheFolder];
            [[DVGPlayerFileUtils sharedManager] cleanupCachesAtPath:cachePath maxAge:7*24*60*60 maxTotalSize:500*1000000];
        });
    }
}

- (void)finalizeThis {
    self.statDownloadedBytes = 0;
    [self.unixpusher finalizeThis];
    self.unixpusher = nil;
    [self resetPendingDownloads:YES];
}

- (void)dealloc {
    [self finalizeThis];
}

- (NSArray*)getChunkUnixPairForUrl:(NSString*)chunkUrl {
    NSURLComponents *urlComponents = [[NSURLComponents alloc] initWithString:chunkUrl];
    //chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"] withString:@""];
    chunkUrl = urlComponents.query;
    chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"?" withString:@"_"];
    chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"=" withString:@"_"];
    chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"&" withString:@"_"];
    chunkUrl = [NSString stringWithFormat:@"%@.ts",chunkUrl];
    //chunkUrl = [NSString stringWithFormat:@"%@/%@.ts",[DVGPlayerFileUtils cachePathForKey:kDVGPlayerLoaderCacheFolder],chunkUrl];
    return @[[DVGPlayerFileUtils cachePathForKey:kDVGPlayerLoaderCacheFolder], chunkUrl];
}

- (void)resetPendingDownloads:(BOOL)andStopDnl {
    //NSLog(@"resetPendingDownloads");
    @synchronized(self){
        if(self.filelist == nil){
            self.statDataPoints = @[].mutableCopy;
            self.filelist = @[].mutableCopy;
            self.downloaderDatas = @{}.mutableCopy;
        }
        if(self.trackTimer != nil){
            [self.trackTimer invalidate];
            self.trackTimer = nil;
        }
        // Normally we do NOT stopping downloads. Active task may continue, since downloader will not go too much to the future
        // and this will save time for resking data by ffmpeg
        if(andStopDnl){
            for(NSString* url in self.downloaderDatas){
                [self cancelDownloadForUrl:url];
            }
        }
        [self.unixpusher llhlsDataFlushAllConnections];
        [self.filelist removeAllObjects];
        self.filelistChunkNext = 0;
        self.activeDownloads = 0;
    }
}

- (BOOL)cancelDownloadForUrl:(NSString*)url {
    NSMutableDictionary* taskData = self.downloaderDatas[url];
    NSURLSessionDataTask *dataTask = taskData[@"downloadTask"];
    if(dataTask != nil){
        [dataTask cancel];
        [taskData removeObjectForKey:@"downloadTask"];
        return YES;
    }
    return NO;
}

- (NSMutableDictionary*)findTaskdataByUrl:(NSString *)url{
    //@synchronized(self){
//        for(NSMutableDictionary* downloadtaskData in self.downloaderDatas){
//            if([url isEqualToString:downloadtaskData[@"url"]]){
//                return downloadtaskData;
//            }
//        }
//    }
//    return nil;
    NSMutableDictionary* res = nil;
    @synchronized(self){
        res = self.downloaderDatas[url];
    }
    return res;
}

- (void)prepareForAvgChunkDuration:(float)durSec prefetchCount:(NSInteger)prefetchcnt {
    self.chunkDuration = durSec;
    //self.chunkPrefetchCount = prefetchcnt;
    self.chunkLoadingTimeout = self.chunkDuration*(prefetchcnt+1);//self.chunkDuration*(prefetchcnt-1.0+(1.0-kPlayerStreamChunksPrefetchFrac));
}

- (void)prepareChunksTimingForList:(NSDictionary*)mapUrlToStartStamp {
    self.downloaderTimingMap = mapUrlToStartStamp;
}

- (BOOL)downloadChunksFromList:(NSArray*)urls andContinue:(dispatch_block_t)onOk {
    if(self.chunkDuration <= 0.1){
        // Not ready
        return NO;
    }
    dispatch_block_t startDownloads = ^{
        // MUST be main thread! special for NSTimer
        [self resetPendingDownloads:NO];
        if([self.filelist count] == 0){
            self.filelistStartTs = CACurrentMediaTime();
        }
        @synchronized(self){
            [self.filelist addObjectsFromArray:urls];
            if(self.trackTimer == nil){
                [self downloadNextChunk];
                self.trackTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                                   target:self selector:@selector(checkForNextDownload)
                                                                 userInfo:nil repeats:YES];
            }
        }
        if(onOk != nil){
            onOk();
        }
    };
    NSString* chunkUnixSoc = nil;
    if([urls count]>0){
        chunkUnixSoc = [[urls objectAtIndex:0] objectAtIndex:1];
    }
    if([chunkUnixSoc length]>0 && self.unixpusher == nil){
        self.unixpusher = [[DVGPlayerUxDataPusher alloc] init];
        [self.unixpusher llhlsUnixPusherInit:chunkUnixSoc andContinue:^{
            dispatch_async(dispatch_get_main_queue(), startDownloads);
        }];
    }else{
        dispatch_async(dispatch_get_main_queue(), startDownloads);
    }
    return YES;
}

- (void)checkForNextDownload {
    //NSLog(@"checkForNextDownload %i %i",self.activeDownloads, self.chunkPrefetchCount);
    double ts = [DVGPlayerServerChecker unixStamp];
    //double up_dnlpossible_ts = self.filelistStartTs+(self.filelistChunkNext-self.chunkPrefetchCount)*self.chunkDuration;
    //double dn_dnlpossible_ts = self.filelistLastDnTs+self.chunkDuration*kPlayerStreamChunksPrefetchFrac;
    
    BOOL isTimingOk = NO;
    NSInteger chunkNum = self.filelistChunkNext;
    NSArray* chunkMeta = [self.filelist objectAtIndex:chunkNum];
    NSString* chunkUrl = [chunkMeta objectAtIndex:0];
    if(self.downloaderTimingMap[chunkUrl] != nil){
        double chunkUrlMinTs = [self.downloaderTimingMap[chunkUrl] doubleValue];
        if(ts > chunkUrlMinTs){
            isTimingOk = YES;
        }
    }
    if(isTimingOk){// self.activeDownloads < self.chunkPrefetchCount
        [self downloadNextChunk];
    }
    if(ts > self.unixpusherGarbageColTs + 5.0){
        self.unixpusherGarbageColTs = ts;
        [self.unixpusher collectGarbage];
    }
}

- (BOOL)downloadNextChunk {
    //NSLog(@"downloadNextChunk %i %i",self.filelistChunkNext, [self.filelist count]);
    if(self.filelistChunkNext >= [self.filelist count]){
        return NO;
    }
    NSURLSessionDataTask *downloadTask = nil;
    @synchronized(self){
        NSInteger chunkNum = self.filelistChunkNext;
        self.filelistChunkNext++;
        NSArray* chunkMeta = [self.filelist objectAtIndex:chunkNum];
        NSString* chunkUrl = [chunkMeta objectAtIndex:0];
        NSString* chunkFileuri = [chunkMeta objectAtIndex:2];
        if([self findTaskdataByUrl:chunkUrl] != nil){
            // Already in progress, skipping
            // VLLog(@"DVGPlayerChunkLoader: downloadNextChunk already in progress, %@", chunkUrl);
            return NO;
        }
        self.activeDownloads++;
        VLLog(@"DVGPlayerChunkLoader: download started for %@, timeout=%.02f", chunkUrl, self.chunkLoadingTimeout);
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:chunkUrl]
                                                               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                           timeoutInterval:self.chunkLoadingTimeout];
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.allowsCellularAccess = YES;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];// [NSURLSession sharedSession]
        downloadTask = [session dataTaskWithRequest:request];
        NSMutableDictionary* taskData = @{}.mutableCopy;
        [taskData setObject:downloadTask forKey:@"downloadTask"];
        [taskData setObject:@(0) forKey:@"ts_start"];
        [taskData setObject:chunkUrl forKey:@"url"];
        [taskData setObject:chunkFileuri forKey:@"fileuri"];
        [taskData setObject:@(chunkNum) forKey:@"chunkSeq"];
        NSMutableData* receivedData = [[NSMutableData alloc] init];
        [receivedData setLength:0];
        [taskData setObject:receivedData forKey:@"data"];
        self.downloaderDatas[chunkUrl] = taskData;
        if([chunkFileuri length] > 0){
            [self.unixpusher llhlsDataPrepare:taskData uri:chunkFileuri];
        }
        // Chunk request init point
        [self.statDataPoints addObject:@[@([DVGPlayerServerChecker unixStamp]), @(20000), @(chunkNum)]];
    }
    [downloadTask resume];
    self.filelistLastDnTs = CACurrentMediaTime();
    return YES;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    NSMutableDictionary* taskData = [self findTaskdataByUrl:dataTask.originalRequest.URL.absoluteString];
    if(taskData == nil){
        VLLog(@"DVGPlayerChunkLoader: ERROR: taskData not found, %@", dataTask.originalRequest);
        return;
    }
    //NSString* taskUrl = taskData[@"url"];
    //VLLog(@"DVGPlayerChunkLoader: download first response for %@", taskUrl);
    [taskData setObject:@(CACurrentMediaTime()) forKey:@"ts_start"];
    completionHandler(NSURLSessionResponseAllow);
}
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSMutableDictionary* taskData = [self findTaskdataByUrl:dataTask.originalRequest.URL.absoluteString];
    if(taskData == nil){
        VLLog(@"DVGPlayerChunkLoader: ERROR: taskData not found, %@", dataTask.originalRequest);
        return;
    }
    NSString* taskUrl = taskData[@"url"];
    NSInteger chunkNum = [taskData[@"chunkSeq"] integerValue];
    if([taskData objectForKey:@"ts_firstbyte"] == nil){
        VLLog(@"DVGPlayerChunkLoader: download first bytes for %@", taskUrl);
        [taskData setObject:@(CACurrentMediaTime()) forKey:@"ts_firstbyte"];
        if(self.autoCancelOutdatedChunks){
            // We can cancel all previous downloads as well - in case they was loaded not so fast
            @synchronized(self){
                for(NSString* taskUrlPrev in self.downloaderDatas){
                    NSMutableDictionary* prevTaskData = self.downloaderDatas[taskUrlPrev];
                    if([[prevTaskData objectForKey:@"chunkSeq"] integerValue] == chunkNum-1){
                        if([self cancelDownloadForUrl:taskUrlPrev]){
                             VLLog(@"DVGPlayerChunkLoader: cancelling outdated %@", taskUrlPrev);
                        }
                    }
                }
            }
        }
    }
    NSMutableData* receivedData = [taskData objectForKey:@"data"];
    @synchronized (receivedData) {
        [receivedData appendData:data];
        self.statDownloadedBytes += data.length;
    }
    NSString* fileuri = [taskData objectForKey:@"fileuri"];
    if([fileuri length] > 0){
        [self.unixpusher llhlsDataChange:fileuri finalLength:0];
    }
    if(data.length > 0){
        [self.statDataPoints addObject:@[@([DVGPlayerServerChecker unixStamp]), @(data.length), @(chunkNum)]];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSMutableDictionary* taskData = [self findTaskdataByUrl:task.originalRequest.URL.absoluteString];
    @synchronized(self){
        if(taskData != nil){
            double dnl_start = [[taskData objectForKey:@"ts_start"] doubleValue];
            double dnl_stop = CACurrentMediaTime();
            [taskData setObject:@(dnl_stop) forKey:@"ts_stop"];
            // Parsing results
            NSString* taskUrl = taskData[@"url"];
            NSData* loadedData = [taskData objectForKey:@"data"];
            if(self.onChunkDownloaded != nil){
                self.onChunkDownloaded(taskUrl, loadedData, taskData, error);
            }
            [taskData removeObjectForKey:@"downloadTask"];
            NSString* fileuri = [taskData objectForKey:@"fileuri"];
            if([fileuri length] > 0){
                [self.unixpusher llhlsDataChange:fileuri finalLength:(error==nil)?[loadedData length]:-1];
                VLLog(@"DVGPlayerChunkLoader: download finished for %@ (time=%.02f) err=%@", fileuri, (dnl_start>0)?(dnl_stop-dnl_start):0.0, [error localizedDescription]);
            }
            //if(error != nil){
            //    self.statChunkDownloadTime = 50;// Max
            //}else if(dnl_start > 0){
            //    self.statChunkDownloadTime = (dnl_stop-dnl_start);
            //}
            self.downloaderDatas[taskUrl] = @{};// Clearing here, UnixPusherGarbageCollector will release initial data later
        }else{
            VLLog(@"DVGPlayerChunkLoader: ERROR: taskData not found, %@ err=%@", task.originalRequest, error);
        }
        self.activeDownloads--;
    }
}

- (void)statsFillHotData:(NSMutableDictionary* _Nonnull)stats {
    stats[kDVGPlayerStatsDownloadedBytes] = @(self.statDownloadedBytes);
    stats[kDVGPlayerStatsConsumedBytes] = @(self.unixpusher.statConsumedBytes);
    //stats[kDVGPlayerStatsDownloadTs] = @(self.statChunkDownloadTime);
    if(self.statDataPoints.count > 0){
        NSInteger subrangeFrom = self.statDataPoints.count-1000;
        if(subrangeFrom<0){
            subrangeFrom = 0;
        }
        stats[kDVGPlayerStatsActiveDnChunk] = [self.statDataPoints subarrayWithRange:NSMakeRange(subrangeFrom, self.statDataPoints.count-subrangeFrom)];
    }
}
@end
