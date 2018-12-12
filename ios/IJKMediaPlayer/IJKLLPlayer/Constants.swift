//
//  Constants.swift
//  DVGPlayer
//
//  Created by Xinzhe Wang on 11/27/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import Foundation

// URL to retrieve stream information from LowLat server. Not real playlist, but special information from streamer
let kVideoStreamLowLatMetaURLBase = "http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/"
let kVideoStreamLowLatMetaTempl = "{base_url}getMeta?playlist={name}"

// URL to get chunks data (ts files)
let kVideoStreamLowLatChunkURLBase = "http://d1d7bq76ey2psd.cloudfront.net/"
let kVideoStreamLowLatChunkTempl = "{base_url}getChunk?playlist={name}&chunk={chunk}"

// // URL for uploading logs
let kVideoStreamLogsUplURLBase = "http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/"
let kVideoStreamLogsUplFileTempl = "{url_base}uploadMedia?playlist={name}&chunk={chunk}&frame={frame}&meta={meta}&tm={stamp}"


// Time difference between frames, shown in player and frames, downloaded from server.
let kDVGPlayerStatsRtLate = "kDVGPlayerStatsRtLate";
// Server timestamp of matched frames. Used for kDVGPlayerStatsRtLate calculations
//static NSString* _Nonnull const kDVGPlayerStatsRtLateServerTs = @"kDVGPlayerStatsRtLateServerTs";
// Local timestamp of matched frames. Used for kDVGPlayerStatsRtLate calculations
let kDVGPlayerStatsRtLateLocalTs = "kDVGPlayerStatsRtLateLocalTs";
// Local pts of matched frames. Used for kDVGPlayerStatsRtLate calculations
let kDVGPlayerStatsRtLateLocalPts = "kDVGPlayerStatsRtLateLocalPts";
// Local timestamp of most recently showns frames. Used for kDVGPlayerStatsRtLate calculations
let kDVGPlayerStatsRtLateLocalTsLast = "kDVGPlayerStatsRtLateLocalTsLast";
// Local pts of most recently showns frames. Used for kDVGPlayerStatsRtLate calculations
let kDVGPlayerStatsRtLateLocalPtsLast = "kDVGPlayerStatsRtLateLocalPtsLast";
// Average time difference approximation (player->network->server), since network may give some error
// Low values mean other stats are ok. High values mean other server-related stats are not reliable (network so unstable that math cant help here)
let kDVGPlayerStatsPlayerToServerTimerror = "kDVGPlayerStatsPlayerToServerTimerror";
// Seconds in wait for data. If player waits for data - this value will increase.
// Value will be 0 if player normally plays video (no stalls)
let kDVGPlayerStatsStalltime = "kDVGPlayerStatsStalltime";
// Known streamer (uploader) delay
let kDVGPlayerStatsUploaderDelay = "kDVGPlayerStatsUploaderDelay";
// kDVGPlayerStatsIsRealtime = NO, if player plays finished playlist (not realtime, stream ended some time ago). Player will no try any seeks
// kDVGPlayerStatsIsRealtime = YES, if player play active stream. In this case player will try to seek to real time inside stream.
let kDVGPlayerStatsIsRealtime = "kDVGPlayerStatsIsRealtime";
// Delay between parsing frames and show them on screen (player buffering)
let kDVGPlayerStatsBuffDelay = "kDVGPlayerStatsBuffDelay";

// Fraction of chunk duration to calculate time to calculate time threshold for using regular seek instead of accurate seekskip
let kPlayerUseAvSeekFrac = 2.1;

// seconds. Time threshold for "jumping" into playlist end after series of stalls
let kPlayerRestartOnPtsLateSec = 3.5;

// number of attempts. When player stalls for as many times - it stops any reseek logic due unstable network
let kPlayerStallReseekTolerate = 5;

// seconds. If uploader delay is bigger than this threashold - player will not try reseeks since there is no point in catchin up
let kPlayerNoSkipOnBadUploaderSec = 2.0;

// seconds. Used to calculate stream finish with sure
let kPlayerAvgInBufftime = 0.5;
