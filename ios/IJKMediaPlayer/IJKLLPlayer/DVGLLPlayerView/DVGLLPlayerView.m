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
#import "DVGPlayerServerChecker.h"
#import "DVGPlayerChunkLoader.h"
#import "DVGPlayerFileUtils.h"


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

@property (atomic,assign) double hlsChunkDuration;
@property (atomic,assign) double hlsStreamFps;
@property (atomic,assign) double hlsRTStreamStartupInitsNeeded;
@property (atomic,assign) double hlsRTStreamTipUplDelay;
@property (atomic,assign) double hlsRTStreamTipPtsStamp;
@property (atomic,assign) double hlsRTStreamTipPts;
@property (atomic,assign) double hlsRTStreamTipAfterReseekPts;
@property (atomic,assign) NSInteger hlsIsClosed;
@property (atomic,assign) NSInteger hlsRTChunk;

@property (atomic,assign) NSInteger playlistId;
@property (atomic,assign) double regenPlaylistEndIsNear;
@property (atomic,strong) NSTimer *playerTrackTimer;

@property (atomic,assign) double statLastRtDelayCheck;
@property (atomic,strong) NSMutableArray* statChunkPts;

//@property (strong,atomic) AFxJSONResponseSerializer* httpManagerSerializer;
//@property (strong,atomic) AFxHTTPSessionManager* httpManager;
@property (strong,atomic) DVGPlayerChunkLoader* httpChunkLoader;
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
            [DVGPlayerFileUtils overloadConfigurationKey:@"kVideoStreamLowLatMetaURLBase" value:topserver];
        }
    }
}

- (void)preparePlayer {
    if(self.isInitialized){
        return;
    }
    [DVGLLPlayerView ffmpegPreheating];
    self.httpChunkLoader = [[DVGPlayerChunkLoader alloc] init];
    self.isInitialized = YES;
    self.scalingMode = IJKMPMovieScalingModeAspectFill;// IJKMPMovieScalingModeAspectFit
    [DVGLLPlayerView switchToOptimalServer];
}

// initializes view with lowlat playlist
- (void)setPlayerForLowLatPlaylist:(NSString*)ll_playlist {
    [self preparePlayer];
    if([ll_playlist characterAtIndex:ll_playlist.length-1] == '?'){
        ll_playlist = [ll_playlist stringByReplacingOccurrencesOfString:@"?" withString:@""];
        [DVGLLPlayerView performSpeedTestForStream:ll_playlist];
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
- (void)shutdownPlayer
{
    [self setPlayerForURL:nil];
}

- (void)dealloc
{
    [self shutdownPlayer];
}

//- (void)viewDidDisappear:(BOOL)animated {
//    [super viewDidDisappear:animated];
//    [self setPlayerForURL:nil];
//}
-(void)willMoveToSuperview:(UIView *)newSuperview {
    if (newSuperview == nil) {
        [self shutdownPlayer];
    }
}
-(void) didMoveToWindow {
    [super didMoveToWindow];
    if (self.window == nil) {
        [self shutdownPlayer];
    }
}

// Replaces ijk player source URL
// Normally ijk player should be recreated, but for lowlat functionality source replacement is much faster
- (void)updatePlayerForURLInplace:(NSURL*)playurl {
    VLLog(@"updatePlayerForURLInplace: %@",playurl);
    if(self.player == nil){
        return;
    }
    [self removeMovieNotificationObservers];
    [self.player stop];
    [self.player updateURL:playurl];
    self.tsStalledStart = -1;
    self.secondsInStall = 0;
    self.hlsRTStreamTipPts = 0;
    self.hlsRTStreamTipUplDelay = 0;
    self.hlsRTStreamTipPtsStamp = 0;
    [self installMovieNotificationObservers];
    [self.player prepareToPlay];
}

// Swaps ijk player for new one and point ijk player to new source url
- (void)setPlayerForURL:(NSURL*)playurl {
    VLLog(@"setPlayerForURL: %@",playurl);
    [self preparePlayer];
    if(self.player != nil){
        [self.playerTrackTimer invalidate];
        [self.player.view removeFromSuperview];
        [self.player shutdown];
        [self removeMovieNotificationObservers];
        if ([self.delegate respondsToSelector:@selector(onDVGLLPlayerUpdate:)]) {
            [self.delegate onDVGLLPlayerUpdate:nil];
        }
        self.player = nil;
        self.playerTrackTimer = nil;
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
    mon.rtDelayOnbuff = 0;
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
    double curStamp = [[NSDate date] timeIntervalSince1970];
    double ontippts = 0.0;
    if(self.hlsRTStreamTipPts > 0){
        ontippts = self.hlsRTStreamTipPts + (curStamp-self.hlsRTStreamTipPtsStamp);
    }
    double onbufpts = [self.player getOnbuffPts];
    //double onscrpts = [self.player getOnscreenPts];//  HEVC play trick on this... not sustainable
    double rtDelay = (onbufpts > 0 && ontippts > 0)?(ontippts - onbufpts):0.0;
    BOOL isLastReseekFailed = NO;
    if(self.hlsRTStreamTipAfterReseekPts > 0 && onbufpts > 0
       && self.hlsRTStreamTipAfterReseekPts > onbufpts && ontippts > self.hlsRTStreamTipAfterReseekPts){
        // Reseek not fast enough to fast-forward to real time
        isLastReseekFailed = YES;
    }
    
    BOOL tryReseek = NO;
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
            if(self.secondsInStall > kPlayerRestartOnStallingSec || rtDelay > kPlayerRestartOnPtsLateChunkSec){
                VLLog(@"HLSLOWLAT: Stalling for too long, requesting restart (%.02f > %.02f, ptslate: %.02f, lastfail%i)", self.secondsInStall, kPlayerRestartOnStallingSec, rtDelay, isLastReseekFailed);
                self.playlist_state = PLSTATE_NEEDREGENERATION;
                self.playlist_stallrestarts++;
                //}else{
                //    VLLog(@"HLSLOWLAT:  Stalling for too long, but reseek is pending (exp%.02f > buf%.02f, tip%.02f)",
                //          self.hlsRTStreamTipAfterReseekPts, onbufpts, ontippts);
                //}
            }else
            {
                double maxPtsLate = self.hlsChunkDuration*kPlayerReseekOnPtsLateChunkFrac+kPlayerAvgInBufftime;
                if(rtDelay > maxPtsLate){
                    if(onbufpts > self.hlsRTStreamTipAfterReseekPts){
                        //VLLog(@"HLSLOWLAT: Last shown frame too late for stream, requesting restart (%.02f > %.02f)", ontippts, onscrpts);
                        //self.playlist_state = PLSTATE_NEEDREGENERATION;
                        //self.playlist_stallrestarts++;
                        VLLog(@"HLSLOWLAT: Last shown frame too late for stream, trying to reseek (tip%.02f > buf%.02f, rtd%.02f, lastfail%i)", ontippts, onbufpts, rtDelay, isLastReseekFailed);
                        tryReseek = YES;
                    }else{
                        VLLog(@"HLSLOWLAT: Last shown frame too late for stream, but reseek is pending (exp%.02f > buf%.02f, tip%.02f, rtd%.02f, lastfail%i)",
                              self.hlsRTStreamTipAfterReseekPts, onbufpts, ontippts, rtDelay, isLastReseekFailed);
                    }
                }
            }
        }
    }
    if(self.hlsRTStreamStartupInitsNeeded > 0 && onbufpts > 0.001 && ontippts > 0.001){
        // Checking initial delays and deciding on seeking to realtime tip of the stream
        self.secondsInStall = 0;
        self.hlsRTStreamStartupInitsNeeded = 0;
        self.statLastRtDelayCheck = CACurrentMediaTime();
        [self.player setAccurateBufferingSec:kPlayerAvgInBufftime fps:self.hlsStreamFps];
        VLLog(@"HLSLOWLAT: Player ready, chunkId=%lu fps=%lu stt=%i upl_dl=%.02f",
              self.hlsRTChunk, self.hlsStreamFps, self.hlsIsClosed, self.hlsRTStreamTipUplDelay);
        tryReseek = YES;
        if ([self.delegate respondsToSelector:@selector(onDVGLLPlaylistStarted)]) {
            [self.delegate onDVGLLPlaylistStarted];
        }
    }
    if(self.hlsIsClosed == 0 && CACurrentMediaTime() > self.regenPlaylistEndIsNear){
        // We have to regenerate out handmade playlist if we are almost at the end
        VLLog(@"HLSLOWLAT: Playlist almost over, requesting restart");
        self.playlist_state = PLSTATE_NEEDREGENERATION;
    }
    if(self.playlist_state >= PLSTATE_NEEDREGENERATION){
        self.tsStalledStart = -1;
        self.secondsInStall = 0;
        [self syncToLowLatPlaylist];
    }else{
        if(tryReseek){
            if(self.hlsIsClosed == 0 && rtDelay > kPlayerAvgInBufftime){
                //  kPlayerAvgInBufftime will be introduced with buffering on waitForChance2SeekSkip
                VLLog(@"HLSLOWLAT: reseek to catchup with realtime %f", rtDelay);
                self.hlsRTStreamTipAfterReseekPts = ontippts + kPlayerAvgInBufftime;
                dispatch_async( dispatch_get_main_queue(), ^{
                    [self waitForChance2SeekSkip:0 targetPts: ontippts - kPlayerAvgInBufftime];
                });
            }else{
                VLLog(@"HLSLOWLAT: reseek skipped %i/%.02f",self.hlsIsClosed,rtDelay);
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
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.allowsCellularAccess = YES;
    configuration.multipathServiceType = kDVGPlayerMultipathServiceType;
    double tsLocalBefore = [[NSDate date] timeIntervalSince1970];
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
        double tsLocalAfter = [[NSDate date] timeIntervalSince1970];
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
        double tsServer = [responseObject[@"serverts"] integerValue]/1000.0;
        double tsServerChunkLastWrite = [responseObject[@"lastopts"] integerValue]/1000.0;
        double tsServerChunkFirstWrite = [responseObject[@"chunkts"] integerValue]/1000.0;
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
        double chunkStrUdlSec = 0;
        NSDictionary* chunkmeta = [DVGLLPlayerView serverPListToDictionary:responseObject[@"chunkmeta"]];
        if(chunkmeta != nil){
            chunkStartPts = [chunkmeta[@"pts"] doubleValue];
            chunkStrUdlSec = [chunkmeta[@"udl"] doubleValue];
            self.hlsRTStreamTipUplDelay = chunkStrUdlSec;
            self.hlsRTStreamTipPts = chunkStartPts + (tsServerChunkLastWrite-tsServerChunkFirstWrite);
            self.hlsRTStreamTipPtsStamp = tsLocal;
        }
        self.hlsRTChunk = [responseObject[@"chunk"] integerValue];
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
        chunkdata[@"playlist"] = self.active_lowlat_playlist;
        chunkdata[@"chunk"] = @(self.hlsRTChunk);
        chunkdata[@"url_template"] = kVideoStreamLowLatChunkTempl;
        chunkdata[@"chunk_duration"] = @(self.hlsChunkDuration);
        chunkdata[@"chunk_fin"] = @(finStreamId);
        if(self.statChunkPts == nil){
            self.statChunkPts = @[].mutableCopy;
        }
        [self.statChunkPts addObject:@[@(tsServerChunkFirstWrite), @(chunkStartPts), @(self.hlsRTChunk)]];
        while([self.statChunkPts count]>10){
            [self.statChunkPts removeObjectAtIndex:0];
        }
        // stats
        NSMutableDictionary* stats = @{}.mutableCopy;
        IJKFFMonitor* mon = [self.player getJkMonitor];
        [self statsFillHotData:stats];
        double onScreenPts = [self.player getOnscreenPts];
        double onBufPts = [self.player getOnbuffPts];
        if(onScreenPts > 0 && self.hlsRTStreamTipPts > 0){
            double ontippts = self.hlsRTStreamTipPts + (tsLocalAfter-self.hlsRTStreamTipPtsStamp);
            mon.rtDelayOnscreen = ontippts-onScreenPts;
        }
        mon.stallMarker = self.secondsInStall;
        stats[kDVGPlayerStatsStalltime] = @(mon.stallMarker);
        stats[kDVGPlayerStatsRtLate] = @(mon.rtDelayOnscreen > 0?(mon.rtDelayOnscreen + chunkStrUdlSec):0.0);
        stats[kDVGPlayerStatsUploaderDelay] = @(chunkStrUdlSec);
        VLLog(@"PLAY STATS: chk = %@, rt-late = %.02fsec, known streamer delay = %.02f. ontip_pts=%.02f onbuf_pts=%.02f, onscr_pts=%.02f, s-diff: %.02f",
              chunkdata[@"chunk"], mon.rtDelayOnscreen > 0?(mon.rtDelayOnscreen + chunkStrUdlSec):0.0, chunkStrUdlSec,
              self.hlsRTStreamTipPts, onBufPts, onScreenPts, tsLocalAfter-tsLocalBefore);
        // If this is old stream - starting from 1, no reseeks
        if(finStreamId > 0 || tsServer - tsServerChunkFirstWrite > self.hlsChunkDuration*2.0
           //|| chunkStrUdlSec > kPlayerNoSkipOnBadUploaderSec
        ){
            if(self.playlist_state == PLSTATE_NEEDINTIALIZATION){
                VLLog(@"HLSLOWLAT: Non-RT playlist detected, stopping RT-logic %@ %@", chunkdata, stats);
            }else if(self.hlsIsClosed < 1){
                VLLog(@"HLSLOWLAT: Streamer delays are too big, stopping RT-logic %@ %@", chunkdata, stats);
            }
            self.hlsIsClosed = 1;
            chunkdata[@"chunk"] = @(1);
        }
        stats[kDVGPlayerStatsIsRealtime] = @(self.hlsIsClosed>0?NO:YES);
        
        BOOL needCheckStreamFinish = NO;
        if(self.playlist_state != PLSTATE_NEEDINTIALIZATION && self.playlist_state >= PLSTATE_PLAYING){
            needCheckStreamFinish = YES;
        }
        if(needCheckStreamFinish){
            BOOL isStreamEnd = NO;
            double onBuffPts = [self.player getOnbuffPts];
            if(finStreamId > 0 && finStreamPts < onBuffPts+kPlayerAvgInBufftime){
                isStreamEnd = YES;
            }
            if(isStreamEnd){
                VLLog(@"syncToLowLatPlaylist: End of stream found");
                self.secondsInStall = 0;
                self.playlist_state = PLSTATE_FINISHED;
                [self.player stop];
                if ([self.delegate respondsToSelector:@selector(onDVGLLPlaylistFinished)]) {
                    [self.delegate onDVGLLPlaylistFinished];
                }
            }
        }
        if(self.playlist_state >= PLSTATE_NEEDREGENERATION){
            [self playPlaylistWithMsg:chunkdata futureOffset:1 fakeChunkAdvance:1000];
        }
        if ([self.delegate respondsToSelector:@selector(onDVGLLPlayerStatsUpdated:)]) {
            [self.delegate onDVGLLPlayerStatsUpdated:stats];
        }
    }];
    [downloadTask resume];
}

- (void)statsFillHotData:(NSMutableDictionary*)stats {
    IJKFFMonitor* mon = [self.player getJkMonitor];
    double onScreenPts = [self.player getOnscreenPts];
    double onBuffPts = [self.player getOnbuffPts];
    mon.rtDelayOnbuff = 0;
    if(onBuffPts > 0 && onScreenPts>0){
        mon.rtDelayOnbuff = onBuffPts-onScreenPts;
    }
    BOOL isFound = NO;
    double ptsLocalStampTs = 0;
    //double ptsServerStampTs = 0;
    double ptsLocalStampPts = 0;
    if(onScreenPts > 0 && onBuffPts > 0){
        double ptsHistory[1000];
        double tsHistory[1000];
        int ptsHistorySize = [self.player fillPtsHistory:ptsHistory ptsTsHistory:tsHistory size:1000];
        stats[kDVGPlayerStatsRtLateLocalTsLast] = @(tsHistory[ptsHistorySize-1]);
        stats[kDVGPlayerStatsRtLateLocalPtsLast] = @(ptsHistory[ptsHistorySize-1]);
        // Searching for shown pts
        for(NSArray* chunkStats in [self.statChunkPts reverseObjectEnumerator]){
            double csStamp = [chunkStats[1] doubleValue];
            for(int i = 0; i < ptsHistorySize; i++){
                if(fabs(csStamp - ptsHistory[i]) < 0.01f){
                    // Found!
                    isFound = YES;
                    ptsLocalStampTs = tsHistory[i];
                    ptsLocalStampPts = ptsHistory[i];
                    //ptsServerStampTs = [chunkStats[0] doubleValue];
                    break;
                }
            }
            if(isFound){
                break;
            }
        }
    }

    //stats[kDVGPlayerStatsRtLateServerTs] = @(ptsServerStampTs);
    stats[kDVGPlayerStatsRtLateLocalTs] = @(ptsLocalStampTs);
    stats[kDVGPlayerStatsRtLateLocalPts] = @(ptsLocalStampPts);
    stats[kDVGPlayerStatsBuffDelay] = @(mon.rtDelayOnbuff);
}

// Generating handmade playlist for the stream. And pointing jk player on it
- (void)playPlaylistWithMsg:(NSDictionary*)chunkdata futureOffset:(NSInteger)foffset fakeChunkAdvance:(NSInteger)chunks {
    BOOL useLowlatDownloader = YES;
    self.playlist_state = PLSTATE_PLAYING;
    self.playlistId += 1;
    self.secondsInStall = 0;
    NSString* playlistName = chunkdata[@"playlist"];
    NSInteger chunkDur = [chunkdata[@"chunk_duration"] integerValue];
    NSInteger chunkId = [chunkdata[@"chunk"] integerValue];
    self.regenPlaylistEndIsNear = CACurrentMediaTime()+self.hlsChunkDuration*MAX(3,chunks-3);
    NSMutableArray* hlsContent = @[].mutableCopy;
    [hlsContent addObject:@"#EXTM3U"];
    [hlsContent addObject:@"#EXT-X-VERSION:3"];
    [hlsContent addObject:[NSString stringWithFormat:@"#EXT-X-TARGETDURATION:%li", (long)chunkDur]];
    
    NSString* firstUrl = nil;
    NSMutableArray* chunksUrls4Pusher = @[].mutableCopy;
    for (int i=0;i<chunks;i++) {
        [hlsContent addObject:@""];
        [hlsContent addObject:[NSString stringWithFormat:@"#EXTINF:%li,", (long)chunkDur]];
        
        NSString* chunkUrl = chunkdata[@"url_template"];
        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{base_url}"
                                                                 withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"]];
        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{name}" withString:playlistName];
        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{chunk}" withString:[NSString stringWithFormat:@"%lu", chunkId+i+(foffset-1)]];
        NSString* chunkUrlWeb = chunkUrl;
        if(useLowlatDownloader){
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"http://" withString:@""];
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"https://" withString:@""];
            NSArray* chunkPair = [self.httpChunkLoader getChunkUnixPairForUrl:chunkUrl];
            [hlsContent addObject:[NSString stringWithFormat:@"llhls://%@?%@",chunkPair[0], chunkPair[1]]];
            [chunksUrls4Pusher addObject:@[chunkUrlWeb, chunkPair[0], chunkPair[1]]];
        }else{
            [hlsContent addObject:[NSString stringWithFormat:@"%@",chunkUrl]];
            [chunksUrls4Pusher addObject:@[chunkUrlWeb, chunkUrl]];
        }
        if(firstUrl == nil){
            firstUrl = chunkUrl;
        }
    }
    if(self.hlsIsClosed > 0){
        // Non-realtime logic for ffmpeg
        [hlsContent addObject:@""];
        [hlsContent addObject:@"#EXT-X-ENDLIST"];
    }
    NSString* joinedHlsContent = [hlsContent componentsJoinedByString:@"\n"];
    
    NSString *tempPath = NSTemporaryDirectory();
    NSString* fileName = [NSString stringWithFormat:@"hls_%@_%li.m3u8",playlistName,self.playlistId];
    NSURL *directoryURL = [NSURL fileURLWithPath:tempPath isDirectory:YES];
    NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
    NSError* error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:&error];
    error = nil;
    [joinedHlsContent writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if(error == nil){
        if(useLowlatDownloader){
            [self.httpChunkLoader resetPendingDownloads];
            [self.httpChunkLoader downloadChunksFromList:chunksUrls4Pusher prefetchLimit:kPlayerStreamChunksPrefetchLimit avgChunkDuration:chunkDur];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if(self.player != nil){
                // Player already created, no need to recreate it - just replacing ijk player source URL with new one
                // this is much faster than creating ijk player from scratch
                [self updatePlayerForURLInplace:fileURL];
                return;
            }
            // Initializing player with local playlist
            [self setPlayerForURL:fileURL];
        });
    }
    VLLog(@"HLS: Regenerating playlist with chunk data %@", chunkdata);
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
+ (void)performSpeedTestForStream:(NSString*_Nullable)active_lowlat_playlist
{
    static NSInteger checkedChunks = 0;
    static NSInteger checkedChunksOvertm = 0;
    NSString* getMetaHlsUrl = kVideoStreamLowLatMetaTempl;
    getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{base_url}"
                                                             withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatMetaURLBase"]];
    getMetaHlsUrl = [getMetaHlsUrl stringByReplacingOccurrencesOfString:@"{name}" withString:active_lowlat_playlist];
    //getMetaHlsUrl = [getMetaHlsUrl stringByAddingPercentEncodingWithAllowedCharacters:[[NSCharacterSet characterSetWithCharactersInString:@"&"] invertedSet]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:getMetaHlsUrl] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [request setHTTPMethod:@"POST"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.allowsCellularAccess = YES;
    NSURLSessionDataTask* downloadTask1 = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if(error != nil){
            VLLog(@"performSpeedTestForStream failed with error: %@ %@", error, active_lowlat_playlist);
            //dispatch_async( dispatch_get_main_queue(), ^{
            //    [DVGLLPlayerView performSpeedTestForStream:active_lowlat_playlist];
            //});
            return;
        }
        NSError *JSONError = nil;
        NSDictionary* responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
        if(responseObject[@"chunk"] == nil || responseObject[@"chunk"] == [NSNull null]){
            VLLog(@"performSpeedTestForStream: failed with error: %@ %@", responseObject, active_lowlat_playlist);
            return;
        }
        //double tsServer = [responseObject[@"serverts"] integerValue]/1000.0;
        double tsServerChunkLastWrite = [responseObject[@"lastopts"] integerValue]/1000.0;
        double tsServerChunkFirstWrite = [responseObject[@"chunkts"] integerValue]/1000.0;
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
        double hlsRTStreamTipPts= 0;
        NSDictionary* chunkmeta = [DVGLLPlayerView serverPListToDictionary:responseObject[@"chunkmeta"]];
        if(chunkmeta != nil){
            chunkStartPts = [chunkmeta[@"pts"] doubleValue];
            chunkStrUdlSec = [chunkmeta[@"udl"] doubleValue];
            hlsRTStreamTipPts = chunkStartPts + (tsServerChunkLastWrite-tsServerChunkFirstWrite);
        }
        NSInteger hlsRTChunk = [responseObject[@"chunk"] integerValue];
        // Generating chunk list and feeding to parallel downloader
        NSMutableArray* chunksUrls4Pusher = @[].mutableCopy;
        for(int i=0;i<1000;i++){
            NSString* chunkUrl = kVideoStreamLowLatChunkTempl;
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{base_url}"
                                                           withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"]];
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{name}" withString:active_lowlat_playlist];
            chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{chunk}" withString:[NSString stringWithFormat:@"%lu", hlsRTChunk+i]];
            [chunksUrls4Pusher addObject:@[chunkUrl,@"",@""]];
        }
        DVGPlayerChunkLoader* loader = [[DVGPlayerChunkLoader alloc] init];
        loader.onChunkDownloaded = ^BOOL(NSString * _Nonnull url2, NSData * _Nullable data2, NSDictionary* taskData, NSError * _Nullable error2) {
            CGFloat startTime1 = [taskData[@"ts_start"] doubleValue];
            CGFloat stopTime = [taskData[@"ts_stop"] doubleValue];
            CGFloat downloadTime = stopTime-startTime1;
            if(error2 != nil){
                VLLog(@"-> Time=%.02f, error=%@", downloadTime, error2);
                return NO;
            }
            checkedChunks++;
            if(downloadTime > hlsChunkDuration+0.5){
                checkedChunksOvertm++;
            }
            NSInteger fileSize = data2.length;
            VLLog(@"-> Time=%.02f, Size = %lu (upd=%.02f, %lu/%lu)", downloadTime, fileSize, chunkStrUdlSec, checkedChunks, checkedChunksOvertm);
            return YES;
        };
        [loader downloadChunksFromList:chunksUrls4Pusher prefetchLimit:kPlayerStreamChunksPrefetchLimit avgChunkDuration:hlsChunkDuration];
//        NSString* chunkUrl = kVideoStreamLowLatChunkTempl;
//        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{base_url}"
//                                                       withString:[DVGPlayerFileUtils configurationValueForKey:@"kVideoStreamLowLatChunkURLBase"]];
//        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{name}" withString:active_lowlat_playlist];
//        chunkUrl = [chunkUrl stringByReplacingOccurrencesOfString:@"{chunk}" withString:[NSString stringWithFormat:@"%lu", hlsRTChunk]];
//        NSMutableURLRequest *request2 = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:chunkUrl] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
//        VLLog(@"%@ #%lu, Server has=%.02fsec", active_lowlat_playlist, hlsRTChunk, serverHas);
//        double tsLocalBefore = CACurrentMediaTime();// [[NSDate date] timeIntervalSince1970];
//        NSURLSessionDataTask* downloadTask2 = [[NSURLSession sharedSession] dataTaskWithRequest:request2 completionHandler:^(NSData * _Nullable data2, NSURLResponse * _Nullable response2, NSError * _Nullable error2){
//            double tsLocalAfter = CACurrentMediaTime(); //[[NSDate date] timeIntervalSince1970];
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


