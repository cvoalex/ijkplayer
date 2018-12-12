#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "DVGPlayerFileUtils.h"
#import "DVGPlayerServerChecker.h"
#import "DVGLLPlayerView.h"
#include <stdlib.h>
#define DVGPINGER_UNKNOWNTIME 1000.0f


@interface DVGPlayerServerChecker()
//@property(nonatomic, strong) SimplePing* simplePing;
@property(nonatomic, strong) NSURLSession* simplePing;
@property(nonatomic, strong) NSString* simplePingHost;
@property(nonatomic, assign) double simplePingStartAt;
@property(nonatomic, strong) NSMutableDictionary* serverTimes;
@property(nonatomic, strong) NSMutableArray* servers2test;
//@property(nonatomic, strong) NSMutableArray* serversPings;
@end

@implementation DVGPlayerServerChecker
+ (DVGPlayerServerChecker*)getActiveCheckerForURL:(NSString*)serverConfigUrl
{
    static dispatch_once_t pred = 0;
    __strong static DVGPlayerServerChecker* mainChecker = nil;
    dispatch_once(&pred, ^{
        mainChecker = [[DVGPlayerServerChecker alloc] init];
    });
    static int isInited = 0;
    if(isInited == 0){
        isInited++;
        // TBD: Read config URL if not yet and save files
        //[serverChecker addServers: @[@"http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/",@"http://ec2-54-159-151-197.compute-1.amazonaws.com:3000/"]];
        //[mainChecker addServers: @[@"http://18.213.85.167:3000/",@"http://d1d7bq76ey2psd.cloudfront.net/"]];
        [mainChecker addServers: @[@"http://18.213.85.167:3000/"]];
    }
    return mainChecker;
}

- (void)addServers:(NSArray*)serverUrls
{
    VLLog(@"DVGPlayerServerChecker: checking urls %@", serverUrls);
    if(self.serverTimes == nil){
        self.serverTimes = @{}.mutableCopy;
        self.servers2test = @[].mutableCopy;
    }
    for(NSString* url in serverUrls){
        if(self.serverTimes[url] == nil){
            self.serverTimes[url] = @(DVGPINGER_UNKNOWNTIME);
            [self.servers2test addObject:url];
        }
    }
    if(self.simplePing == nil){
        [self checkNextServer];
    }
}

- (NSString*)getOptimalServer
{
    double maxtime = DVGPINGER_UNKNOWNTIME;
    NSString* optimal = nil;
    for(NSString* url in self.serverTimes){
        double srvt = [self.serverTimes[url] doubleValue];
        if(srvt < maxtime){
            maxtime = srvt;
            optimal = url;
        }
    }
    if(optimal == nil){
        NSArray* allUrls = [self.serverTimes allKeys];
        NSUInteger randomIdx = arc4random_uniform([allUrls count]);
        optimal = [allUrls objectAtIndex:randomIdx];
    }
    VLLog(@"DVGPlayerServerChecker: getOptimalServer: url=%@, time=%.02f",optimal,maxtime);
    return optimal;
}

- (void)checkNextServer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURLSession* pinger = nil;
        @synchronized (self) {
            if([self.servers2test count] == 0 || self.simplePing != nil){
                return;
            }
            NSUInteger randomIdx = arc4random_uniform([self.servers2test count]);
            NSString* address = [[self.servers2test objectAtIndex:randomIdx] copy];
            self.simplePingHost = address;
            [self.servers2test removeObjectAtIndex:randomIdx];
            self.simplePingStartAt = CACurrentMediaTime();
            //pinger = [[SimplePing alloc] initWithHostName:address];
            //self.simplePing = pinger;
            //self.simplePing.delegate = self;
            //[self.simplePing start];
            NSString *serverTestUrl = kDVGPlayerServerCheckerDwnMetaTempl;
            serverTestUrl = [serverTestUrl stringByReplacingOccurrencesOfString:@"{url_base}" withString:address];
            serverTestUrl = [serverTestUrl stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            VLLog(@"DVGPlayerServerChecker: checkNextServer: url=%@",address);
            NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverTestUrl]
                                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                               timeoutInterval:2.0];
            self.simplePing = session;
            [[session dataTaskWithRequest:request
                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        if (!error) {
                            [self successPing];
                        } else {
                            [self failPing:[error localizedDescription]];
                        }
                    }] resume];
        }
        //dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        //    if (self.simplePing != nil && self.simplePing == pinger) { // If it hasn't already been killed, then it's timed out
        //        [self failPing:@"timeout"];
        //    }
        //});
    });
}

- (void)dealloc {
	self.simplePing = nil;
}

- (void)killPing {
    if(self.simplePing != nil){
        //[self.simplePing stop];
        //if(self.serversPings == nil){
        //    self.serversPings = @[].mutableCopy;
        //}
        //[self.serversPings addObject:self.simplePing];
        self.simplePing = nil;
    }
    [self checkNextServer];
}

- (void)successPing {
    @synchronized (self) {
        NSString* url = self.simplePingHost;//self.simplePing.hostName;
        double simplePingStopAt = CACurrentMediaTime();
        double time2server = simplePingStopAt-self.simplePingStartAt;
        self.serverTimes[url] = @(time2server);
        VLLog(@"DVGPlayerServerChecker: successPing %@, time=%.02f", url, time2server);
    }
    [self killPing];
}

- (void)failPing:(NSString*)reason {
    @synchronized (self) {
        NSString* url = self.simplePingHost;//self.simplePing.hostName;
        self.serverTimes[url] = @(DVGPINGER_UNKNOWNTIME+1);
        VLLog(@"DVGPlayerServerChecker: failPing %@: %@", url, reason);
    }
	[self killPing];
}

@end
