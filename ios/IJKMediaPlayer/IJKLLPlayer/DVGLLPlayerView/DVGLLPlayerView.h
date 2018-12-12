/*
 * Copyright (C) 2013-2015 Bilibili
 * Copyright (C) 2013-2015 Zhang Rui <bbcallen@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <UIKit/UIKit.h>
#import <DVGLLPlayerFramework/IJKMediaFrameworkWithSSL.h>

#define DVGLLPlayerFramework_VERSION @"1.0.32"

@class IJKMediaControl;

// URL to retrieve stream information from LowLat server. Not real playlist, but special information from streamer
static NSString* _Nonnull const kVideoStreamLowLatMetaURLBase =
    @"http://18.213.85.167:3000/";
static NSString* _Nonnull const kVideoStreamLowLatMetaTempl =
    @"{base_url}getMeta?playlist={name}";

// URL to get chunks data (ts files)
static NSString* _Nonnull const kVideoStreamLowLatChunkURLBase =
    @"http://18.213.85.167:3000/";
    //@"http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/";
    //@"http://d1d7bq76ey2psd.cloudfront.net/";
static NSString* _Nonnull const kVideoStreamLowLatChunkTempl =
    @"{base_url}getChunk?playlist={name}&chunk={chunk}";

// URL for uploading logs
static NSString* _Nonnull const kVideoStreamLogsUplURLBase =
    @"http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/";
    //@"http://LHLS-LB-469453332.us-east-1.elb.amazonaws.com/";
static NSString* _Nonnull const kVideoStreamLogsUplFileTempl = @"{url_base}uploadMedia?playlist={name}&chunk={chunk}&frame={frame}&meta={meta}&tm={stamp}";
// http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/getPlaylist?playlist=logs:player:test7289

// Time difference between frames, shown in player and frames, downloaded from server.
static NSString* _Nonnull const kDVGPlayerStatsRtLate = @"kDVGPlayerStatsRtLate";
// Server timestamp of matched frames. Used for kDVGPlayerStatsRtLate calculations
//static NSString* _Nonnull const kDVGPlayerStatsRtLateServerTs = @"kDVGPlayerStatsRtLateServerTs";
// Local timestamp of matched frames. Used for kDVGPlayerStatsRtLate calculations
static NSString* _Nonnull const kDVGPlayerStatsRtLateLocalTs = @"kDVGPlayerStatsRtLateLocalTs";
// Local pts of matched frames. Used for kDVGPlayerStatsRtLate calculations
static NSString* _Nonnull const kDVGPlayerStatsRtLateLocalPts = @"kDVGPlayerStatsRtLateLocalPts";
// Local timestamp of most recently showns frames. Used for kDVGPlayerStatsRtLate calculations
static NSString* _Nonnull const kDVGPlayerStatsRtLateLocalTsLast = @"kDVGPlayerStatsRtLateLocalTsLast";
// Local pts of most recently showns frames. Used for kDVGPlayerStatsRtLate calculations
static NSString* _Nonnull const kDVGPlayerStatsRtLateLocalPtsLast = @"kDVGPlayerStatsRtLateLocalPtsLast";
// Seconds in wait for data. If player waits for data - this value will increase.
// Value will be 0 if player normally plays video (no stalls)
static NSString* _Nonnull const kDVGPlayerStatsStalltime = @"kDVGPlayerStatsStalltime";
// Known streamer (uploader) delay
static NSString* _Nonnull const kDVGPlayerStatsUploaderDelay = @"kDVGPlayerStatsUploaderDelay";
// kDVGPlayerStatsIsRealtime = NO, if player plays finished playlist (not realtime, stream ended some time ago). Player will no try any seeks
// kDVGPlayerStatsIsRealtime = YES, if player play active stream. In this case player will try to seek to real time inside stream.
static NSString* _Nonnull const kDVGPlayerStatsIsRealtime = @"kDVGPlayerStatsIsRealtime";
// Delay between parsing frames and show them on screen (player buffering)
static NSString* _Nonnull const kDVGPlayerStatsBuffDelay = @"kDVGPlayerStatsBuffDelay";

// Seconds between requesting fresh stream metadata from server
static double const kPlayerCheckStreamMetadataSec = 3;
static double const kPlayerCheckStreamMetadataTimeoutSec = 3;

// Number of chunks to actively prefetch
static double const kPlayerStreamChunksPrefetchLimit = 3;
// Time to keep prefetched chunks in memory
static double const kPlayerStreamChunksPrefetchTtlSec = 30;

// Fraction of chunk duration. Time threshold for "jumping" into playlist end after series of stalls
static double const kPlayerReseekOnPtsLateChunkFrac = 1.4;
static double const kPlayerRestartOnPtsLateChunkSec = 10.0;
static double const kPlayerRestartOnStallingSec = 10.0;

// seconds. If uploader delay is bigger than this threashold - player will not try reseeks since there is no point in catchin up
static double const kPlayerNoSkipOnBadUploaderSec = 2.0;

// seconds. Used to calculate stream finish with sure
static double const kPlayerAvgInBufftime = 0.5;

//static NSURLSessionMultipathServiceType kDVGPlayerMultipathServiceType = NSURLSessionMultipathServiceTypeNone;
static NSURLSessionMultipathServiceType kDVGPlayerMultipathServiceType = NSURLSessionMultipathServiceTypeHandover;

@protocol DVGLLPlayerViewDelegate <NSObject>

// Called when wrapper swap IJK player for another instance. Can be used to get additional info from ffplay
- (void)onDVGLLPlayerUpdate:(id<IJKMediaPlayback> _Nullable)player;

// Called when there is an error asking server for metadata info
- (void)onDVGLLPlaylistError:(NSError* _Nullable)error;

// Called when stream is started to play
- (void)onDVGLLPlaylistStarted;

// Called when stream is finished on streamer side and player played all the video of the stream
- (void)onDVGLLPlaylistFinished;

// Called periodically with averages for video lag and various delays
- (void)onDVGLLPlayerStatsUpdated:(NSDictionary* _Nullable)stats;

@end


@interface DVGLLPlayerView : UIView
@property (weak, atomic) id<DVGLLPlayerViewDelegate> _Nullable delegate;


- (void)setPlayerForLowLatPlaylist:(NSString* _Nullable)ll_playlist;
- (void)setPlayerForURL:(NSURL* _Nullable)playurl;
- (void)videoScalingMode:(IJKMPMovieScalingMode)mode;

- (BOOL)playerShowHUD;
- (void)playerPlay;
- (void)playerPause;

+ (void)ffmpegPreheating;
- (void)statsFillHotData:(NSMutableDictionary* _Nonnull)stats;

+ (void)uploadLogsForStream:(NSString*_Nullable)streamName;
+ (void)performSpeedTestForStream:(NSString*_Nullable)streamName;
@end


