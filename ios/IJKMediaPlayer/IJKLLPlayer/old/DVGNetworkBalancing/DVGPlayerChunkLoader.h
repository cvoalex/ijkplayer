//
//  DVGPlayerChunkLoader.h
//  DVGLLPlayer
//
//  Created by IPv6 on 03/12/2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#ifndef DVGPlayerChunkLoader_h
#define DVGPlayerChunkLoader_h

typedef BOOL (^OnDVGPlayerChunkLoaderDownBlock)(NSString* _Nonnull url, NSData* _Nullable data, NSDictionary* fulldata, NSError * _Nullable error);
@interface DVGPlayerChunkLoader : NSObject
@property (atomic, strong) OnDVGPlayerChunkLoaderDownBlock onChunkDownloaded;

- (NSArray*)getChunkUnixPairForUrl:(NSString*)url;
- (void)downloadChunksFromList:(NSArray*)urls prefetchLimit:(NSInteger)chunksInAdvance avgChunkDuration:(float)durSec;
- (void)resetPendingDownloads;

@end

#endif /* DVGPlayerChunkLoader_h */
