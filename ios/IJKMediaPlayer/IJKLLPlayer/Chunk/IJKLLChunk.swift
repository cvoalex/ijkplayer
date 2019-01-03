//
//  IJKLLChunk.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/13/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public struct IJKLLChunk {
    let streamId: String
    let sequence: Int
    
    init?(_ request: URLRequest) {
        guard let url = request.url else { return nil }
        guard let streamId = url.param("playlist"), let chunkSeq = url.param("chunk") else { return nil }
        self.streamId = streamId
        self.sequence = Int(chunkSeq)!
    }
    
    init(streamId: String, sequence: Int) {
        self.streamId = streamId
        self.sequence = sequence
    }
    
    var requestKey: String {
        return "playlist_\(streamId)_chunk_\(sequence).ts"
    }
    
    var cachePath: String = {
        return NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
    }()
    
    var llhls: String {
        return "llhls://\(cachePath)/playerloader?playlist_\(streamId)_chunk_\(sequence).ts"
    }
    
    var urlString: String {
        return "http://d1d7bq76ey2psd.cloudfront.net/getChunk?playlist=\(streamId)&chunk=\(sequence)"
    }
    
    var url: URL? {
        return URL(string: urlString)
    }
    
    var next: IJKLLChunk {
        return IJKLLChunk(streamId: streamId, sequence: sequence + 1)
    }
}

extension IJKLLChunk: Hashable {
    public var hashValue: Int {
        return streamId.hashValue ^ sequence.hashValue
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
