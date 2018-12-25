//
//  IJKLLChunkLoader.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/11/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

protocol IJKLLChunkLoaderDelegate {
    func onDownload()
}

public struct IJKLLChunkLoaderConfig {
    var fetchTimeout: Double
    var resourceTimeout: Double
    var timerInterval: TimeInterval
    var prefetchThreshold: Double
    
    static let realTime = IJKLLChunkLoaderConfig(fetchTimeout: 2, resourceTimeout: 4, timerInterval: 1, prefetchThreshold: 1.6)
    static let concessive = IJKLLChunkLoaderConfig(fetchTimeout: 3, resourceTimeout: 6, timerInterval: 1, prefetchThreshold: 1.6)
}

public enum IJKLLChunkLoadStatus: Equatable {
    case none
    case requested(chunk: IJKLLChunk, timestamp: TimeInterval)
    case receiveResponse(chunk: IJKLLChunk, timestamp: TimeInterval)
    case beginDataTransmit(chunk: IJKLLChunk, timestamp: TimeInterval)
    case done(chunk: IJKLLChunk, timestamp: TimeInterval)
    case error(chunk: IJKLLChunk, error: Error, timestamp: TimeInterval)
    
    var description: String {
        switch self {
        case .none:
            return "none"
        case let .requested(savedChunk, _):
            return "requested \(savedChunk.fileName)"
        case let .receiveResponse(savedChunk, _):
            return "receiveResponse \(savedChunk.fileName)"
        case let .beginDataTransmit(savedChunk, _):
            return "beginDataTransmit \(savedChunk.fileName)"
        case let .done(savedChunk, _):
            return "done \(savedChunk.fileName)"
        case let .error(savedChunk, _, _):
            return "error \(savedChunk.fileName)"
        }
    }
    
    var loadSequence: Int {
        switch self {
        case .none:
            return 0
        case .requested(_, _):
            return 1
        case .receiveResponse(_, _):
            return 2
        case .beginDataTransmit(_, _):
            return 3
        case .done(_, _):
            return 4
        case .error(_, _, _):
            return 5
        }
    }
    
    var chunk: IJKLLChunk? {
        switch self {
        case .none:
            return nil
        case let .requested(savedChunk, _):
            return savedChunk
        case let .receiveResponse(savedChunk, _):
            return savedChunk
        case let .beginDataTransmit(savedChunk, _):
            return savedChunk
        case let .done(savedChunk, _):
            return savedChunk
        case let .error(savedChunk, _, _):
            return savedChunk
        }
    }
    
    var timestamp: TimeInterval? {
        switch self {
        case .none:
            return nil
        case let .requested(_, ts):
            return ts
        case let .receiveResponse(_, ts):
            return ts
        case let .beginDataTransmit(_, ts):
            return ts
        case let .done(_, ts):
            return ts
        case let .error(_, _, ts):
            return ts
        }
    }
    
    var isRemovable: Bool {
        switch self {
        case .none:
            return true
        case .requested(_, _):
            return false
        case .receiveResponse(_, _):
            return false
        case .beginDataTransmit(_, _):
            return false
        case .done(_, _):
            return true
        case .error(_, _, _):
            return true
        }
    }
    
    func chunkEqual(_ chunk: IJKLLChunk) -> Bool {
        switch self {
        case .none:
            return false
        case let .requested(savedChunk, _):
            return chunk == savedChunk
        case let .receiveResponse(savedChunk, _):
            return chunk == savedChunk
        case let .beginDataTransmit(savedChunk, _):
            return chunk == savedChunk
        case let .done(savedChunk, _):
            return chunk == savedChunk
        case let .error(savedChunk, _, _):
            return chunk == savedChunk
        }
    }
    
    public static func ==(lhs: IJKLLChunkLoadStatus, rhs: IJKLLChunkLoadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.none,.none):
            return true
        case (let .requested(c1, _), let .requested(c2, _)):
            return c1 == c2
        case (let .receiveResponse(c1, _), let .receiveResponse(c2, _)):
            return c1 == c2
        case (let .beginDataTransmit(c1, _), let .beginDataTransmit(c2, _)):
            return c1 == c2
        case (let .done(c1, _), let .done(c2, _)):
            return c1 == c2
        case (let .error(c1, _, _), let .error(c2, _, _)):
            return c1 == c2
        default:
            return false
        }
    }
}

public class IJKLLChunkLoader {
//    static let shared = IJKLLChunkLoader()
    
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
    }
    
    public func taskReceiveData(request: URLRequest, data: Data) {
        updateDataBytes(data.count)
    }
    
    public func taskComplete(request: URLRequest) {
        guard let chunk = IJKLLChunk(request) else { return }
        let ts = Date().timeIntervalSince1970
        let status = IJKLLChunkLoadStatus.done(chunk: chunk, timestamp: ts)
        updateLoadStatus(chunk: chunk, newStatus: status)
    }
    
    public func taskCompleteWithError(request: URLRequest, error: Error) {
        guard let chunk = IJKLLChunk(request) else { return }
        let ts = Date().timeIntervalSince1970
        let status = IJKLLChunkLoadStatus.error(chunk: chunk, error: error, timestamp: ts)
        updateLoadStatus(chunk: chunk, newStatus: status)
        
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
