//
//  IJKLLPlaylist.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/18/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public struct IJKLLPlaylist {
    static let chunkLimit = 3
    let header: [String] = ["#EXTM3U", "#EXT-X-VERSION:3"]
    var chunks = [Chunk]()
    private var lastMeta: IJKLLMeta?
    
    public init() {}
    
    public mutating func pop() -> Chunk? {
        guard let meta = lastMeta else { return nil }
        guard !meta.streamFinished else { return nil }
        let nextChunk = chunks.first
        if let lastChunk = chunks.last {
            chunks.append(lastChunk.next)
            chunks.removeFirst()
        }
        let chunkNumArr = chunks.map { $0.sequence }
        IJKLLLog.playlist("after pop, # in list \(chunks.count) \(chunkNumArr)")
        return nextChunk
    }
    
    public func peek() -> Chunk? {
        guard let meta = lastMeta else { return nil }
        guard !meta.streamFinished else { return nil }
        return chunks.first
    }
    
    public mutating func refresh(playlistId: String, meta: IJKLLMeta) {
        if self.lastMeta == nil {
            self.lastMeta = meta
        }
        guard let lastMeta = self.lastMeta, meta > lastMeta else { return }
        self.lastMeta = meta
        let lastSeq = meta.sequence
        var newChunks = [Chunk]()
        for i in 0..<IJKLLPlaylist.chunkLimit {
            let chunk = Chunk(playlistId: playlistId, sequence: lastSeq + i)
            newChunks.append(chunk)
        }
        self.chunks = newChunks
//        if let firstChunk = self.chunks.first, let metaFirstChunk = newChunks.first {
//            if metaFirstChunk.sequence > firstChunk.sequence {
//                IJKLLLog.playlist("refresh tip seq \(meta.sequence)")
//                self.chunks = newChunks
//            }
//        } else {
//            IJKLLLog.playlist("refresh error no first")
//            self.chunks = newChunks
//        }
    }
    
    public func write() {
        guard let lastMeta = self.lastMeta, let chunkDuration = lastMeta.streamChunkDuration else { return }
        guard let playlistId = self.chunks.first?.playlistId else { return }
        let chunkStringArr = chunks.map { "#EXTINF:\(chunkDuration),\n\($0.llhls)" }
        var content = header
        content.append("#EXT-X-TARGETDURATION:\(chunkDuration)")
        content.append("")
        content.append(contentsOf: chunkStringArr)
        if lastMeta.streamFinished {
            content.append("")
            content.append("#EXT-X-ENDLIST")
        }
        let doc = content.joined(separator: "\n")
        let path = NSTemporaryDirectory()
        let fileName = "hls_\(playlistId).m3u8"
        let tempUrl = URL(fileURLWithPath: path, isDirectory: true)
        let fileUrl = tempUrl.appendingPathComponent(fileName)
        do {
            try doc.write(to: fileUrl, atomically: true, encoding: .utf8)
        } catch {
            IJKLLLog.playlist("write error \(error.localizedDescription)")
        }
    }
    
    private mutating func getNewestMeta(newMeta: IJKLLMeta) -> IJKLLMeta {
        if let oldMeta = self.lastMeta {
            // If one meta fetch comes late, the new is the old, need to discard on that case
            return oldMeta <= newMeta ? newMeta : oldMeta
        } else {
            // no stored meta, just return new meta
            self.lastMeta = newMeta
            return newMeta
        }
    }
}

extension IJKLLPlaylist {
    public struct Chunk {
        let playlistId: String
        let sequence: Int
        
        var llhls: String {
            return "llhls://d1d7bq76ey2psd.cloudfront.net/getChunk?playlist=\(playlistId)&chunk=\(sequence)"
        }
        
        var urlString: String {
            return "http://d1d7bq76ey2psd.cloudfront.net/getChunk?playlist=\(playlistId)&chunk=\(sequence)"
        }
        
        var url: URL? {
            return URL(string: urlString)
        }
        
        var next: Chunk {
            return Chunk(playlistId: playlistId, sequence: sequence + 1)
        }
    }
}
