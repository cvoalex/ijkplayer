//
//  DVGPlayerChunkLoader.h
//  DVGLLPlayer
//
//  Created by IPv6 on 03/12/2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#ifndef DVGPlayerChunkLoader_h
#define DVGPlayerChunkLoader_h

static NSString* _Nonnull const kDVGPlayerStatsDownloadedBytes = @"kDVGPlayerStatsDownloadedBytes";
static NSString* _Nonnull const kDVGPlayerStatsConsumedBytes = @"kDVGPlayerStatsConsumedBytes";
//static NSString* _Nonnull const kDVGPlayerStatsDownloadTs = @"kDVGPlayerStatsDownloadTs";
static NSString* _Nonnull const kDVGPlayerStatsActiveDnChunk = @"kDVGPlayerStatsActiveDnChunkId";

typedef BOOL (^OnDVGPlayerChunkLoaderDownBlock)(NSString* _Nonnull url, NSData* _Nullable data, NSDictionary* fulldata, NSError * _Nullable error);
@interface DVGPlayerChunkLoader : NSObject
@property (atomic, strong) OnDVGPlayerChunkLoaderDownBlock onChunkDownloaded;
@property (atomic, assign) BOOL autoCancelOutdatedChunks;

- (NSArray*)getChunkUnixPairForUrl:(NSString*)url;
- (void)prepareForAvgChunkDuration:(float)durSec prefetchCount:(NSInteger)prefetchcnt;
- (void)prepareChunksTimingForList:(NSDictionary*)mapUrlToStartStamp;
- (BOOL)downloadChunksFromList:(NSArray*)urls andContinue:(dispatch_block_t)onOk;
- (void)finalizeThis;

- (void)statsFillHotData:(NSMutableDictionary* _Nonnull)stats;
@end

#endif /* DVGPlayerChunkLoader_h */
