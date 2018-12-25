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
    
    init?(_ request: URLRequest) {
        guard let url = request.url else { return nil }
        self.fileName = url.param("chunk") ?? "unknown"
        self.urlString = url.absoluteString
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
