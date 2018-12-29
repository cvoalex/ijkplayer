
#import <Foundation/Foundation.h>

static NSString* const kDVGPlayerServerCheckerDwnMetaTempl = @"{url_base}getMeta?playlist={name}";
@interface DVGPlayerServerChecker : NSObject // <SimplePingDelegate>

- (void)addServers:(NSArray*)serverUrls;
- (NSString*)getOptimalServer;

+ (DVGPlayerServerChecker*)getActiveCheckerForURL:(NSString*)serverConfigUrl;// TBD: configure URL for server lists
@end
