#ifndef DVGPlayerUxDataPusher_h
#define DVGPlayerUxDataPusher_h

@interface DVGPlayerUxDataPusher : NSObject

- (void)llhlsDataInit:(NSMutableDictionary*)taskData socket:(NSString*)socpath uri:(NSString*)unixpath;
- (void)llhlsDataChange:(NSString*)uri finalLength:(NSInteger)finalLen;
- (void)llhlsDataResetAll;
- (void)collectGarbage;
@end

#endif
