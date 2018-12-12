//
//  DVGLLPlayerStatChart.m
//  DVGLLPlayerFramework
//
//  Created by IPv6 on 18/10/2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "DVGLLPlayerView.h"

#import <QuartzCore/QuartzCore.h>
#import "DVGLLPlayerStatChart.h"
#import "FSLineChart.h"
#import "UIColor+FSPalette.h"

@interface DVGLLPlayerStatChart ()
@property (weak) DVGLLPlayerView *llPlayerView;

@property (assign) NSInteger delayItems;
@property (assign) double delayChartFirstUpdate;
@property (strong, nonatomic) NSMutableArray* delayData;
@property (strong, nonatomic) NSMutableArray* onbufData;
@property (strong, nonatomic) NSMutableArray* strmdData;
@property (strong, nonatomic) NSMutableArray* stampData;

@property (atomic, strong) NSTimer *chartTrackTimer;
@property (atomic, strong) NSDictionary* chartLastStats;
@end

@implementation DVGLLPlayerStatChart

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self chartInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self chartInit];
    }
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [self chartInit];
}

- (void)chartInit
{
    self.delayItems = 1000;
    self.delayData = @[].mutableCopy;
    self.onbufData = @[].mutableCopy;
    self.strmdData = @[].mutableCopy;
    self.stampData = @[].mutableCopy;
    
    FSLineChart* delayChart = self;
    delayChart.backgroundColor = [UIColor clearColor];
    
    delayChart.backgroundColor = [UIColor clearColor];
    delayChart.animationDuration = 0;
    delayChart.verticalGridStep = 5;
    delayChart.horizontalGridStep = 9;
    delayChart.labelForIndex = ^NSString *(NSUInteger index) {
        NSInteger stmpd = [self.stampData count] - (self.delayItems-index);
        if(stmpd < 0){
            return @"-";
        }
        double stmp = [self.stampData[stmpd] doubleValue];
        double secs = (stmp-self.delayChartFirstUpdate);
        if(secs < 0.1){
            return @"-";
        }
        return [NSString stringWithFormat:@"%.01fs", secs];
    };
    delayChart.labelForValue = ^NSString *(CGFloat index) {
        return [NSString stringWithFormat:@"%0.02fs",index];
    };
}

- (void)trackingStart
{
    [self trackingStop];
    self.chartTrackTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                            target:self
                                                          selector:@selector(checkChartupdate)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)trackingStop
{
    [self.chartTrackTimer invalidate];
    self.chartTrackTimer = nil;
}

- (void)onUpdateFrame:(CGRect)chartFrame
{
    FSLineChart* delayChart = self;
    if(fabs(chartFrame.origin.x-delayChart.frame.origin.x)
       +fabs(chartFrame.origin.y-delayChart.frame.origin.y)
       +fabs(chartFrame.size.width-delayChart.frame.size.width)
       +fabs(chartFrame.size.height-delayChart.frame.size.height) > 1.0){
        delayChart.frame = chartFrame;
        [delayChart addAxisLabels];
        [delayChart setNeedsLayout];
    }
}

- (void)onStatsUpdated:(NSDictionary *)stats inView:(DVGLLPlayerView*)playerView {
    if(self.chartLastStats == nil){
        self.delayChartFirstUpdate = CACurrentMediaTime();
    }
    self.chartLastStats = [stats copy];
    self.llPlayerView = playerView;
    double stmp = CACurrentMediaTime();
    [self.stampData addObject:@(stmp)];
    double rtdelay = [stats[kDVGPlayerStatsRtLate] doubleValue];
    [self.delayData addObject:@(fabs(rtdelay))];
    double bfdelay = [stats[kDVGPlayerStatsBuffDelay] doubleValue];
    [self.onbufData addObject:@(fabs(bfdelay))];
    double stdelay = [stats[kDVGPlayerStatsUploaderDelay] doubleValue];
    [self.strmdData addObject:@(fabs(stdelay))];
}

-(void)checkChartupdate {
    if(self.chartLastStats == nil){
        return;
    }
    FSLineChart* delayChart = self;
    // Adding interpolated data
    NSMutableDictionary* stats = @{}.mutableCopy;
    [self.llPlayerView statsFillHotData:stats];
    
    double stmp = CACurrentMediaTime();
    [self.stampData addObject:@(stmp)];
    double rtcdelay = [self.chartLastStats[kDVGPlayerStatsRtLate] doubleValue];
    if(rtcdelay > 0){
        double ptsActiveDiff = [stats[kDVGPlayerStatsRtLateLocalPtsLast] doubleValue] - [self.chartLastStats[kDVGPlayerStatsRtLateLocalPts] doubleValue];
        double ltsActiveDiff = [stats[kDVGPlayerStatsRtLateLocalTsLast] doubleValue] - [self.chartLastStats[kDVGPlayerStatsRtLateLocalTs] doubleValue];
        rtcdelay = fabs(rtcdelay)+(ltsActiveDiff-ptsActiveDiff);
    }
    [self.delayData addObject:@(fabs(rtcdelay))];
    double bfdelay = [[self.onbufData lastObject] doubleValue];
    [self.onbufData addObject:@(fabs(bfdelay))];
    double stdelay = [[self.strmdData lastObject] doubleValue];
    [self.strmdData addObject:@(fabs(stdelay))];
    
    //
    double rtdelay;
    NSMutableArray* data1 = @[].mutableCopy;
    for(NSInteger i = self.delayItems-1; i >= 0; i--){
        NSInteger revIdx = [self.delayData count]-i-1;
        if(revIdx >= 0){
            rtdelay = [self.delayData[revIdx] doubleValue];
            if (rtdelay < -1 || rtdelay > 10){
                rtdelay = 0;
            }
            [data1 addObject:@(rtdelay)];
        }else{
            [data1 addObject:@(0)];
        }
    }
    delayChart.color = [UIColor fsLightBlue];
    delayChart.fillColor = [[UIColor fsLightBlue] colorWithAlphaComponent:0.25];
    [delayChart clearChartData];
    [delayChart setChartBaseData:data1];
    [delayChart addAxisLabels];
    
    NSMutableArray* data2 = @[].mutableCopy;
    for(NSInteger i = self.delayItems-1; i >= 0; i--){
        NSInteger revIdx = [self.onbufData count]-i-1;
        if(revIdx >= 0){
            rtdelay = [self.onbufData[revIdx] doubleValue];
            if (rtdelay < -1 || rtdelay > 10){
                rtdelay = 0;
            }
            [data2 addObject:@(fabs(rtdelay))];
        }else{
            [data2 addObject:@(0)];
        }
    }
    delayChart.color = [UIColor fsPink];
    delayChart.fillColor = nil;
    [delayChart addChartLayerWithData:data2];
    
    NSMutableArray* data3 = @[].mutableCopy;
    for(NSInteger i = self.delayItems-1; i >= 0; i--){
        NSInteger revIdx = [self.strmdData count]-i-1;
        if(revIdx >= 0){
            rtdelay = [self.strmdData[revIdx] doubleValue];
            if (rtdelay < -1 || rtdelay > 10){
                rtdelay = 0;
            }
            [data3 addObject:@(fabs(rtdelay))];
        }else{
            [data3 addObject:@(0)];
        }
    }
    delayChart.color = [UIColor fsYellow];
    delayChart.fillColor = nil;
    [delayChart addChartLayerWithData:data3];
    // cleanup
    while([self.stampData count]> self.delayItems){
        [self.stampData removeObjectAtIndex:0];
        [self.delayData removeObjectAtIndex:0];
        [self.onbufData removeObjectAtIndex:0];
        [self.strmdData removeObjectAtIndex:0];
    }
}

@end

@interface DVGLLPlayerStatLogs()
@end

@implementation DVGLLPlayerStatLogs
- (void)addLogLine:(NSString*)logline {
    static NSString* loglineFull = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(loglineFull == 0){
            loglineFull = @"";
            self.text = @"";
            self.numberOfLines = 0;
        }
        NSString* loglinep = @"";
        if(logline.length > 0){
            loglinep = [logline stringByAppendingString:@"\n"];
        }
        loglinep = [loglinep stringByAppendingString:loglineFull];
        loglineFull = loglinep;
        if(loglineFull.length > 2000){
            loglineFull = [loglineFull substringWithRange:NSMakeRange(0,2000)];
        }
        // Faking vertical align
        self.text = [loglineFull stringByAppendingString:@"\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"];
    });
}
@end
