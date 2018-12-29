//
//  DVGChunkServer.h
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/27/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

#ifndef DVGChunkServer_h
#define DVGChunkServer_h

@protocol DVGChunkServerDelegate <NSObject>

- (void)unixServerReady;
- (NSData* _Nullable)requestData:(NSString* _Nonnull)key dataSent:(NSInteger)offset;
- (NSData* _Nullable)requestData:(NSString* _Nonnull)key;

@end

@interface DVGChunkServer : NSObject
@property (weak, atomic) id<DVGChunkServerDelegate> _Nullable delegate;
@property (atomic, assign) NSInteger statConsumedBytes;
- (void)run:(NSString*_Nonnull)socketPath;
- (void)hasNewData:(NSString* _Nonnull)key;
- (void)endDataTransmission:(NSString* _Nonnull)key;
- (void)closeDataConnection:(NSString* _Nonnull)key;
@end

#endif /* DVGChunkServer_h */
