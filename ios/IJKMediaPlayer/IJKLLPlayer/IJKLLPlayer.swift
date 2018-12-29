//
//  DVGPlayer.swift
//  DVGPlayer
//
//  Created by Xinzhe Wang on 11/25/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import Foundation

public protocol IJKLLPlayerDelegate: class {
    // Called when wrapper swap IJK player for another instance. Can be used to get additional info from ffplay
    func onPlayerUpdate(player: IJKMediaPlayback?)
    
    // Called when there is an error asking server for metadata info
    func onError(error: Error)
    
    // Called when stream is started to play
    func onStart()
    
    // Called when stream is finished on streamer side and player played all the video of the stream
    func onFinish()
    
    // Called periodically with averages for video lag and various delays
    func onStatsUpdate(loader: IJKLLChunkLoader)
}

public struct IJKLLPlayerConfig {
    var metaURLBase = kVideoStreamLowLatMetaURLBase
    var metaURLTemplate = kVideoStreamLowLatMetaTempl
    var chunkURLBase = kVideoStreamLowLatChunkURLBase
    var chunkURLTemplate = kVideoStreamLowLatChunkTempl
    
    var scalingMode: IJKMPMovieScalingMode = .aspectFill
    var shouldAutoplay = true
    var targetBufferTime = kPlayerAvgInBufftime
    var playbackFPS = 30.0
    
    var chunkDuration: TimeInterval = 2.0
    var metaSyncTimeInterval: TimeInterval = 2.0
    var maintenanceTimeInterval: TimeInterval = 1.0
    var chunkLoadCheckTimeInterval: TimeInterval = 0.3
    var statsUpdateTimeInterval: TimeInterval = 0.5
    
    // default as 2 sec chunk
    public static var `default` = IJKLLPlayerConfig()
}

public class IJKLLPlayer: NSObject {
    public weak var delegate: IJKLLPlayerDelegate?
    
    private let configuration: IJKLLPlayerConfig
    private var internalPlayer: IJKMediaPlayback?
    private(set) var state: State
    private var meta: IJKLLMeta?
    public var view: UIView? {
        return self.internalPlayer?.view
    }
    
    private var metaSyncRepeater: Repeater?
    private var maintenanceRepeater: Repeater?
    private var chunkLoadCheckRepeater: Repeater?
    private var statsUpdateRepeater: Repeater?
    
    private let stateSerialQueue = DispatchQueue(label: "me.mobcast.ijkllplayer.state.serialQueue")
    private let networkSession = SessionManager(configuration: .ijkllMeta)
    private let strategy = IJKLLStrategy()
    var chunkLoader: IJKLLChunkLoader?
    var chunkServer: DVGChunkServer?
    //var chunkServer: IJKLLChunkServer?
    var playlist = IJKLLPlaylist()
    //var streamId: String!
    
    public init(config: IJKLLPlayerConfig = .default, state: State = .default) {
        self.configuration = config
        self.state = state
    }
    
    public func play() {
        self.internalPlayer?.play()
    }
    
    public func pause() {
        self.internalPlayer?.pause()
    }
    
    
    public func prepareToPlay(_ streamId: String) {
        if let _ = self.internalPlayer {
            self.prepareToRelease()
        }
        do {
            let m3u8 = IJKLLPlayer.getM3U8Url(streamId)
            try FileManager.default.removeItem(at: m3u8)
        } catch {
            IJKLLLog.player("m3u8 file remove error(okay): \(error.localizedDescription)")
        }
        self.state.playlistState = .preparing(playlistId: streamId)
        self.playlist.delegate = self
        setupRepeaters(config: configuration)
        self.chunkLoader = IJKLLChunkLoader(config: .realTime, watcher: IJKLLStrategy())
        self.chunkLoader?.delegate = self
    }
    
    public func prepareToRelease() {
        self.internalPlayer?.shutdown()
        self.removePlayerNotificationObservers()
        self.internalPlayer = nil
        self.chunkLoader = nil
        self.chunkServer = nil
    }
    
    static func getM3U8Url(_ streamId: String) -> URL {
        let path = NSTemporaryDirectory()
        let fileName = "hls_\(streamId).m3u8"
        let tempUrl = URL(fileURLWithPath: path, isDirectory: true)
        let fileUrl = tempUrl.appendingPathComponent(fileName)
        return fileUrl
    }
}

extension IJKLLPlayer {
    func onMetaSyncRepeater() {
        // Update meta
        let playlistState = self.state.playlistState
        guard let url = makeMetaRequestURL(state: playlistState, config: self.configuration) else { return }
        let _ = networkSession.request(url, method: .post).responseData { [weak self] (response) in
            let decoder = JSONDecoder()
            let meta: Result<IJKLLMeta> = decoder.decodeResponse(from: response)
            switch meta {
            case let .success(llMeta):
                if let streamId = playlistState.playlistId {
                    var timelinedMeta = llMeta
                    timelinedMeta.requestTimeline = response.timeline
                    self?.playlist.write()
                    self?.playlist.refresh(playlistId: streamId, meta: timelinedMeta)
                    if playlistState.isPreparing {
                        // first meta, ready to setup player
                        self?.playlist.write()
                        self?.setupChunkServer()
                        self?.state.playlistState = .loading(playlistId: streamId)
                    }
                }
            case let .failure(error):
                self?.delegate?.onError(error: error)
            }
        }
    }
    
    func onMaintenanceRepeater() {
//        guard let player = self.internalPlayer, let monitor = player.getJkMonitor() else { return }
//        //guard let meta = self.meta else { return }
//        // Based on the currect state and strategy, shall allow three action: none, restart, seek
//        let action = strategy.decideAction(playerState: state, player: player, meta: meta)
//        switch action {
//        case .none:
//            break
//        case let .start(startPTS: pts, bufferTime: bt, fps: fps):
//            player.setAccurateBufferingSec(bt, fps: fps)
//            delegate?.onStart()
//            stateSerialQueue.async {
//                if let playlistId = self.state.playlistState.playlistId {
//                    self.state.playlistState = .playing(playlistId: playlistId)
//                }
//            }
//            player.doAccurateSeekSkip(pts)
//        case let .seek(targetPTS: pts):
//            player.doAccurateSeekSkip(pts)
//        case .restart:
//            // regen playlist
//            break
//        }
    }
    
    func onChunkLoadCheckRepeater() {
        // Fire download if needed
        guard let loader = self.chunkLoader else { return }
        guard let nextPeekChunk = self.playlist.peek() else { return }
        guard loader.fetchCheck(nextPeekChunk) else { return }
        guard let nextChunk = self.playlist.pop() else { return }
        IJKLLLog.player("Ready to fetch chunk \(nextChunk.sequence)")
        loader.fetch(nextChunk)
    }
    
//    func chunkFetch(chunk: IJKLLPlaylist.Chunk) {
//        guard let loader = self.chunkLoader else { return }
//        IJKLLLog.player("Ready to fetch chunk \(chunk.sequence)")
//        loader.fetch(chunk)
//    }
    
    func onStatsUpdateRepeater() {
        guard let loader = self.chunkLoader else { return }
        IJKLLLog.player("lastChunk \(loader.state.lastChunkStatus.description) tipChunk \(loader.state.tipChunkStatus.description)")
        delegate?.onStatsUpdate(loader: loader)
    }
}

extension IJKLLPlayer {
    func setupChunkServer() {
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        let socketPath = "\(cachePath)/playerloader"
        IJKLLLog.player("socket path \(cachePath)")
//        self.chunkServer = IJKLLChunkServer(socketPath: cachePath)
//        chunkServer?.delegate = self
//        self.chunkServer?.run()
        self.chunkServer = DVGChunkServer()
        chunkServer?.delegate = self
        self.chunkServer?.run(cachePath)
    }
    
    func setupIJKPlayer(_ streamId: String) {
        IJKFFMoviePlayerController.setLogReport(true)
        IJKFFMoviePlayerController.setLogLevel(k_IJK_LOG_DEFAULT)
        let options = IJKFFOptions.byDefault()
        let url = IJKLLPlayer.getM3U8Url(streamId)
        let player = IJKFFMoviePlayerController(contentURL: url, with: options)
        player?.scalingMode = configuration.scalingMode
        player?.shouldAutoplay = configuration.shouldAutoplay
        player?.setAccurateBufferingSec(configuration.targetBufferTime, fps: configuration.playbackFPS)
//        if let monitor = player?.getJkMonitor() {
//            monitor.rtDelayOnscreen = 0
//            monitor.rtDelayOnbuff = 0
//        }
        self.registerPlayerNotificationObservers()
        self.delegate?.onPlayerUpdate(player: player)
        self.internalPlayer = player
        self.internalPlayer?.prepareToPlay()
    }
    
    private func setupRepeaters(config: IJKLLPlayerConfig) {
        if let repeater = self.metaSyncRepeater {
            repeater.reset(.seconds(config.metaSyncTimeInterval), restart: true)
        } else {
            self.metaSyncRepeater = Repeater.every(.seconds(config.metaSyncTimeInterval), { [weak self] (repeater) in
                self?.onMetaSyncRepeater()
            })
        }
        
        if let repeater = self.maintenanceRepeater {
            repeater.reset(.seconds(config.maintenanceTimeInterval), restart: true)
        } else {
            self.maintenanceRepeater = Repeater.every(.seconds(config.maintenanceTimeInterval), { [weak self] (repeater) in
                self?.onMaintenanceRepeater()
            })
        }
        
        if let repeater = self.chunkLoadCheckRepeater {
            repeater.reset(.seconds(config.chunkLoadCheckTimeInterval), restart: true)
        } else {
            self.chunkLoadCheckRepeater = Repeater.every(.seconds(config.chunkLoadCheckTimeInterval), { [weak self] (repeater) in
                self?.onChunkLoadCheckRepeater()
            })
        }
        
        if let repeater = self.statsUpdateRepeater {
            repeater.reset(.seconds(config.statsUpdateTimeInterval), restart: true)
        } else {
            self.statsUpdateRepeater = Repeater.every(.seconds(config.statsUpdateTimeInterval), { [weak self] (repeater) in
                self?.onStatsUpdateRepeater()
            })
        }
        //self.metaSyncRepeater?.fire()
    }
    // Replaces ijk player source URL
    // Normally ijk player should be recreated, but for lowlat functionality source replacement is much faster
    private func swapSourceURL(_ url: URL) {
        
    }
    
    private func getNewestMeta(newMeta: IJKLLMeta) -> IJKLLMeta {
        if let oldMeta = self.meta {
            // If one meta fetch comes late, the new is the old, need to discard on that case
            return oldMeta <= newMeta ? newMeta : oldMeta
        } else {
            // no stored meta, just return new meta
            return newMeta
        }
    }
    
    private func makeMetaRequestURL(state: PlaylistState, config: IJKLLPlayerConfig) -> URL? {
        guard let playlistId = state.playlistId else { return nil }
        let template = config.metaURLTemplate
        let base = config.metaURLBase
        let t1 = template.replacingOccurrences(of: "{base_url}", with: base)
        let t2 = t1.replacingOccurrences(of: "{name}", with: playlistId)
        return URL(string: t2)
        //guard let url = URL(string: t2) else { return nil }
        //return try? URLRequest(url: url, method: .post)
    }
    
    private func registerPlayerNotificationObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(loadStateDidChange(notification:)),
                                               name: .IJKMPMoviePlayerLoadStateDidChange,
                                               object: self.internalPlayer)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(moviePlayBackDidFinish(notification:)),
                                               name: .IJKMPMoviePlayerPlaybackDidFinish,
                                               object: self.internalPlayer)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(moviePlayBackStateDidChange(notification:)),
                                               name: .IJKMPMoviePlayerPlaybackStateDidChange,
                                               object: self.internalPlayer)
    }
    
    private func removePlayerNotificationObservers() {
        NotificationCenter.default.removeObserver(self, name: .IJKMPMoviePlayerLoadStateDidChange, object: self.internalPlayer)
        NotificationCenter.default.removeObserver(self, name: .IJKMPMoviePlayerPlaybackDidFinish, object: self.internalPlayer)
        NotificationCenter.default.removeObserver(self, name: .IJKMPMoviePlayerPlaybackStateDidChange, object: self.internalPlayer)
    }
}

extension IJKLLPlayer {
    @objc func loadStateDidChange(notification: NSNotification) {
        if let loadState = self.internalPlayer?.loadState {
            switch loadState {
            case .playthroughOK:
                IJKLLLog.player("loadStateDidChange: playthroughOK");
            case .stalled:
                IJKLLLog.player("loadStateDidChange: stalled");
            case .playable:
                IJKLLLog.player("loadStateDidChange: playable");
            default:
                IJKLLLog.player("loadStateDidChange: unknown \(loadState)");
            }
        }
    }
    
    @objc func moviePlayBackDidFinish(notification: NSNotification) {
        if let reasonKey = notification.userInfo?[IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey] as? Int,
            let reason = IJKMPMovieFinishReason(rawValue: reasonKey) {
            switch reason {
            case IJKMPMovieFinishReason.playbackEnded:
                IJKLLLog.player("playbackStateDidChange: IJKMPMovieFinishReasonPlaybackEnded: \(reason)")
            case IJKMPMovieFinishReason.userExited:
                IJKLLLog.player("playbackStateDidChange: IJKMPMovieFinishReasonUserExited: \(reason)");
            case IJKMPMovieFinishReason.playbackError:
                IJKLLLog.player("playbackStateDidChange: IJKMPMovieFinishReasonPlaybackError: \(reason)");
            default:
                IJKLLLog.player("playbackPlayBackDidFinish: ???: \(reason)");
            }
        }
    }
    
    @objc func moviePlayBackStateDidChange(notification: NSNotification) {
        if let playbackState = self.internalPlayer?.playbackState {
            switch playbackState {
            case .stopped:
                IJKLLLog.player("IJKMPMoviePlayBackStateDidChange: stopped");
            case .playing:
                IJKLLLog.player("IJKMPMoviePlayBackStateDidChange: playing");
            case .paused:
                IJKLLLog.player("IJKMPMoviePlayBackStateDidChange: paused");
            case .interrupted:
                IJKLLLog.player("IJKMPMoviePlayBackStateDidChange: interrupted");
            case .seekingForward:
                IJKLLLog.player("IJKMPMoviePlayBackStateDidChange: seekingForward");
            case .seekingBackward:
                IJKLLLog.player("IJKMPMoviePlayBackStateDidChange: seekingBackward");
            default:
                IJKLLLog.player("IJKMPMoviePlayBackStateDidChange: unknown \(playbackState)");
            }
        }
    }
}

// update to chunk server
extension IJKLLPlayer: IJKLLChunkLoaderDelegate {
    public func taskReceiveData(key: String) {
        //chunkServer?.hasNewData(key: key)
        chunkServer?.hasNewData(key)
    }
    
    public func taskComplete(key: String) {
        //chunkServer?.closeDataConnection(key: key)
        chunkServer?.endDataTransmission(key)
    }
    
    public func taskCompleteWithError(key: String, error: Error) {
        //chunkServer?.closeDataConnection(key: key)
        chunkServer?.endDataTransmission(key)
    }
}

extension IJKLLPlayer: DVGChunkServerDelegate {
    public func requestData(_ key: String) -> Data? {
        if let entry = try? IJKLLChunkCache.shared.syncStorage.entry(forKey: key) {
            let rawData = entry.object
            return rawData
        } else {
            IJKLLLog.player("entry doesn't exist")
        }
        return nil
    }
    
    public func requestData(_ key: String, dataSent offset: Int) -> Data? {
        if let entry = try? IJKLLChunkCache.shared.syncStorage.entry(forKey: key) {
            let rawData = entry.object
            if rawData.count > offset {
                let range = NSMakeRange(entry.dataSent, rawData.count - entry.dataSent)
                if let r = Range(range) {
                    IJKLLLog.player("data in store \(rawData.count) dataSent \(offset), start send")
                    let data = rawData.subdata(in: r)
                    return data
                }
            } else {
                IJKLLLog.player("entry exist but no new data, existed data \(rawData.count), sent data \(offset)")
            }
        } else {
            IJKLLLog.player("entry doesn't exist")
        }
        return nil
    }
    
    public func unixServerReady() {
        guard let streamId = self.state.playlistState.playlistId else { return }
        IJKLLLog.player("unixServerReady setupIJKPlayer \(streamId)")
        setupIJKPlayer(streamId)
    }
    
    
}

extension IJKLLPlayer: IJKLLPlaylistDelegate {
    public func playlistRunFasterThanMeta(_ meta: IJKLLMeta) {
        IJKLLLog.player("calibrateTipIfNeeded meta seq \(meta.sequence)")
        chunkLoader?.calibrateTipIfNeeded(meta)
    }
}

//extension IJKLLPlayer: IJKLLChunkServerDelegate {
//    func unixServerReady() {
//        guard let streamId = self.state.playlistState.playlistId else { return }
//        IJKLLLog.player("unixServerReady setupIJKPlayer \(streamId)")
//        setupIJKPlayer(streamId)
//    }
//}

extension IJKLLPlayer {
    enum PlaylistState {
        case none
        case preparing(playlistId: String) // loading IJKLLPlayer resource
        case loading(playlistId: String) // IJKPlayer loading
        case playing(playlistId: String)
        case stalled(playlistId: String, since: Double)
        case paused(playlistId: String, since: Double)
        case stopped(playlistId: String)
        case finished(playlistId: String)
        
        var playlistId: String? {
            switch self {
            case .none:
                return nil
            case let .preparing(playlistId: p):
                return p
            case let .loading(playlistId: p):
                return p
            case let .playing(playlistId: p):
                return p
            case let .stalled(playlistId: p, since: _):
                return p
            case let .paused(playlistId: p,  since: _):
                return p
            case let .stopped(playlistId: p):
                return p
            case let .finished(playlistId: p):
                return p
            }
        }
        
        // onMaintenanceRepeater will check when playlist in these state
        var realtimable: Bool {
            switch self {
            case .playing(playlistId: _):
                return true
            case .loading(playlistId: _):
                return true
            case .stalled(playlistId: _, since: _):
                return true
            default:
                return false
            }
        }
        
        var isPreparing: Bool {
            switch self {
            case .preparing(playlistId: _):
                return true
            default:
                return false
            }
        }
    }
    
    public struct State {
        var playlistState: PlaylistState = .none
        public static var `default` = State()
    }
    
    struct Matrix {
        var stallStartTimestamp: Double = -1
        var chunkDuration = 2.0
    }
}
