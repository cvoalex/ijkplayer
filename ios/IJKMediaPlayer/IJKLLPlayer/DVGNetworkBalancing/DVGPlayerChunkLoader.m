#import <Foundation/Foundation.h>
#import "DVGLLPlayerView.h"
#import "DVGPlayerChunkLoader.h"
#import "DVGPlayerFileUtils.h"
#import "DVGPlayerUxDataPusher.h"
//#import "AFxNetworking.h"
#define kDVGPlayerLoaderCacheFolder @"playerloader"



@interface DVGPlayerChunkLoader () <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
//@property (atomic,strong) AFxJSONResponseSerializer* httpManagerSerializer;
//@property (atomic,strong) AFxHTTPSessionManager* httpManager;
@property (atomic, strong) NSMutableArray* filelist;
@property (atomic, strong) NSMutableDictionary* downloaderDatas;
@property (atomic, strong) NSTimer *trackTimer;
@property (atomic, assign) NSInteger activeDownloads;
@property (atomic, assign) NSInteger filelistChunkNext;
@property (atomic, assign) double filelistStartTs;
@property (atomic, assign) double chunkDuration;
@property (atomic, assign) double chunkLoadingTimeout;
@property (atomic, assign) NSInteger chunkPrefetchCount;
@property (atomic, assign) double unixpusherGarbageColTs;
@property (atomic, strong) DVGPlayerUxDataPusher* unixpusher;
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

- (void)dealloc {
    [self resetPendingDownloads];
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

- (void)resetPendingDownloads {
    //NSLog(@"resetPendingDownloads");
    @synchronized(self){
        if(self.filelist == nil){
            self.filelist = @[].mutableCopy;
            self.downloaderDatas = @{}.mutableCopy;
        }
        if(self.trackTimer != nil){
            [self.trackTimer invalidate];
            self.trackTimer = nil;
        }
        // Do NOT stopping downloads. Active task may continue, since downloader will not go too much to the future
        // and this will save time for resking data by ffmpeg
//        for(NSString* url in self.downloaderDatas){
//            NSMutableDictionary* taskData = self.downloaderDatas[url];
//            NSURLSessionDataTask *dataTask = taskData[@"downloadTask"];
//            [dataTask cancel];
//        }
        if(self.unixpusher == nil){
            self.unixpusher = [[DVGPlayerUxDataPusher alloc] init];
        }
        [self.unixpusher llhlsDataResetAll];
        [self.filelist removeAllObjects];
        self.filelistChunkNext = 0;
        self.activeDownloads = 0;
    }
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

- (void)downloadChunksFromList:(NSArray*)urls prefetchLimit:(NSInteger)chunksInAdvance avgChunkDuration:(float)durSec {
    dispatch_async(dispatch_get_main_queue(), ^{// special for NSTimer
        if(self.filelist == nil){
            [self resetPendingDownloads];
        }
        self.chunkDuration = durSec;
        self.chunkPrefetchCount = chunksInAdvance;
        self.chunkLoadingTimeout = self.chunkDuration*(1+self.chunkPrefetchCount)+kPlayerAvgInBufftime;
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
    });
}

- (void)checkForNextDownload {
    //NSLog(@"checkForNextDownload %i %i",self.activeDownloads, self.chunkPrefetchCount);
    double ts = CACurrentMediaTime();
    double max_dnlpossible_ts = self.filelistStartTs+(self.filelistChunkNext-self.chunkPrefetchCount)*self.chunkDuration;
    if(self.activeDownloads < self.chunkPrefetchCount && ts >= max_dnlpossible_ts){
        [self downloadNextChunk];
    }
    if(ts > self.unixpusherGarbageColTs + 5.0){
        self.unixpusherGarbageColTs = ts;
        [self.unixpusher collectGarbage];
    }
}

- (void)downloadNextChunk {
    //NSLog(@"downloadNextChunk %i %i",self.filelistChunkNext, [self.filelist count]);
    if(self.filelistChunkNext >= [self.filelist count]){
        return;
    }
    NSURLSessionDataTask *downloadTask = nil;
    @synchronized(self){
        NSInteger chunkNum = self.filelistChunkNext;
        self.filelistChunkNext++;
        NSArray* chunkMeta = [self.filelist objectAtIndex:chunkNum];
        NSString* chunkUrl = [chunkMeta objectAtIndex:0];
        NSString* chunkUnixSoc = [chunkMeta objectAtIndex:1];
        NSString* chunkFileuri = [chunkMeta objectAtIndex:2];
        if([self findTaskdataByUrl:chunkUrl] != nil){
            // Already in progress, skipping
            // VLLog(@"DVGPlayerChunkLoader: downloadNextChunk already in progress, %@", chunkUrl);
            return;
        }
        self.activeDownloads++;
        VLLog(@"DVGPlayerChunkLoader: downloading %@", chunkUrl);
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
        //[taskData setObject:chunkUnixSoc forKey:@"unixsoc"];
        [taskData setObject:chunkFileuri forKey:@"fileuri"];
        [taskData setObject:@(chunkNum) forKey:@"chunkSeq"];
        NSMutableData* receivedData = [[NSMutableData alloc] init];
        [receivedData setLength:0];
        [taskData setObject:receivedData forKey:@"data"];
        self.downloaderDatas[chunkUrl] = taskData;
        if([chunkFileuri length] > 0){
            [self.unixpusher llhlsDataInit:taskData socket:chunkUnixSoc uri:chunkFileuri];
        }
    }
    [downloadTask resume];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    NSMutableDictionary* taskData = [self findTaskdataByUrl:dataTask.originalRequest.URL.absoluteString];
    if(taskData == nil){
        VLLog(@"DVGPlayerChunkLoader: ERROR: taskData not found, %@", dataTask.originalRequest);
        return;
    }
    [taskData setObject:@(CACurrentMediaTime()) forKey:@"ts_start"];
    completionHandler(NSURLSessionResponseAllow);
}
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSMutableDictionary* taskData = [self findTaskdataByUrl:dataTask.originalRequest.URL.absoluteString];
    if(taskData == nil){
        VLLog(@"DVGPlayerChunkLoader: ERROR: taskData not found, %@", dataTask.originalRequest);
        return;
    }
    if([taskData objectForKey:@"ts_firstbyte"] == nil){
        [taskData setObject:@(CACurrentMediaTime()) forKey:@"ts_firstbyte"];
    }
    NSMutableData* receivedData = [taskData objectForKey:@"data"];
    @synchronized (receivedData) {
        [receivedData appendData:data];
    }
    NSString* fileuri = [taskData objectForKey:@"fileuri"];
    if([fileuri length] > 0){
        [self.unixpusher llhlsDataChange:fileuri finalLength:0];
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
            self.downloaderDatas[taskUrl] = @{};// Clearing here, UnixPusherGarbageCollector will release initial data later
        }else{
            VLLog(@"DVGPlayerChunkLoader: ERROR: taskData not found, %@ err=%@", task.originalRequest, error);
        }
        self.activeDownloads--;
    }
}
@end
