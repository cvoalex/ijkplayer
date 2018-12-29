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
#import "DVGPlayerChunkLoader.h"
#import "DVGPlayerServerChecker.h"

#import <QuartzCore/QuartzCore.h>
#import "DVGLLPlayerStatChart.h"
#import "FSLineChart.h"
#import "UIColor+FSPalette.h"

@interface DVGLLPlayerStatChart ()
@property (atomic, weak) DVGLLPlayerView *llPlayerView;

@property (atomic, assign) NSInteger delayItems;
@property (atomic, assign) NSInteger dppItems;
@property (atomic, assign) double delayChartFirstUpdate;
@property (strong, nonatomic) NSMutableArray* delayData;
@property (strong, nonatomic) NSMutableArray* onbufDataV;
@property (strong, nonatomic) NSMutableArray* onbufDataA;
@property (strong, nonatomic) NSMutableArray* strmdData;
@property (strong, nonatomic) NSMutableArray* stampData;
//@property (strong, nonatomic) NSMutableArray* bytesData;

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
    self.delayItems = 50;
    self.dppItems = 1000;
    self.delayData = @[].mutableCopy;
    self.onbufDataV = @[].mutableCopy;
    self.onbufDataA = @[].mutableCopy;
    self.strmdData = @[].mutableCopy;
    self.stampData = @[].mutableCopy;
    //self.bytesData = @[].mutableCopy;
    
    FSLineChart* delayChart = self;
    delayChart.backgroundColor = [UIColor clearColor];
    
    delayChart.backgroundColor = [UIColor clearColor];
    delayChart.animationDuration = 0;
    delayChart.verticalGridStep = 5;
    delayChart.horizontalGridStep = 9;
    delayChart.labelForIndex = ^NSString *(NSUInteger index) {
        double secs = 0.0;
        @synchronized(self){
            NSInteger stmpd = [self.stampData count] - (self.delayItems-index);
            if(stmpd < 0 || stmpd >= self.stampData.count){
                return @"-";
            }
            double stmp = [self.stampData[stmpd] doubleValue];
            secs = (stmp-self.delayChartFirstUpdate);
            if(secs < 0.1){
                return @"-";
            }
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
}

- (void)trackingStop
{
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
    @synchronized(self){
        if(self.chartLastStats == nil){
            self.delayChartFirstUpdate = [DVGPlayerServerChecker unixStamp];
        }
        self.chartLastStats = [stats copy];
        self.llPlayerView = playerView;
        double stmp = [DVGPlayerServerChecker unixStamp];
        [self.stampData addObject:@(stmp)];
        double rtdelayT = [stats[kDVGPlayerStatsRtLate] doubleValue];
        [self.delayData addObject:@(rtdelayT)];
        double bfdelayV = [stats[kDVGPlayerStatsBuffDelayV] doubleValue];
        [self.onbufDataV addObject:@(bfdelayV)];
        double bfdelayA = [stats[kDVGPlayerStatsBuffDelayA] doubleValue];
        [self.onbufDataA addObject:@(bfdelayA)];
        double stdelay = [stats[kDVGPlayerStatsUploaderDelay] doubleValue];
        [self.strmdData addObject:@(stdelay)];
        //double btyesDiff = (double)([stats[kDVGPlayerStatsDownloadedBytes] doubleValue] - [stats[kDVGPlayerStatsConsumedBytes] doubleValue]);
        //double btyesDiff = [stats[kDVGPlayerStatsDownloadTs] doubleValue];
        //[self.bytesData addObject:@(btyesDiff)];
        NSInteger reseek_state = [stats[kDVGPlayerStatsReseekState] integerValue];
        
        FSLineChart* delayChart = self;
        double rtdelay;
        double rtdelayBlueMax = -999;
        
        // Blue - Rt-delay
        NSMutableArray* data1 = @[].mutableCopy;
        for(NSInteger i = self.delayItems-1; i >= 0; i--){
            NSInteger revIdx = [self.delayData count]-i-1;
            if(revIdx >= 0){
                rtdelay = [self.delayData[revIdx] doubleValue];
                rtdelay = MAX(0,MIN(50,rtdelay));
                if(rtdelay > rtdelayBlueMax){
                    rtdelayBlueMax = rtdelay;
                }
                [data1 addObject:@(rtdelay)];
            }else{
                [data1 addObject:@(0)];
            }
        }
        if(reseek_state > 0){
            delayChart.color = [[UIColor fsLightBlue] colorWithAlphaComponent:0.5];
        }else if(reseek_state < 0){
            delayChart.color = [UIColor fsDarkBlue];
        }else{
            delayChart.color = [UIColor fsLightBlue];
        }
        delayChart.fillColor = [delayChart.color colorWithAlphaComponent:0.25];
        [delayChart clearChartData];
        [delayChart setChartBaseData:data1];
        [delayChart addAxisLabels];

        // Orange - bytes
//        NSMutableArray* dataBt = @[].mutableCopy;
//        for(NSInteger i = self.delayItems-1; i >= 0; i--){
//            NSInteger revIdx = [self.onbufDataV count]-i-1;
//            if(revIdx >= 0){
//                rtdelay = [self.bytesData[revIdx] doubleValue];
//                rtdelay = MAX(0,rtdelay);
//                [dataBt addObject:@(fabs(rtdelay))];
//            }else{
//                [dataBt addObject:@(0)];
//            }
//        }
//        delayChart.color = [UIColor fsOrange];
//        delayChart.fillColor = nil;
//        [delayChart addChartLayerWithData:dataBt stroke:YES points:NO];
        
        // Pink - buffer (video)
        NSMutableArray* data2v = @[].mutableCopy;
        for(NSInteger i = self.delayItems-1; i >= 0; i--){
            NSInteger revIdx = [self.onbufDataV count]-i-1;
            if(revIdx >= 0){
                rtdelay = [self.onbufDataV[revIdx] doubleValue];
                rtdelay = MAX(0,MIN(50,rtdelay));
                [data2v addObject:@(fabs(rtdelay))];
            }else{
                [data2v addObject:@(0)];
            }
        }
        delayChart.color = [UIColor fsPink];
        delayChart.fillColor = nil;
        [delayChart addChartLayerWithData:data2v stroke:YES points:NO];
        
        // Pink - buffer (audio)
        NSMutableArray* data2a = @[].mutableCopy;
        for(NSInteger i = self.delayItems-1; i >= 0; i--){
            NSInteger revIdx = [self.onbufDataA count]-i-1;
            if(revIdx >= 0){
                rtdelay = [self.onbufDataA[revIdx] doubleValue];
                rtdelay = MAX(0,MIN(50,rtdelay));
                [data2a addObject:@(fabs(rtdelay))];
            }else{
                [data2a addObject:@(0)];
            }
        }
        delayChart.color = [[UIColor fsPink] colorWithAlphaComponent:0.7];
        delayChart.fillColor = nil;
        [delayChart addChartLayerWithData:data2a stroke:YES points:NO];

        // Yellow - Streamer upload delay
        NSMutableArray* data3 = @[].mutableCopy;
        for(NSInteger i = self.delayItems-1; i >= 0; i--){
            NSInteger revIdx = [self.strmdData count]-i-1;
            if(revIdx >= 0){
                rtdelay = [self.strmdData[revIdx] doubleValue];
                rtdelay = MAX(0,MIN(50,rtdelay));
                [data3 addObject:@(fabs(rtdelay))];
            }else{
                [data3 addObject:@(0)];
            }
        }
        delayChart.color = [UIColor fsYellow];
        delayChart.fillColor = nil;
        [delayChart addChartLayerWithData:data3 stroke:YES points:NO];
        
        // Adding data points
        double maxItems = (double)self.delayItems-1;
        NSArray* dataPoints = stats[kDVGPlayerStatsActiveDnChunk];
        static NSArray* dpColors = nil;
        if(dpColors == nil){
            dpColors = @[[UIColor fsYellow], [UIColor fsRed], [UIColor fsGreen], [UIColor fsLightBlue], [UIColor fsLightGray]];
        }
        for(int i = 0; i < self.dppItems; i++){
            NSInteger dpIndex = dataPoints.count-1-i;
            if(dpIndex < 0){
                break;
            }
            NSArray* datapoint = dataPoints[dpIndex];
            double datapointStmp = [datapoint[0] doubleValue];
            double datapointSz = [datapoint[1] doubleValue];
            NSInteger datapointId = [datapoint[2] integerValue];
            double chartIndex = -1;
            for(NSInteger j = self.delayItems-1; j >= 0; j--){
                NSInteger revIdx1 = [self.stampData count]-j-1;
                NSInteger revIdx2 = [self.stampData count]-j-2;
                if(revIdx1 >= 0 && revIdx2 >= 0){
                    double dtmp1 = [self.stampData[revIdx2] doubleValue];
                    double dtmp2 = [self.stampData[revIdx1] doubleValue];
                    if(datapointStmp >= dtmp1 && datapointStmp < dtmp2){
                        chartIndex = (double)j-(datapointStmp-dtmp1)/(dtmp2-dtmp1);
                        break;
                    }
                }
            }
            if(chartIndex > maxItems){
                break;
            }
            if(chartIndex < 0){
                continue;
            }
            [delayChart addChartPointFracX:1.0-chartIndex/maxItems fracY:-0.1
                                    radius:MAX(0.3, sqrt(datapointSz/1000.0)) color:dpColors[datapointId%dpColors.count]];
        }

        // cleanup
        while([self.stampData count]> self.delayItems){
            [self.stampData removeObjectAtIndex:0];
            [self.delayData removeObjectAtIndex:0];
            [self.onbufDataV removeObjectAtIndex:0];
            [self.onbufDataA removeObjectAtIndex:0];
            [self.strmdData removeObjectAtIndex:0];
            //[self.bytesData removeObjectAtIndex:0];
        }
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
