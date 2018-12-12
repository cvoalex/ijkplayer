//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#ifndef DVGPlayerFileUtils_h
#define DVGPlayerFileUtils_h

#define VLLog(frmt, ...) [VLLogger LogFormat:frmt, ##__VA_ARGS__]
@interface VLLogger: NSObject
+ (NSString*)LogFormat:(NSString *)format, ...;
+ (NSString*)GetLogs:(BOOL)andReset;
@end

@interface DVGPlayerFileUtils : NSFileManager

+ (instancetype)sharedManager;
+ (NSString *)cachesDirectory;
+ (NSString *)cachePathForKey:(NSString*)key;
- (void)deleteFilesAtPath:(NSString *)path;
- (long)cleanupCachesAtPath:(NSString *)path maxAge:(NSTimeInterval)maxAge maxTotalSize:(NSUInteger)maxTotalSize;
- (BOOL)createDirectoryAtPath:(NSString *)path;

+ (id _Nullable)overloadConfigurationKey:(NSString* _Nonnull)configKey value:(id _Nullable)configValue;
+ (id _Nullable)configurationValueForKey:(NSString* _Nonnull)configKey;
@end

#endif
