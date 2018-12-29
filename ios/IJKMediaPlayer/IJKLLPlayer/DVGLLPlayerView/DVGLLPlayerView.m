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
#import <Foundation/Foundation.h>
#import "DVGLLPlayerView.h"
//#import "AFxNetworking.h"
#import "DVGPlayerServerChecker.h"
#import "DVGPlayerChunkLoader.h"
#import "DVGPlayerFileUtils.h"
#import "DVGLLPlayerStatChart.h"


typedef void (^afnCallback)(NSURLResponse *response, id responseObject, NSError *error);
#define EXPECTED_IJKPLAYER_VERSION (1 << 16) & 0xFF) |

#define PLSTATE_NEEDINTIALIZATION 2
#define PLSTATE_NEEDREGENERATION 1
#define PLSTATE_PLAYING 0
#define PLSTATE_FINISHED -1

@interface DVGLLPlayerView()
@property (assign, atomic) BOOL isInitialized;

// ijk/ffplay player
@property (atomic, retain) id<IJKMediaPlayback> player;
@property (assign, atomic) IJKMPMovieScalingMode scalingMode;

// active playlist
@property (atomic,strong) NSString* active_lowlat_playlist;

@property (atomic,assign) int playlist_state;
@property (atomic,assign) double secondsInStall;
@property (atomic,assign) double tsStalledStart;
@property (atomic,assign) int playlist_stallrestarts;
@property (atomic,assign) int playlist_reseekstate;

@property (atomic,assign) double hlsChunkDuration;
@property (atomic,assign) double hlsStreamFps;
@property (atomic,assign) double hlsRTStreamStartupInitsNeeded;
@property (atomic,assign) double hlsRTStreamTipUplDelay;
@property (atomic,assign) double hlsRTStreamTipPtsStamp;
@property (atomic,assign) double hlsRTStreamTipPtsStampS;
@property (atomic,assign) double hlsRTStreamTipPts;
@property (atomic,assign) double hlsRTStreamIngoreReseekTillPts;
@property (atomic,assign) NSInteger hlsIsClosed;
@property (atomic,assign) NSInteger hlsRTChunk;

@property (atomic,assign) NSInteger regenPlaylistCnt;
@property (atomic,assign) double regenPlaylistEndIsNear;
@property (atomic,strong) NSTimer *playerTrackTimer;

@property (atomic,assign) double statLastRtDelayCheck;
@property (atomic,strong) NSMutableArray* statChunkPts;

//@property (strong,atomic) AFxJSONResponseSerializer* httpManagerSerializer;
//@property (strong,atomic) AFxHTTPSessionManager* httpManager;
@property (strong,atomic) DVGPlayerChunkLoader* httpChunkLoader;

@property (atomic,strong) NSTimer *statsTrackTimer;
@end

@implementation DVGLLPlayerView

// Makes empty requests to meta/chunk server to prepare ffmpeg dns caches (can save a time for realtime calls)
+ (void)ffmpegPreheating {
    static BOOL isPreheated = NO;
    if(isPreheated == NO){
        isPreheated = YES;
        
        [IJKFFMoviePlayerController setLogReport:YES];
        [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_DEFAULT];

//#ifdef DEBUG
//        [IJKFFMoviePlayerController setLogReport:YES];
//        [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_DEFAULT];//k_IJK_LOG_DEBUG
//#else
//        [IJKFFMoviePlayerController setLogReport:NO];
//        [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_INFO];
//#endif
        // Preheating DNS caches - not needed
        //[IJKFFMoviePlayerController preheatURL:[DVGLLPlayerView configurationValueForKey:@"kVideoStreamLowLatMetaURLBase"]];
        //[IJKFFMoviePlayerController preheatURL:[DVGLLPlayerView configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"]];
    }
}

+ (void)switchToOptimalServer
{
    // http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/getPlaylist?playlist=027C7792-EFF9-4394-A65D-014012B1C4F2
    // http://d1d7bq76ey2psd.cloudfront.net/getPlaylist?playlist=qq153
    // curl "http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/getChunk?playlist=027C7792-EFF9-4394-A65D-014012B1C4F2&chunk=5" -o ts5.ts
    // ffprobe -show_frames -print_format compact -i ts5.ts
    if([DVGPlayerFileUtils configurationValueForKey:@"DVGServerCheckerUsed"] == nil){
        [DVGPlayerFileUtils overloadConfigurationKey:@"DVGServerCheckerUsed" value:@(1)];
        NSString* topserver = [[DVGPlayerServerChecker getActiveCheckerForURL:nil] getOptimalServer];
        if(topserver != nil){
            [DVGPlayerFileUtils overloadConfigurationKey:@"kVideoStreamLowLatChunkURLBase" value:topserver];
            if(![topserver containsString:@"cloudfront"]){
                [DVGPlayerFileUtils overloadConfigurationKey:@"kVideoStreamLowLatMetaURLBase" value:topserver];
            }
        }
    }
}

- (void)preparePlayer {
    if(self.httpChunkLoader == nil){
        self.httpChunkLoader = [[DVGPlayerChunkLoader alloc] init];
        self.httpChunkLoader.autoCancelOutdatedChunks = YES;
    }
    if(self.isInitialized){
        return;
    }
    self.isInitialized = YES;
    [DVGLLPlayerView ffmpegPreheating];
    self.scalingMode = IJKMPMovieScalingModeAspectFill;// IJKMPMovieScalingModeAspectFit
    [DVGLLPlayerView switchToOptimalServer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillEnterActive)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
}

// initializes view with lowlat playlist
- (void)setPlayerForLowLatPlaylist:(NSString*)ll_playlist {
    [self preparePlayer];
    if([ll_playlist characterAtIndex:ll_playlist.length-1] == '?'){
        ll_playlist = [ll_playlist stringByReplacingOccurrencesOfString:@"?" withString:@""];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DVGLLPlayerStatLogs* logsView = [[DVGLLPlayerStatLogs alloc] init];
            logsView.frame = CGRectInset(self.frame,20,20);
            logsView.font = [UIFont systemFontOfSize:10];
            [self addSubview:logsView];
            [DVGLLPlayerView performSpeedTestForStream:ll_playlist logView:logsView];
        });
        return;
    }
    lastActiveStreamName = [ll_playlist copy];
    self.active_lowlat_playlist = ll_playlist;
    self.playlist_state = PLSTATE_NEEDINTIALIZATION;
    self.hlsIsClosed = 0;
    self.playlist_stallrestarts = 0;
    [self syncToLowLatPlaylist];
}

// Cleans ijk player
- (void)shutdownPlayer:(BOOL)hardShutdown
{
    [self.httpChunkLoader finalizeThis];
    self.httpChunkLoader = nil;
    self.secondsInStall = 0;
    self.playlist_state = PLSTATE_FINISHED;
    [self.player forceStopLoadingSource];
    if(hardShutdown){
        [self setPlayerForURL:nil];
    }else{
        [self.playerTrackTimer invalidate];
        [self.statsTrackTimer invalidate];
        self.playerTrackTimer = nil;
        self.statsTrackTimer = nil;
        [self.player stop];
    }
}

- (void)appWillResignActive
{
    [self shutdownPlayer:YES];
}

- (void)appWillEnterActive
{
    if(self.active_lowlat_playlist != nil){
        [self setPlayerForLowLatPlaylist:self.active_lowlat_playlist];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self shutdownPlayer:YES];
}

//- (void)viewDidDisappear:(BOOL)animated {
//    [super viewDidDisappear:animated];
//    [self setPlayerForURL:nil];
//}
-(void)willMoveToSuperview:(UIView *)newSuperview {
    if (newSuperview == nil) {
        [self shutdownPlayer:YES];
    }
}
-(void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window == nil) {
        [self shutdownPlayer:YES];
    }
}

 -(void)updatePlayerInplaceForSameURL {
     self.tsStalledStart = -1;
     self.secondsInStall = 0;
     self.hlsRTStreamTipPts = 0;
     self.hlsRTStreamTipUplDelay = 0;
     self.hlsRTStreamTipPtsStamp = 0;
     self.hlsRTStreamTipPtsStampS = 0;
     [self.player forceReloadSource];
 }

// Replaces ijk player source URL
// Normally ijk player should be recreated, but for lowlat functionality source replacement is much faster
//- (void)updatePlayerForURLInplace:(NSURL*)playurl {
//    VLLog(@"updatePlayerForURLInplace: %@",playurl);
//    if(self.player == nil){
//        return;
//    }
//    [self removeMovieNotificationObservers];
//    [self.player stop];
//    //[self.player shutdown];
//    [self.player updateURL:playurl];
//    self.tsStalledStart = -1;
//    self.secondsInStall = 0;
//    self.hlsRTStreamTipPts = 0;
//    self.hlsRTStreamTipUplDelay = 0;
//    self.hlsRTStreamTipPtsStamp = 0;
//    [self installMovieNotificationObservers];
//    [self.player prepareToPlay];
//}

// Swaps ijk player for new one and point ijk player to new source url
- (void)setPlayerForURL:(NSURL*)playurl {
    VLLog(@"setPlayerForURL: %@",playurl);
    [self preparePlayer];
    if(self.player != nil){
        [self.playerTrackTimer invalidate];
        [self.statsTrackTimer invalidate];
        self.playerTrackTimer = nil;
        self.statsTrackTimer = nil;
        [self.player.view removeFromSuperview];
        [self.player shutdown];
        [self removeMovieNotificationObservers];
        if ([self.delegate respondsToSelector:@selector(onDVGLLPlayerUpdate:)]) {
            [self.delegate onDVGLLPlayerUpdate:nil];
        }
        self.player = nil;
    }
    if(playurl != nil){
        IJKFFOptions *options = [IJKFFOptions optionsByDefault];
        self.player = [[IJKFFMoviePlayerController alloc] initWithContentURL:playurl withOptions:options];
        self.player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.player.view.frame = self.bounds;
        self.player.scalingMode = self.scalingMode;
        self.player.shouldAutoplay = YES;
        [self addSubview:self.player.view];
        if ([self.delegate respondsToSelector:@selector(onDVGLLPlayerUpdate:)]) {
            [self.delegate onDVGLLPlayerUpdate:self.player];
        }
        self.tsStalledStart = -1;
        self.secondsInStall = 0;
        [self installMovieNotificationObservers];
        [self.player prepareToPlay];
        [self setNeedsLayout];
        [self layoutIfNeeded];
        self.playerTrackTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                 target:self
                                                               selector:@selector(checkPlayerStalled)
                                                               userInfo:nil
                                                                repeats:YES];
        self.statsTrackTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                                 target:self
                                                               selector:@selector(checkStats)
                                                               userInfo:nil
                                                                repeats:YES];
    }
}

- (void)videoScalingMode:(IJKMPMovieScalingMode)mode {
    self.scalingMode = mode;
    if(self.player){
        self.player.scalingMode = self.scalingMode;
    }
}

- (void)layoutSubviews
{
    self.player.view.frame = self.bounds;
}

// Build-in HUD with debug info (handled by ijk player)
- (BOOL)playerShowHUD
{
    if(self.player != nil){
        if ([self.player isKindOfClass:[IJKFFMoviePlayerController class]]) {
            IJKFFMoviePlayerController *player = self.player;
            player.shouldShowHudView = !player.shouldShowHudView;
            return player.shouldShowHudView;
        }
    }
    return NO;
}

// Main operation to start playback
- (void)playerPlay
{
    if(self.player != nil){
        [self.player play];
    }
}

// Main operation to pause playback
- (void)playerPause
{
    if(self.player != nil){
        [self.player pause];
    }
}

- (void)loadStateDidChange:(NSNotification*)notification
{
    //    MPMovieLoadStateUnknown        = 0,
    //    MPMovieLoadStatePlayable       = 1 << 0,
    //    MPMovieLoadStatePlaythroughOK  = 1 << 1, // Playback will be automatically started in this state when shouldAutoplay is YES
    //    MPMovieLoadStateStalled        = 1 << 2, // Playback will be automatically paused in this state, if started
    IJKMPMovieLoadState loadState = _player.loadState;
    if ((loadState & IJKMPMovieLoadStatePlaythroughOK) != 0) {
        VLLog(@"loadStateDidChange: IJKMPMovieLoadStatePlaythroughOK: %d\n", (int)loadState);
    }
    if ((loadState & IJKMPMovieLoadStateStalled) != 0) {
        self.tsStalledStart = CACurrentMediaTime();
        VLLog(@"loadStateDidChange: IJKMPMovieLoadStateStalled: %d\n", (int)loadState);
    }else{
        [self checkPlayerStalled];
        self.tsStalledStart = -1;
    }
    [self checkPlayerStalled];
}

- (void)moviePlayBackDidFinish:(NSNotification*)notification
{
    //    MPMovieFinishReasonPlaybackEnded,
    //    MPMovieFinishReasonPlaybackError,
    //    MPMovieFinishReasonUserExited
    int reason = [[[notification userInfo] valueForKey:IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey] intValue];
    switch (reason)
    {
        case IJKMPMovieFinishReasonPlaybackEnded:
            VLLog(@"playbackStateDidChange: IJKMPMovieFinishReasonPlaybackEnded: %d\n", reason);
            break;

        case IJKMPMovieFinishReasonUserExited:
            VLLog(@"playbackStateDidChange: IJKMPMovieFinishReasonUserExited: %d\n", reason);
            break;

        case IJKMPMovieFinishReasonPlaybackError:
            VLLog(@"playbackStateDidChange: IJKMPMovieFinishReasonPlaybackError: %d\n", reason);
            break;

        default:
            VLLog(@"playbackPlayBackDidFinish: ???: %d\n", reason);
            break;
    }
    [self checkPlayerStalled];
}

- (void)moviePlayBackStateDidChange:(NSNotification*)notification
{
    //    MPMoviePlaybackStateStopped,
    //    MPMoviePlaybackStatePlaying,
    //    MPMoviePlaybackStatePaused,
    //    MPMoviePlaybackStateInterrupted,
    //    MPMoviePlaybackStateSeekingForward,
    //    MPMoviePlaybackStateSeekingBackward
    switch (_player.playbackState)
    {
        case IJKMPMoviePlaybackStateStopped: {
            VLLog(@"IJKMPMoviePlayBackStateDidChange %d: stoped", (int)_player.playbackState);
            break;
        }
        case IJKMPMoviePlaybackStatePlaying: {
            VLLog(@"IJKMPMoviePlayBackStateDidChange %d: playing", (int)_player.playbackState);
            break;
        }
        case IJKMPMoviePlaybackStatePaused: {
            VLLog(@"IJKMPMoviePlayBackStateDidChange %d: paused", (int)_player.playbackState);
            break;
        }
        case IJKMPMoviePlaybackStateInterrupted: {
            VLLog(@"IJKMPMoviePlayBackStateDidChange %d: interrupted", (int)_player.playbackState);
            break;
        }
        case IJKMPMoviePlaybackStateSeekingForward:
        case IJKMPMoviePlaybackStateSeekingBackward: {
            VLLog(@"IJKMPMoviePlayBackStateDidChange %d: seeking", (int)_player.playbackState);
            break;
        }
        default: {
            VLLog(@"IJKMPMoviePlayBackStateDidChange %d: unknown", (int)_player.playbackState);
            break;
        }
    }
    [self checkPlayerStalled];
}

-(void)installMovieNotificationObservers
{
    [self.player setAccurateBufferingSec:kPlayerAvgInBufftime fps:self.hlsStreamFps];
    IJKFFMonitor* mon = [self.player getJkMonitor];
    mon.rtDelayOnscreen = 0;
    mon.rtDelayOnbuffV = 0;
	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(loadStateDidChange:)
                                                 name:IJKMPMoviePlayerLoadStateDidChangeNotification
                                               object:_player];

	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayBackDidFinish:)
                                                 name:IJKMPMoviePlayerPlaybackDidFinishNotification
                                               object:_player];

	//[[NSNotificationCenter defaultCenter] addObserver:self
    //                                         selector:@selector(mediaIsPreparedToPlayDidChange:)
    //                                             name:IJKMPMediaPlaybackIsPreparedToPlayDidChangeNotification
    //                                           object:_player];

	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayBackStateDidChange:)
                                                 name:IJKMPMoviePlayerPlaybackStateDidChangeNotification
                                               object:_player];
}

-(void)removeMovieNotificationObservers
{
    [[NSNotificationCenter defaultCenter]removeObserver:self name:IJKMPMoviePlayerLoadStateDidChangeNotification object:_player];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:IJKMPMoviePlayerPlaybackDidFinishNotification object:_player];
    //[[NSNotificationCenter defaultCenter]removeObserver:self name:IJKMPMediaPlaybackIsPreparedToPlayDidChangeNotification object:_player];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:IJKMPMoviePlayerPlaybackStateDidChangeNotification object:_player];
}

// Since ijk player initialization and video preparation is asynchronous process (and there is no single point for injecting seekskip when player not ready) - we waiting for it to be ready to play and seekskip stream
- (void)waitForChance2SeekSkip:(int)maxtries targetPts:(double)targetPts {
    long res = [self.player doAccurateSeekSkip:targetPts];
    if(res < 0 && maxtries > 0){
        VLLog(@"HLSLOWLAT: buffering to catchup with realtime (reseek), next attempt, %li, %li",res,maxtries);
        double waitForReadyDelay = 0.3;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(waitForReadyDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self waitForChance2SeekSkip:maxtries-1 targetPts:targetPts];
        });
    }
}

// Main method to perform various actions when player is stalled
- (void)checkPlayerStalled {
    if(self.player == nil || self.playlist_state <= PLSTATE_FINISHED){
        // No player or stream finished - nothing to check
        return;
    }
    double ontippts = 0.0;
    double onDecoPtsV = [self.player getOnDecoPtsV];
    double onPaktPtsV = [self.player getOnPaktPtsV];
    //double ondecoptsA = [self.player getOnDecoPtsA];
    //double onscrpts = [self.player getOnScreenPts];//  HEVC play trick on this... not sustainable
    double rtDelay = 0;
    if(self.hlsRTStreamTipPts > 0){
        ontippts = self.hlsRTStreamTipPts + ([DVGPlayerServerChecker unixStamp]-self.hlsRTStreamTipPtsStamp);
    }
    if(onPaktPtsV > 0 && onDecoPtsV > 0 && ontippts > 0){
        rtDelay = ontippts - onDecoPtsV;
    }
    
    BOOL tryReseek = NO;
    if(self.hlsRTStreamStartupInitsNeeded > 0 && onDecoPtsV > 0.001 && ontippts > 0.001){
        // Checking initial delays and deciding on seeking to realtime tip of the stream
        self.secondsInStall = 0;
        self.hlsRTStreamStartupInitsNeeded = 0;
        self.statLastRtDelayCheck = CACurrentMediaTime();
        [self.player setAccurateBufferingSec:kPlayerAvgInBufftime fps:self.hlsStreamFps];
        VLLog(@"HLSLOWLAT: Player ready, chunkId=%lu fps=%.02f stt=%i upl_dl=%.02f",
              self.hlsRTChunk, self.hlsStreamFps, self.hlsIsClosed, self.hlsRTStreamTipUplDelay);
        if ([self.delegate respondsToSelector:@selector(onDVGLLPlaylistStarted)]) {
            [self.delegate onDVGLLPlaylistStarted];
        }
    }
    if(self.hlsChunkDuration > 0 && self.hlsRTStreamStartupInitsNeeded == 0){
        // Summarizing and checking stall periods if player waiting for data
        if(self.tsStalledStart > 0){
            IJKFFMonitor* mon = [self.player getJkMonitor];
            self.secondsInStall += CACurrentMediaTime()-self.tsStalledStart;
            self.tsStalledStart = CACurrentMediaTime();
            mon.stallMarker = self.secondsInStall;
            VLLog(@"HLSLOWLAT: secondsInStall=%.02f, pl=%i/%i/%i",self.secondsInStall, self.playlist_state, self.hlsIsClosed, self.playlist_stallrestarts);
        }
        // We have to regenerate playlist if player not active for chunk-duration seconds
        if(self.hlsIsClosed == 0 && self.playlist_state == PLSTATE_PLAYING){
            double maxPtsLate4Restart = self.hlsChunkDuration*kPlayerRestartOnPtsLateChunkFrac;
            if(self.secondsInStall > kPlayerRestartOnStallingSec || rtDelay > maxPtsLate4Restart){
                VLLog(@"HLSLOWLAT: Stalling for too long, requesting restart (%.02f > %.02f || ptslate%.02f > %.02f)", self.secondsInStall, kPlayerRestartOnStallingSec, rtDelay, maxPtsLate4Restart);
                self.playlist_reseekstate = 1;
                self.playlist_state = PLSTATE_NEEDREGENERATION;
                self.playlist_stallrestarts++;
            }else
            {
                double maxPtsLate = MAX(kPlayerAvgInBufftime, self.hlsChunkDuration*kPlayerReseekOnPtsLateChunkFrac);
                if(rtDelay > maxPtsLate){
                    if(onDecoPtsV > self.hlsRTStreamIngoreReseekTillPts){
                        VLLog(@"HLSLOWLAT: Last shown frame too late for stream, trying to reseek (tip%.02f > dec%.02f, rtd%.02f)",
                              ontippts, onDecoPtsV, rtDelay);
                        tryReseek = YES;
                    }else{
                        VLLog(@"HLSLOWLAT: Last shown frame too late for stream, but reseek is pending (exp%.02f, tip%.02f > dec%.02f, rtd%.02f)",
                              self.hlsRTStreamIngoreReseekTillPts, ontippts, onDecoPtsV, rtDelay);
                    }
                }
            }
        }
    }
    if(self.hlsIsClosed == 0 && CACurrentMediaTime() > self.regenPlaylistEndIsNear){
        // We have to regenerate out handmade playlist if we are almost at the end
        VLLog(@"HLSLOWLAT: Playlist almost over, requesting restart");
        self.playlist_state = PLSTATE_NEEDREGENERATION;
    }
    self.playlist_reseekstate = 0;
    if(self.playlist_state >= PLSTATE_NEEDREGENERATION){
        self.playlist_reseekstate = 1;
        self.tsStalledStart = -1;
        self.secondsInStall = 0;
        [self syncToLowLatPlaylist];
    }else{
        if(!tryReseek && onDecoPtsV < self.hlsRTStreamIngoreReseekTillPts){
            self.playlist_reseekstate = -1;
        }
        if(tryReseek){
            if(self.hlsIsClosed == 0){
                self.playlist_reseekstate = -1;
                if(onPaktPtsV > ontippts - kPlayerAvgInBufftime){
                    VLLog(@"HLSLOWLAT: reseek to catchup with realtime %f, bufferReady=%.02f", rtDelay, onPaktPtsV-onDecoPtsV);
                    self.hlsRTStreamIngoreReseekTillPts = ontippts;
                    dispatch_async( dispatch_get_main_queue(), ^{
                        [self waitForChance2SeekSkip:0 targetPts: ontippts - kPlayerAvgInBufftime];
                    });
                }else{
                    VLLog(@"HLSLOWLAT: reseek skipped, not enough data, rtd%.02f, bufferReady=%.02f, tip%.02f, pak%.02f", rtDelay, onPaktPtsV-onDecoPtsV, ontippts, onPaktPtsV);
                }
            }else{
                VLLog(@"HLSLOWLAT: reseek skipped %i, playlist closed already: %i", self.hlsIsClosed);
            }
        }
        // We have to ask server for fresh metadata from time to time
        // checking if we need to ask again
        if(self.statLastRtDelayCheck > 0){
            if(CACurrentMediaTime() - self.statLastRtDelayCheck > kPlayerCheckStreamMetadataSec){
                self.statLastRtDelayCheck = CACurrentMediaTime();
                [self syncToLowLatPlaylist];
            }
        }
    }
}

+ (NSDictionary*)serverPListToDictionary:(NSString*)params {
    NSMutableDictionary* res = @{}.mutableCopy;
    if(params == (id)[NSNull null]){
        return res;
    }
    NSArray* metapairs = [params componentsSeparatedByString:@","];
    if([metapairs count] == 0 || ([metapairs count]%2) != 0){
        // Wrong plist/no data
        return nil;
    }
    for(int i = 0; i<[metapairs count]; i = i+2){
        NSString* key = metapairs[i+0];
        NSString* val = metapairs[i+1];
        res[key] = val;
    }
    return res;
}

// Asking server for metadata and analizing answer
- (void)syncToLowLatPlaylist {
    static int isSyncToLowLatPlaylistActive = 0;
    if(isSyncToLowLatPlaylistActive > 0){
        return;
    }
    NSString* getMetaHlsUrl = kVideoStreamLowLatMetaTempl;
    getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{base_url}"
                                                             withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatMetaURLBase"]];
    getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{name}" withString:self.active_lowlat_playlist];
    //getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{cachepnc}" withString:[NSString stringWithFormat:@"%f",[DVGPlayerServerChecker unixStamp]]];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.allowsCellularAccess = YES;
    configuration.multipathServiceType = kDVGPlayerMultipathServiceType;
    double tsLocalBefore = [DVGPlayerServerChecker unixStamp];
    isSyncToLowLatPlaylistActive++;
    //getMetaHlsUrl = [getMetaHlsUrl stringByAddingPercentEncodingWithAllowedCharacters:[[NSCharacterSet characterSetWithCharactersInString:@"&"] invertedSet]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:getMetaHlsUrl] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kPlayerCheckStreamMetadataTimeoutSec];
    [request setHTTPMethod:@"POST"];
    NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if(error != nil || [data length] == 0){
            VLLog(@"HLSLOWLAT: syncToLowLatPlaylist failed with error: %@", error);
            isSyncToLowLatPlaylistActive--;
            if(self.playlist_state >= PLSTATE_NEEDREGENERATION){
                if ([self.delegate respondsToSelector:@selector(onDVGLLPlaylistError:)]) {
                    [self.delegate onDVGLLPlaylistError:error];
                };
            }
            return;
        }
        NSError *JSONError = nil;
        NSDictionary* responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
        double tsLocalAfter = [DVGPlayerServerChecker unixStamp];
        //VLLog(@"Requested stream metadata: syncToLowLatPlaylist for %@, diff = %.02f",self.active_lowlat_playlist,tsLocalAfter-tsLocalBefore);
        //VLLog(@"JSON: %@", responseObject);
        isSyncToLowLatPlaylistActive--;
        if(responseObject[@"chunk"] == nil || responseObject[@"chunk"] == [NSNull null]){
            VLLog(@"HLSLOWLAT: syncToLowLatPlaylist: [%@] failed with error: %@", self.active_lowlat_playlist, responseObject);
            if ([self.delegate respondsToSelector:@selector(onDVGLLPlaylistError:)]) {
                 [self.delegate onDVGLLPlaylistError:nil];
            }
            return;
        }
        //double playerStamp = [self.player getTimestamp];
        double tsLocal = (tsLocalBefore+(tsLocalAfter-tsLocalBefore)*0.5);
        double tsServer = ((double)[responseObject[@"serverts"] longLongValue])/1000.0f;
        double tsServerChunkLastWrite = ((double)[responseObject[@"lastopts"] longLongValue])/1000.0f;
        double tsServerChunkFirstWrite = ((double)[responseObject[@"chunkts"] longLongValue])/1000.0f;
        double tsServerChunkLastWriteLocal = tsServerChunkLastWrite+tsLocal-tsServer;
        //double tsLocalserverTimeError = tsLocal - tsServer;
        NSDictionary* meta = [DVGLLPlayerView serverPListToDictionary:responseObject[@"meta"]];
        self.hlsChunkDuration = 1.0;
        NSInteger finStreamId = 0;
        double finStreamPts = 0.0;
        if(meta != nil){
            self.hlsChunkDuration = [meta[@"dur"] integerValue];
            self.hlsStreamFps = [meta[@"fps"] integerValue];
            finStreamId = [meta[@"fin"] integerValue];
            finStreamPts = [meta[@"pts"] doubleValue];
        }
        double chunkStartPts = 0;
        double chunkStartPtsTs = 0;
        double chunkStrUdlSec = 0;
        NSInteger chunkMetaId = 0;//[responseObject[@"chunk"] integerValue];
        NSDictionary* chunkmeta = meta;//[DVGLLPlayerView serverPListToDictionary:responseObject[@"chunkmeta"]];
        if(chunkmeta != nil){
            chunkMetaId = [chunkmeta[@"ch_id"] integerValue];
            chunkStartPts = [chunkmeta[@"ch_pts"] doubleValue];
            chunkStartPtsTs = [chunkmeta[@"ch_ptsts"] doubleValue];
            chunkStrUdlSec = [chunkmeta[@"ch_udl"] doubleValue];
            self.hlsRTStreamTipUplDelay = chunkStrUdlSec;
            self.hlsRTStreamTipPtsStamp = tsLocal;
            self.hlsRTStreamTipPtsStampS = chunkStartPtsTs;
            self.hlsRTStreamTipPts = chunkStartPts + tsServer-tsServerChunkFirstWrite;
            //NSLog(@"self.hlsRTStreamTipPts %f %f %f %@", chunkStartPts, tsServerChunkLastWrite, tsServerChunkFirstWrite, responseObject);
        }
        self.hlsRTChunk = chunkMetaId;
        if(self.playlist_state == PLSTATE_NEEDINTIALIZATION){
            self.hlsRTStreamStartupInitsNeeded++;
            if(finStreamId == 0){
                // If request take more than chunk duration - we can adjust start chunk to catch missed time right away!
                int adjustedChunks = 0;
                float reqdiff = tsLocalAfter - tsLocalBefore;
                while(reqdiff >= self.hlsChunkDuration){
                    reqdiff = reqdiff-self.hlsChunkDuration;
                    self.hlsRTChunk = self.hlsRTChunk+1;
                    adjustedChunks++;
                }
                if(adjustedChunks > 0){
                    VLLog(@"syncToLowLatPlaylist: preliminary playlist reseek: %i", adjustedChunks);
                }
            }
        }
        NSMutableDictionary* chunkdata = @{}.mutableCopy;
        chunkdata[@"url_template"] = kVideoStreamLowLatChunkTempl;
        chunkdata[@"playlist"] = self.active_lowlat_playlist;
        chunkdata[@"chunkId"] = @(self.hlsRTChunk);
        chunkdata[@"chunkDuration"] = @(self.hlsChunkDuration);
        chunkdata[@"chunkTs"] = @(chunkStartPtsTs);
        if(self.statChunkPts == nil){
            self.statChunkPts = @[].mutableCopy;
        }
        [self.statChunkPts addObject:@[@(tsServerChunkFirstWrite), @(chunkStartPts), @(chunkMetaId), @(chunkStartPtsTs)]];
        while([self.statChunkPts count]>10){
            [self.statChunkPts removeObjectAtIndex:0];
        }
        // stats
        NSMutableDictionary* stats = @{}.mutableCopy;
        IJKFFMonitor* mon = [self.player getJkMonitor];
        [self statsFillHotData:stats];
        double ondecoptsV = [self.player getOnDecoPtsV];
        double onpaktptsA = [self.player getOnPaktPtsV];
        double onscrnptsV = [self.player getOnScreenPts];
        double rtLate = 0;
        if(ondecoptsV > 0 && self.hlsRTStreamTipPts > 0){
            double ontippts = self.hlsRTStreamTipPts + ([DVGPlayerServerChecker unixStamp]-self.hlsRTStreamTipPtsStamp);
            rtLate = MAX(0, ontippts-ondecoptsV);
        }
        mon.stallMarker = self.secondsInStall;
        stats[kDVGPlayerStatsStalltime] = @(mon.stallMarker);
        stats[kDVGPlayerStatsUploaderDelay] = @(chunkStrUdlSec);
        VLLog(@"PLAY STATS: chk = %i (%.02f), rt-late = %.02fsec, known streamer delay = %.02f. ontip_pts=%.02f buf/dec/scr=%.02f/%.02f/%.02f, net-dl: %.02f",
              chunkMetaId, chunkStartPts, rtLate, chunkStrUdlSec, self.hlsRTStreamTipPts,
              onpaktptsA, ondecoptsV, onscrnptsV, tsLocalAfter-tsLocalBefore);
        // If this is old stream - starting from 1, no reseeks
        BOOL isStreamUpdatesAreOk = (tsLocal - tsServerChunkLastWriteLocal < self.hlsChunkDuration*5.0)?YES:NO;
        if(self.playlist_state == PLSTATE_NEEDINTIALIZATION && (finStreamId > 0 || !isStreamUpdatesAreOk)){
            VLLog(@"HLSLOWLAT: Non-RT playlist detected, stopping RT-logic %@ %@", chunkdata, stats);
            self.hlsIsClosed = -1;
            chunkdata[@"chunkId"] = @(1);
        }
        if(self.hlsIsClosed == 0 && finStreamId > 0){
            VLLog(@"HLSLOWLAT: Stream was closed, stopping RT-logic %@ %@", chunkdata, stats);
            // Normal stop - when all frames are played
            self.hlsIsClosed = 1;
        }
        if(self.hlsIsClosed >= 0 && !isStreamUpdatesAreOk){
            VLLog(@"HLSLOWLAT: Stream was not updated for too long, stopping RT-logic %@ %@", chunkdata, stats);
            // Abrupt stop - we don`t know when to stop in reality (last chunkId simply not relevant anymore)
            self.hlsIsClosed = 2;
        }
        //stats[kDVGPlayerStatsIsRealtime] = @(self.hlsIsClosed>0?NO:YES);
        
        BOOL needCheckStreamFinish = NO;
        if(self.playlist_state != PLSTATE_NEEDINTIALIZATION && self.playlist_state >= PLSTATE_PLAYING){
            needCheckStreamFinish = YES;
        }
        if(needCheckStreamFinish){
            BOOL isStreamEnd = NO;
            double onDecoPts = [self.player getOnDecoPtsV];
            if(finStreamId > 0 && onDecoPts >= finStreamPts - kPlayerAvgInBufftime){
                isStreamEnd = YES;
            }
            if(self.hlsIsClosed > 1){
                self.hlsIsClosed = 1;
                isStreamEnd = YES;
            }
            if(isStreamEnd){
                VLLog(@"syncToLowLatPlaylist: End of stream found");
                [self shutdownPlayer:NO];
                if ([self.delegate respondsToSelector:@selector(onDVGLLPlaylistFinished)]) {
                    [self.delegate onDVGLLPlaylistFinished];
                }
            }
        }
        [self playPlaylistWithMsg:chunkdata fakeChunkAdvance:300];
    }];
    [downloadTask resume];
}

// Generating handmade playlist for the stream. And pointing jk player on it
- (void)playPlaylistWithMsg:(NSDictionary*)chunkdata fakeChunkAdvance:(NSInteger)chunks {
    if(self.httpChunkLoader == nil){
        [self preparePlayer];
    }
    self.regenPlaylistCnt += 1;
    BOOL useLowlatDownloader = YES;
    NSString* playlistName = chunkdata[@"playlist"];
    double chunkDur = [chunkdata[@"chunkDuration"] doubleValue];
    NSInteger chunkId = [chunkdata[@"chunkId"] integerValue];
    double chunkTs = [chunkdata[@"chunkTs"] doubleValue];
    NSMutableArray* hlsContent = @[].mutableCopy;
    [hlsContent addObject:@"#EXTM3U"];
    [hlsContent addObject:[NSString stringWithFormat:@"## LLHLS-Reload:%li, chk:%lu", (long)self.regenPlaylistCnt, chunkId]];
    [hlsContent addObject:@"#EXT-X-VERSION:3"];
    [hlsContent addObject:[NSString stringWithFormat:@"#EXT-X-TARGETDURATION:%li", (long)chunkDur]];
    
    NSString* firstUrl = nil;
    NSMutableArray* chunksUrls4Pusher = @[].mutableCopy;
    NSMutableDictionary* chunksUrls4PusherStartTimes = @{}.mutableCopy;
    for (int i=0; i < chunks; i++) {
        NSInteger nextChunkId = chunkId+i;
        double thisChunkTs = chunkTs+chunkDur*i;
        [hlsContent addObject:@""];
        [hlsContent addObject:[NSString stringWithFormat:@"#EXTINF:%li,", (long)chunkDur]];
        
        NSString* chunkUrl = chunkdata[@"url_template"];
        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{base_url}"
                                                                 withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"]];
        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{name}" withString:playlistName];
        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{chunk}" withString:[NSString stringWithFormat:@"%lu", nextChunkId]];
        NSString* chunkUrlWeb = chunkUrl;
        if(useLowlatDownloader){
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"http://" withString:@""];
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"https://" withString:@""];
            NSArray* chunkPair = [self.httpChunkLoader getChunkUnixPairForUrl:chunkUrl];
            [hlsContent addObject:[NSString stringWithFormat:@"llhls://%@?%@", chunkPair[0], chunkPair[1]]];
            [chunksUrls4Pusher addObject:@[chunkUrlWeb, chunkPair[0], chunkPair[1]]];
            chunksUrls4PusherStartTimes[chunkUrlWeb] = @(thisChunkTs-chunkDur+chunkDur*kPlayerStreamChunksPrefetchFrac);
        }else{
            [hlsContent addObject:[NSString stringWithFormat:@"%@",chunkUrl]];
        }
        if(firstUrl == nil){
            firstUrl = chunkUrl;
        }
    }
    if(self.hlsIsClosed != 0){
        // Non-realtime logic for ffmpeg
        [hlsContent addObject:@""];
        [hlsContent addObject:@"#EXT-X-ENDLIST"];
    }
    if(self.playlist_state >= PLSTATE_NEEDREGENERATION){
        self.playlist_state = PLSTATE_PLAYING;
        self.secondsInStall = 0;
        self.regenPlaylistEndIsNear = CACurrentMediaTime()+self.hlsChunkDuration*MAX(3,chunks-3);
        NSString* joinedHlsContent = [hlsContent componentsJoinedByString:@"\n"];
        
        // Rewriting HLS files
        // Same file every time!
        NSString *tempPath = NSTemporaryDirectory();
        NSString* fileName = [NSString stringWithFormat:@"hls_%@.m3u8",playlistName];
        NSURL *directoryURL = [NSURL fileURLWithPath:tempPath isDirectory:YES];
        NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
        NSError* error = nil;
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:&error];
        error = nil;
        [joinedHlsContent writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if(error == nil){
            dispatch_block_t launchPlayer = ^{
                if(self.player != nil){
                    // Player already created, no need to recreate it - just replacing ijk player source URL with new one
                    // this is much faster than creating ijk player from scratch
                    //[self updatePlayerForURLInplace:fileURL];
                    [self updatePlayerInplaceForSameURL];
                }else{
                    // Initializing player with local playlist
                    [self setPlayerForURL:fileURL];
                }
            };
            if(useLowlatDownloader){
                [self.httpChunkLoader prepareForAvgChunkDuration:chunkDur prefetchCount:kPlayerStreamChunksPrefetchLimit];
                [self.httpChunkLoader prepareChunksTimingForList:chunksUrls4PusherStartTimes];
                [self.httpChunkLoader downloadChunksFromList:chunksUrls4Pusher andContinue:launchPlayer];
            }else{
                dispatch_async(dispatch_get_main_queue(), launchPlayer);
            }
        }
        VLLog(@"HLS: Regenerating playlist with chunk data %@", chunkdata);
    }else{
        if(useLowlatDownloader){
            // Updating start-timings per chunk
            [self.httpChunkLoader prepareChunksTimingForList:chunksUrls4PusherStartTimes];
        }
    }
}

- (void)checkStats {
    NSMutableDictionary* stats = @{}.mutableCopy;
    [self statsFillHotData:stats];
    IJKFFMonitor* mon = [self.player getJkMonitor];
    mon.stallMarker = self.secondsInStall;
    stats[kDVGPlayerStatsStalltime] = @(mon.stallMarker);
    stats[kDVGPlayerStatsUploaderDelay] = @(self.hlsRTStreamTipUplDelay);
    stats[kDVGPlayerStatsIsRealtime] = @(self.hlsIsClosed == 0?YES:NO);
    if ([self.delegate respondsToSelector:@selector(onDVGLLPlayerStatsUpdated:)]) {
        [self.delegate onDVGLLPlayerStatsUpdated:stats];
    }
}

- (void)statsFillHotData:(NSMutableDictionary*)stats {
    IJKFFMonitor* mon = [self.player getJkMonitor];
    double onDecoPtsV = [self.player getOnDecoPtsV];
    double onPaktPtsV = [self.player getOnPaktPtsV];
    double onDecoPtsA = [self.player getOnDecoPtsA];
    double onPaktPtsA = [self.player getOnPaktPtsA];
    //NSLog(@"statsFillHotData onDecoPtsV:%.02f-onPaktPtsV:%.02f=%.02f onDecoPtsA:%.02f-onPaktPtsA:%.02f=%.02f", onDecoPtsV, onPaktPtsV, onPaktPtsV-onDecoPtsV, onDecoPtsA, onPaktPtsA, onPaktPtsA-onDecoPtsA);
    mon.rtDelayOnbuffA = 0;
    if(onPaktPtsA > 0 && onDecoPtsA > 0){
        mon.rtDelayOnbuffA = onPaktPtsA-onDecoPtsA;
    }
    mon.rtDelayOnbuffV = 0;
    if(onPaktPtsV > 0 && onDecoPtsV > 0){
        mon.rtDelayOnbuffV = onPaktPtsV-onDecoPtsV;
    }
    if(self.hlsRTStreamTipPts > 0 && onDecoPtsV > 0){
        //double ontippts = self.hlsRTStreamTipPts + ([DVGPlayerServerChecker unixStamp]-self.hlsRTStreamTipPtsStamp);
        //mon.rtDelayOnscreen = MAX(0, ontippts - onScrnPts);
        double now_ts = [DVGPlayerServerChecker unixStamp];
        double localTimeOnStreamer = self.hlsRTStreamTipPtsStampS + onDecoPtsV - self.hlsRTStreamTipPts;
        mon.rtDelayOnscreen = MAX(0, now_ts - localTimeOnStreamer);
        //NSLog(@"rtDelayOnscreen rtl=%f now=%f lts=%f tipptss=%f decov=%f tippts=%f", mon.rtDelayOnscreen, now_ts, localTimeOnStreamer, self.hlsRTStreamTipPtsStampS, onDecoPtsV, self.hlsRTStreamTipPts);
    }
    //    BOOL isFound = NO;
    //    double ptsLocalStampTs = 0;
    //    double ptsLocalStampPts = 0;
    //    if(onScrnPts > 0 && onDecoPts > 0){
    //        double ptsHistory[1000];
    //        double tsHistory[1000];
    //        int ptsHistorySize = [self.player fillPtsHistory:ptsHistory ptsTsHistory:tsHistory size:1000];
    //        stats[kDVGPlayerStatsRtLateLocalTsLast] = @(tsHistory[ptsHistorySize-1]);
    //        stats[kDVGPlayerStatsRtLateLocalPtsLast] = @(ptsHistory[ptsHistorySize-1]);
    //        // Searching for shown pts
    //        for(NSArray* chunkStats in [self.statChunkPts reverseObjectEnumerator]){
    //            double csStamp = [chunkStats[1] doubleValue];
    //            for(int i = 0; i < ptsHistorySize; i++){
    //                if(fabs(csStamp - ptsHistory[i]) < 0.01f){
    //                    // Found!
    //                    isFound = YES;
    //                    ptsLocalStampTs = tsHistory[i];
    //                    ptsLocalStampPts = ptsHistory[i];
    //                    //ptsServerStampTs = [chunkStats[0] doubleValue];
    //                    break;
    //                }
    //            }
    //            if(isFound){
    //                break;
    //            }
    //        }
    //    }
    //    stats[kDVGPlayerStatsRtLateLocalTs] = @(ptsLocalStampTs);
    //    stats[kDVGPlayerStatsRtLateLocalPts] = @(ptsLocalStampPts);
    stats[kDVGPlayerStatsBuffDelayV] = @(mon.rtDelayOnbuffV);
    stats[kDVGPlayerStatsBuffDelayA] = @(mon.rtDelayOnbuffA);
    stats[kDVGPlayerStatsRtLate] = @(mon.rtDelayOnscreen);
    stats[kDVGPlayerStatsReseekState] = @(self.playlist_reseekstate);
    
    [self.httpChunkLoader statsFillHotData:stats];
}

NSString* lastActiveStreamName = nil;
+ (void)uploadLogsForStream:(NSString*)streamName {
    if([streamName length] == 0){
        // Last used stream
        streamName = [lastActiveStreamName copy];
    }
    if([streamName length] == 0){
        streamName = @"unknown";
    }
    NSString* playlistName = [NSString stringWithFormat:@"logs:player:%@",streamName];
    NSString* uploadHlsUrl = kVideoStreamLogsUplFileTempl;
    uploadHlsUrl = [uploadHlsUrl stringByReplacingOccurrencesOfString:@"{url_base}" withString:kVideoStreamLogsUplURLBase];
    uploadHlsUrl = [uploadHlsUrl stringByReplacingOccurrencesOfString:@"{name}" withString:playlistName];
    uploadHlsUrl = [uploadHlsUrl stringByReplacingOccurrencesOfString:@"{chunk}" withString:@"0"];
    uploadHlsUrl = [uploadHlsUrl stringByReplacingOccurrencesOfString:@"{frame}" withString:@"0"];
    uploadHlsUrl = [uploadHlsUrl stringByReplacingOccurrencesOfString:@"{stamp}" withString:@""];
    uploadHlsUrl = [uploadHlsUrl stringByReplacingOccurrencesOfString:@"{meta}" withString:@""];
    VLLog(@"Uploading logs to %@...", uploadHlsUrl);
    NSString* logsData = [VLLogger GetLogs:YES];
    if([logsData length] == 0){
        return;
    }
    NSData* hls_dat = [logsData dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *URL = [NSURL URLWithString:uploadHlsUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"content-type"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionUploadTask* httpManagerUT = [session uploadTaskWithRequest:request fromData:hls_dat completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        VLLog(@"HLSUploader result for url=%@: %@ %@", uploadHlsUrl, response, error);
    }];
    [httpManagerUT resume];
}

// requesting last chunk and Logs time. endlessly
+ (void)performSpeedTestForStream:(NSString*_Nullable)active_lowlat_playlist logView:(DVGLLPlayerStatLogs*)logview
{
    static NSInteger checkedChunks = 0;
    static NSInteger checkedChunksOvertm = 0;
    NSString* getMetaHlsUrl = kVideoStreamLowLatMetaTempl;
    getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{base_url}"
                                                             withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatMetaURLBase"]];
    getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{name}" withString:active_lowlat_playlist];
    //getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{cachepnc}" withString:[NSString stringWithFormat:@"%f",[DVGPlayerServerChecker unixStamp]]];
    //getMetaHlsUrl = [getMetaHlsUrl stringByAddingPercentEncodingWithAllowedCharacters:[[NSCharacterSet characterSetWithCharactersInString:@"&"] invertedSet]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:getMetaHlsUrl] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [request setHTTPMethod:@"POST"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.allowsCellularAccess = YES;
    NSURLSessionDataTask* downloadTask1 = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if(error != nil){
            [logview addLogLine:VLLog(@"performSpeedTestForStream failed with error: %@ %@", error, active_lowlat_playlist)];
            //dispatch_async( dispatch_get_main_queue(), ^{
            //    [DVGLLPlayerView performSpeedTestForStream:active_lowlat_playlist];
            //});
            return;
        }
        NSError *JSONError = nil;
        NSDictionary* responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
        if(responseObject[@"chunk"] == nil || responseObject[@"chunk"] == [NSNull null]){
            [logview addLogLine:VLLog(@"performSpeedTestForStream: failed with error: %@ %@", responseObject, active_lowlat_playlist)];
            return;
        }
        double tsServer = ((double)[responseObject[@"serverts"] longLongValue])/1000.0f;
        //double tsServerChunkLastWrite = ((double)[responseObject[@"lastopts"] longLongValue])/1000.0f;
        double tsServerChunkFirstWrite = ((double)[responseObject[@"chunkts"] longLongValue])/1000.0f;
        //double serverHas = tsServerChunkLastWrite-tsServerChunkFirstWrite;
        //if(serverHas > 1.0){
        //    // Too much, skipping
        //    dispatch_async( dispatch_get_main_queue(), ^{
        //        [DVGLLPlayerView performSpeedTestForStream:active_lowlat_playlist];
        //    });
        //    return;
        //}
        NSDictionary* meta = [DVGLLPlayerView serverPListToDictionary:responseObject[@"meta"]];
        double hlsChunkDuration = 1.0;
        NSInteger finStreamId = 0;
        double finStreamPts = 0.0;
        if(meta != nil){
            hlsChunkDuration = [meta[@"dur"] integerValue];
            finStreamId = [meta[@"fin"] integerValue];
            finStreamPts = [meta[@"pts"] doubleValue];
        }
        double chunkStartPts = 0;
        double chunkStrUdlSec = 0;
        double hlsRTStreamTipPts = 0;
        double chunkStartPtsTs = 0;
        NSDictionary* chunkmeta = meta;//[DVGLLPlayerView serverPListToDictionary:responseObject[@"chunkmeta"]];
        if(chunkmeta != nil){
            chunkStartPts = [chunkmeta[@"ch_pts"] doubleValue];
            chunkStrUdlSec = [chunkmeta[@"ch_udl"] doubleValue];
            chunkStartPtsTs = [chunkmeta[@"ch_ptsts"] doubleValue];
            hlsRTStreamTipPts = chunkStartPts + tsServer - tsServerChunkFirstWrite;
        }
        NSInteger hlsRTChunk = [responseObject[@"chunk"] integerValue];
        double chunkTs = chunkStartPtsTs;
        // Generating chunk list and feeding to parallel downloader
        NSMutableArray* chunksUrls4Pusher = @[].mutableCopy;
        NSMutableDictionary* chunksUrls4PusherStartTimes = @{}.mutableCopy;
        for(int i=0;i<1000;i++){
            double thisChunkTs = chunkTs+hlsChunkDuration*i;
            NSString* chunkUrl = kVideoStreamLowLatChunkTempl;
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{base_url}"
                                                           withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"]];
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{name}" withString:active_lowlat_playlist];
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{chunk}" withString:[NSString stringWithFormat:@"%lu", hlsRTChunk+i]];
            [chunksUrls4Pusher addObject:@[chunkUrl,@"",@""]];
            chunksUrls4PusherStartTimes[chunkUrl] = @(thisChunkTs-hlsChunkDuration+hlsChunkDuration*kPlayerStreamChunksPrefetchFrac);
        }
        DVGPlayerChunkLoader* loader = [[DVGPlayerChunkLoader alloc] init];
        loader.autoCancelOutdatedChunks = NO;
        loader.onChunkDownloaded = ^BOOL(NSString * _Nonnull url2, NSData * _Nullable data2, NSDictionary* taskData, NSError * _Nullable error2) {
            CGFloat startTime1 = [taskData[@"ts_start"] doubleValue];
            CGFloat stopTime = [taskData[@"ts_stop"] doubleValue];
            CGFloat downloadTime = stopTime-startTime1;
            if(error2 != nil){
                checkedChunksOvertm++;
                [logview addLogLine:VLLog(@"-> Time=%.02f, error=%@", downloadTime, [error2 localizedDescription])];
                return NO;
            }
            checkedChunks++;
            if(downloadTime > hlsChunkDuration+0.5){
                checkedChunksOvertm++;
            }
            NSInteger fileSize = data2.length;
            [logview addLogLine:VLLog(@"-> Time=%.02f, Size = %lu ratio=%lu/%lu", downloadTime, fileSize, checkedChunks, checkedChunksOvertm)];
            return YES;
        };
        [loader prepareForAvgChunkDuration:hlsChunkDuration prefetchCount:kPlayerStreamChunksPrefetchLimit];
        [loader prepareChunksTimingForList:chunksUrls4PusherStartTimes];
        [loader downloadChunksFromList:chunksUrls4Pusher andContinue:nil];
//        NSString* chunkUrl = kVideoStreamLowLatChunkTempl;
//        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{base_url}"
//                                                       withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"]];
//        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{name}" withString:active_lowlat_playlist];
//        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{chunk}" withString:[NSString stringWithFormat:@"%lu", hlsRTChunk]];
//        NSMutableURLRequest *request2 = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:chunkUrl] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
//        VLLog(@"%@ #%lu, Server has=%.02fsec", active_lowlat_playlist, hlsRTChunk, serverHas);
//        double tsLocalBefore = [DVGPlayerServerChecker unixStamp];
//        NSURLSessionDataTask* downloadTask2 = [[NSURLSession sharedSession] dataTaskWithRequest:request2 completionHandler:^(NSData * _Nullable data2, NSURLResponse * _Nullable response2, NSError * _Nullable error2){
//            double tsLocalAfter = [DVGPlayerServerChecker unixStamp];
//            double loadtime = tsLocalAfter-tsLocalBefore;
//            checkedChunks++;
//            if(loadtime > hlsChunkDuration+0.5){
//                checkedChunksOvertm++;
//            }
//            NSInteger fileSize = data2.length;
//            VLLog(@"-> Time=%.02f, Size = %lu (upd=%.02f, %lu/%lu)", loadtime, fileSize, chunkStrUdlSec, checkedChunks, checkedChunksOvertm);
//            dispatch_async( dispatch_get_main_queue(), ^{
//                [DVGLLPlayerView performSpeedTestForStream:active_lowlat_playlist];
//            });
//        }];
//        [downloadTask2 resume];
    }];
    [downloadTask1 resume];
}
@end


