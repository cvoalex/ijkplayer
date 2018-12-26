//
//  IJKLLChunkSession.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/13/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

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
