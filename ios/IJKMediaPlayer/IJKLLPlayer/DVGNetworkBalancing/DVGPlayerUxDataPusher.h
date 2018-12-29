#ifndef DVGPlayerUxDataPusher_h
#define DVGPlayerUxDataPusher_h

@interface DVGPlayerUxDataPusher : NSObject
@property (atomic, assign) NSInteger statConsumedBytes;

- (void)llhlsUnixPusherInit:(NSString*)socpath andContinue:(dispatch_block_t)onOk;
- (void)llhlsDataPrepare:(NSMutableDictionary*)taskData uri:(NSString*)unixpath;
- (void)llhlsDataChange:(NSString*)uri finalLength:(NSInteger)finalLen;
- (void)llhlsDataFlushAllConnections;
- (void)collectGarbage;
- (void)finalizeThis;
@end

#endif
