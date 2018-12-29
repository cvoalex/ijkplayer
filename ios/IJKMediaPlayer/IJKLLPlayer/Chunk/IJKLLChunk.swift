//
//  IJKLLChunk.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/13/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public struct IJKLLChunk {
    let urlString: String
    let fileName: String
    
    let streamId: String
    let sequence: Int
    
    init?(_ request: URLRequest) {
        guard let url = request.url else { return nil }
        guard let streamId = url.param("playlist"), let chunkSeq = url.param("chunk") else { return nil }
        self.fileName = url.param("chunk") ?? "unknown"
        self.urlString = url.absoluteString
        self.streamId = streamId
        self.sequence = Int(chunkSeq)!
    }
    
    var requestKey: String {
        return "playlist_\(streamId)_chunk_\(sequence).ts"
    }
}

extension IJKLLChunk: Equatable {
    public static func == (lhs: IJKLLChunk, rhs: IJKLLChunk) -> Bool {
        return lhs.urlString == rhs.urlString
    }
}

extension IJKLLChunk: Comparable {
    public static func < (lhs: IJKLLChunk, rhs: IJKLLChunk) -> Bool {
        return lhs.urlString < rhs.urlString
    }
}

//extension IJKLLChunk {
//    enum LoadStatus {
//        case none
//        case requested
//        case receiveResponse
//        case loading
//        case done
//    }
//}
