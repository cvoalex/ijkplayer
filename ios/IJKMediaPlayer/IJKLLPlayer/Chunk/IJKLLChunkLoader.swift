//
//  IJKLLChunkLoader.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/11/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public protocol IJKLLChunkLoaderDelegate: class {
    func taskReceiveData(key: String)
    func taskComplete(key: String)
    func taskCompleteWithError(key: String, error: Error)
}

public struct IJKLLChunkLoaderConfig {
    var fetchTimeout: Double
    var resourceTimeout: Double
    var timerInterval: TimeInterval
    var prefetchThreshold: Double
    
    static let realTime = IJKLLChunkLoaderConfig(fetchTimeout: 2, resourceTimeout: 4, timerInterval: 1, prefetchThreshold: 1.6)
    static let concessive = IJKLLChunkLoaderConfig(fetchTimeout: 3, resourceTimeout: 6, timerInterval: 1, prefetchThreshold: 1.6)
}

public class IJKLLChunkLoader {
//    static let shared = IJKLLChunkLoader()
    public weak var delegate: IJKLLChunkLoaderDelegate?
    let configuration: IJKLLChunkLoaderConfig
    let watcher: IJKLLStrategy
    let sessionManager: IJKLLSessionManager
    public let serialQueue = DispatchQueue(label: "me.mobcast.loader.state.serialQueue")
    
    public var state = State()
    
    public init(config: IJKLLChunkLoaderConfig, watcher: IJKLLStrategy) {
        self.configuration = config
        self.watcher = watcher
        self.sessionManager = IJKLLSessionManager()
        self.sessionManager.delegate = self
        //let delegate: SessionDelegate = sessionManager.delegate
    }
    
    public func fetchCheck(_ chunk: IJKLLPlaylist.Chunk) -> Bool {
        if self.state.tipChunkStatus.isRemovable {
            return true
        }
        if self.state.tipChunkStatus.chunk?.urlString == chunk.urlString {
            IJKLLLog.chunkLoader("fetchCheck tip chunk \(chunk.sequence) is fetching already, discard")
            return false
        }
        if let requestTS = self.state.tipChunkStartTime {
            let currentTS = Date().timeIntervalSince1970
            let delta = currentTS - requestTS
            return delta >= configuration.prefetchThreshold
        }
        return false
    }
    
    public func fetch(_ chunk: IJKLLPlaylist.Chunk) {
        // pass loaderStatus, sessionManager to watcher, get urlSession?
        // Watcher may update sessionManager, but sessionManager.session always return proper session
        guard let url = chunk.url else {
            IJKLLLog.chunkLoader("IJKLLPlaylist.Chunk url nil")
            return
        }
        let urlSession = sessionManager.session
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: configuration.fetchTimeout)
        let dataTask = urlSession?.dataTask(with: request)
        serialQueue.sync {
            self.state.lastChunkStatus = self.state.tipChunkStatus
            self.state.lastChunkStartTime = self.state.tipChunkStartTime
            if let llChunk = IJKLLChunk(request) {
                let time = Date().timeIntervalSince1970
                self.state.tipChunkStatus = .requested(chunk: llChunk, timestamp: time)
                self.state.tipChunkStartTime = time
            } else {
                self.state.tipChunkStatus = .none
                self.state.tipChunkStartTime = nil
            }
        }
        dataTask?.resume()
    }
    
    func calibrateTipIfNeeded(_ meta: IJKLLMeta) {
        serialQueue.sync {
            if self.state.tipChunkStatus.chunk?.sequence == meta.sequence, let time = self.state.tipChunkStartTime {
                self.state.tipChunkStartTime = time + 0.3
            }
        }
    }
}

extension IJKLLChunkLoader {
    public struct State {
        public var tipChunkStatus: IJKLLChunkLoadStatus = .none
        public var tipChunkStartTime: TimeInterval?
        public var lastChunkStatus: IJKLLChunkLoadStatus = .none
        public var lastChunkStartTime: TimeInterval?
        public var totalDataCount: Double = 0
    }
}

extension IJKLLChunkLoader: IJKLLSessionManagerDelegate {
    
    public func taskReceiveResponse(request: URLRequest) {
        guard let chunk = IJKLLChunk(request) else { return }
        let ts = Date().timeIntervalSince1970
        let status = IJKLLChunkLoadStatus.receiveResponse(chunk: chunk, timestamp: ts)
        updateLoadStatus(chunk: chunk, newStatus: status)
    }
    
    public func taskBeginReceiveData(request: URLRequest, data: Data) {
        guard let chunk = IJKLLChunk(request) else { return }
        let ts = Date().timeIntervalSince1970
        let status = IJKLLChunkLoadStatus.beginDataTransmit(chunk: chunk, timestamp: ts)
        updateLoadStatus(chunk: chunk, newStatus: status)
        updateDataBytes(data.count)
        delegate?.taskReceiveData(key: chunk.requestKey)
    }
    
    public func taskReceiveData(request: URLRequest, data: Data) {
        updateDataBytes(data.count)
        guard let chunk = IJKLLChunk(request) else { return }
        delegate?.taskReceiveData(key: chunk.requestKey)
    }
    
    public func taskComplete(request: URLRequest) {
        guard let chunk = IJKLLChunk(request) else { return }
        let ts = Date().timeIntervalSince1970
        let status = IJKLLChunkLoadStatus.done(chunk: chunk, timestamp: ts)
        updateLoadStatus(chunk: chunk, newStatus: status)
        IJKLLLog.chunkLoader("taskComplete \(chunk.requestKey)")
        delegate?.taskComplete(key: chunk.requestKey)
    }
    
    public func taskCompleteWithError(request: URLRequest, error: Error) {
        guard let chunk = IJKLLChunk(request) else { return }
        let ts = Date().timeIntervalSince1970
        let status = IJKLLChunkLoadStatus.error(chunk: chunk, error: error, timestamp: ts)
        updateLoadStatus(chunk: chunk, newStatus: status)
        IJKLLLog.chunkLoader("taskCompleteWithError \(chunk.requestKey)")
        delegate?.taskCompleteWithError(key: chunk.requestKey, error: error)
    }
    
    func updateLoadStatus(chunk: IJKLLChunk, newStatus: IJKLLChunkLoadStatus) {
        serialQueue.sync {
            let tipChunkStatus = self.state.tipChunkStatus
            let lastChunkStatus = self.state.lastChunkStatus
            if tipChunkStatus.chunkEqual(chunk) {
                if tipChunkStatus.loadSequence >= newStatus.loadSequence {
                    IJKLLLog.chunkLoader("try to overwrite in wrong order \(tipChunkStatus.loadSequence)>=\(newStatus.loadSequence)")
                }
                self.state.tipChunkStatus = newStatus
            } else if lastChunkStatus.chunkEqual(chunk) {
                if lastChunkStatus.loadSequence >= newStatus.loadSequence {
                    IJKLLLog.chunkLoader("try to overwrite in wrong order \(lastChunkStatus.loadSequence)>=\(newStatus.loadSequence)")
                }
                self.state.lastChunkStatus = newStatus
            } else {
                IJKLLLog.chunkLoader("try to update not record chunk \(chunk.fileName)")
            }
        }
    }
    
    func updateDataBytes(_ byteCount: Int) {
        serialQueue.sync {
            let mbCount = (Double(byteCount)/1024.0)/1024.0
            let count = self.state.totalDataCount
            self.state.totalDataCount = count + mbCount
        }
    }
}
