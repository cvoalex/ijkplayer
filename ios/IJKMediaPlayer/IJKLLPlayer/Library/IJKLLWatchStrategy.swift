//
//  WatchStrategy.swift
//  DVGPlayer
//
//  Created by Xinzhe Wang on 11/28/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import Foundation

protocol IJKLLWatchStrategy {
    var loaderConfig: IJKLLChunkLoaderConfig { get }
    
    func decideAction(playerState: IJKLLPlayer.State, player: IJKMediaPlayback, meta: IJKLLMeta?) -> IJKLLWatchStrategyAction
}

enum IJKLLWatchStrategyAction {
    case none
    case start(startPTS: Double, bufferTime: Double, fps: Double)
    case seek(targetPTS: Double)
    case restart
}

class IJKLLRealTimeWatchStrategy: IJKLLWatchStrategy {
    var configuration = Configuration.default
    var loaderConfig = IJKLLChunkLoaderConfig.realTime
    
    func decideAction(playerState: IJKLLPlayer.State, player: IJKMediaPlayback, meta: IJKLLMeta?) -> IJKLLWatchStrategyAction {
        guard let meta = meta else { return .none }
        guard playerState.playlistState.realtimable else { return .none }
        guard let onTipPTS = meta.estCurrentOnTipPTS else { return .none }
        guard let fps = meta.streamFPS else { return .none }
        guard let chunkDuration = meta.streamChunkDuration else { return .none }
        let onBufPTS = player.getOnbuffPts()
        let delay = onTipPTS - onBufPTS
        let rtDelay = delay > 0 ? delay : 0
        let mostRecentPTS = onTipPTS - configuration.maxBufferTime
        switch playerState.playlistState {
        case .loading(playlistId: _):
            let hasData = onBufPTS > 0.001 && onTipPTS > 0.001
            return hasData ? .start(startPTS: mostRecentPTS, bufferTime: configuration.maxBufferTime, fps: Double(fps)) : .none
        case .playing(playlistId: _):
            // check if need to seek
            if rtDelay > configuration.getMaxReseekRTDelay(Double(chunkDuration)) {
                return .seek(targetPTS: mostRecentPTS)
            }
            return .none
        case let .stalled(playlistId: _, since: stoppedTS):
            let stoppedTime = Date().timeIntervalSince1970 - stoppedTS
            if stoppedTime > configuration.maxStall || rtDelay > configuration.maxRestartRTDelay {
                return .restart
            } else if rtDelay > configuration.getMaxReseekRTDelay(Double(chunkDuration)) {
                return .seek(targetPTS: mostRecentPTS)
            }
            return .none
        default:
            return .none
        }
    }
    
    struct Configuration {
        var maxStall = kPlayerRestartOnStallingSec
        var maxRestartRTDelay = kPlayerRestartOnPtsLateChunkSec
        //var maxReseekRTDelay = kPlayerRestartOnPtsLateChunkSec
        var maxBufferTime = kPlayerAvgInBufftime
        static var `default` = Configuration()
        
        func getMaxReseekRTDelay(_ chunkDuration: Double) -> Double {
            return chunkDuration * kPlayerReseekOnPtsLateChunkFrac + maxBufferTime
        }
    }
}

class IJKLLConcessiveWatchStrategy: IJKLLWatchStrategy {
    var loaderConfig = IJKLLChunkLoaderConfig.concessive
    
    func decideAction(playerState: IJKLLPlayer.State, player: IJKMediaPlayback, meta: IJKLLMeta?) -> IJKLLWatchStrategyAction {
        return .none
    }
}

class IJKLLStrategy {
    var strategy: IJKLLWatchStrategy = IJKLLRealTimeWatchStrategy()
    
    // Need to be call in sync
    func decideAction(playerState: IJKLLPlayer.State, player: IJKMediaPlayback, meta: IJKLLMeta?) -> IJKLLWatchStrategyAction {
        return strategy.decideAction(playerState: playerState, player: player, meta: meta)
    }
}
