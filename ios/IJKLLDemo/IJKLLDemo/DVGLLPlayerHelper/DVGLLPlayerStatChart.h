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
- (void)updateTotalData:(double)dataCount;
- (void)onUpdateFrame:(CGRect)chartFrame;
@end

#endif /* DVGLLPlayerStatChart_h */
