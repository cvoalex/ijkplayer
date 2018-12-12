//
//  DVGPlayer.swift
//  DVGPlayer
//
//  Created by Xinzhe Wang on 11/25/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import Foundation

protocol IJKLLPlayerDelegate: class {
    // Called when wrapper swap IJK player for another instance. Can be used to get additional info from ffplay
    func onPlayerUpdate(player: IJKMediaPlayback)
    
    // Called when there is an error asking server for metadata info
    func onError(error: NSError)
    
    // Called when stream is started to play
    func onStart()
    
    // Called when stream is finished on streamer side and player played all the video of the stream
    func onFinish()
    
    // Called periodically with averages for video lag and various delays
    func onStatsUpdate(dict: Dictionary<String, Any>)
}

struct IJKLLPlayerConfiguration {
    var metaURLBase: String = kVideoStreamLowLatMetaURLBase
    var chunkURLBase: String = kVideoStreamLowLatChunkURLBase
    var scalingMode: IJKMPMovieScalingMode = .aspectFill
    
    static var `default` = IJKLLPlayerConfiguration()
}

class IJKLLPlayer {
    weak var delegate: IJKLLPlayerDelegate?
    
    var playlistState = PlaylistState.none
    var stallDuration = 0 // in sec
    
    init() {}
    
    func setupStream(_ playlistId: String) {
        IJKFFMoviePlayerController.setLogReport(true)
        IJKFFMoviePlayerController.setLogLevel(k_IJK_LOG_DEFAULT)
        
        self.playlistState = .uninitiated(playlistId: playlistId)
        
    }
}

extension IJKLLPlayer {
    // Replaces ijk player source URL
    // Normally ijk player should be recreated, but for lowlat functionality source replacement is much faster
    private func swapSourceURL(_ url: URL) {
        
    }
    
    private func registerPlayerNotificationObservers() {
        
    }
    
    private func removePlayerNotificationObservers() {
        
    }
}

extension IJKLLPlayer {
    enum PlaylistState {
        case none
        case uninitiated(playlistId: String)
        case regenerated(playlistId: String)
        case playing(playlistId: String)
        case finished(playlistId: String)
    }
    
    struct Matrix {
        var stallStartTimestamp: Double = -1
        var chunkDuration = 2.0
    }
}
