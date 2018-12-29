//
//  DVGLLPlayerStatChart.h
//  DVGLLPlayer
//
//  Created by IPv6 on 18/10/2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#ifndef DVGLLPlayerStatChart_h
#define DVGLLPlayerStatChart_h

#import "FSLineChart.h"
@class DVGLLPlayerView;

@interface DVGLLPlayerStatChart : FSLineChart
- (void)trackingStart;
- (void)trackingStop;
- (void)onUpdateFrame:(CGRect)chartFrame;
- (void)onStatsUpdated:(NSDictionary *)stats inView:(DVGLLPlayerView*)playerView;
@end

@interface DVGLLPlayerStatLogs : UILabel
- (void)addLogLine:(NSString*)logline;
@end

#endif /* DVGLLPlayerStatChart_h */
