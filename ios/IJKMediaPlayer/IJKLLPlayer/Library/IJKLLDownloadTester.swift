//
//  IJKLLDownloadTester.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/24/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public protocol IJKLLDownloadTesterDelegate: class {
    func onStatsUpdate(loader: IJKLLChunkLoader, timestamp: TimeInterval)
}

public class IJKLLDownloadTester {
    public weak var delegate: IJKLLDownloadTesterDelegate?
    
    private var metaSyncRepeater: Repeater?
    private var chunkLoadCheckRepeater: Repeater?
    private var reportStatsRepeater: Repeater?
    
    let streamId: String
    var playlist = IJKLLPlaylist()
    let loader = IJKLLChunkLoader(config: .realTime, watcher: IJKLLStrategy())
    private let networkSession = SessionManager(configuration: .ijkllMeta)
    private var meta: IJKLLMeta?
    
    public init(streamId: String) {
        self.streamId = streamId
        self.metaSyncRepeater = Repeater.every(.seconds(2), { [weak self] (repeater) in
            self?.onMetaSyncRepeater()
        })
        self.chunkLoadCheckRepeater = Repeater.every(.seconds(0.3), { [weak self] (repeater) in
            self?.onChunkLoadCheckRepeater()
        })
        self.reportStatsRepeater = Repeater.every(.seconds(0.5), { [weak self] (repeater) in
            self?.onReportStatsRepeater()
        })
        playlist.delegate = self
    }
    
    func onMetaSyncRepeater() {
        guard let url = makeMetaRequestURL() else { return }
        let _ = networkSession.request(url, method: .post).responseData { [weak self] (response) in
            let decoder = JSONDecoder()
            let responseString = String(data: response.data!, encoding: .utf8)
            print(responseString)
            let meta: Result<IJKLLMeta> = decoder.decodeResponse(from: response)
            switch meta {
            case let .success(llMeta):
                if let streamId = self?.streamId {
                    var timelinedMeta = llMeta
                    timelinedMeta.requestTimeline = response.timeline
                    self?.playlist.refresh(playlistId: streamId, meta: timelinedMeta)
                }
            case let .failure(error):
                IJKLLLog.downloadTester(error.localizedDescription)
            }
        }
    }
    
    func onChunkLoadCheckRepeater() {
        // Fire download if needed
        guard let nextPeekChunk = playlist.peek() else { return }
        guard loader.fetchCheck(nextPeekChunk) else { return }
        guard let nextChunk = playlist.pop() else { return }
        IJKLLLog.downloadTester("Ready to fetch chunk \(nextChunk.sequence)")
        loader.fetch(nextChunk)
    }
    
    func onReportStatsRepeater() {
        IJKLLLog.downloadTester("lastChunk \(loader.state.lastChunkStatus.description) tipChunk \(loader.state.tipChunkStatus.description)")
        self.delegate?.onStatsUpdate(loader: self.loader, timestamp: Date().timeIntervalSince1970)
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
    
    private func makeMetaRequestURL() -> URL? {
        let template = "http://ec2-18-213-85-167.compute-1.amazonaws.com:3000/getMeta?playlist=\(self.streamId)"
        return URL(string: template)
    }
}

extension IJKLLDownloadTester: IJKLLPlaylistDelegate {
    public func playlistRunFasterThanMeta(_ meta: IJKLLMeta) {
        IJKLLLog.downloadTester("calibrateTipIfNeeded meta seq \(meta.sequence)")
        loader.calibrateTipIfNeeded(meta)
    }
}
