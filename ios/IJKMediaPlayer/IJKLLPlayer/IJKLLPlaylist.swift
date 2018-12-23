//
//  IJKLLPlaylist.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/18/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

struct IJKLLPlaylist {
    static let chunkLimit = 3
    let header: [String] = ["#EXTM3U", "#EXT-X-VERSION:3"]
    var chunks = [Chunk]()
    private var lastMeta: IJKLLMeta?
    
    mutating func pop() -> Chunk? {
        guard let meta = lastMeta else { return nil }
        guard !meta.streamFinished else { return nil }
        let nextChunk = chunks.first
        if let lastChunk = chunks.last {
            chunks.append(lastChunk.next)
            chunks.removeFirst()
        }
        IJKLLLog.playlist("after pop, # in list \(chunks.count)")
        return nextChunk
    }
    
    mutating func refresh(playlistId: String, meta: IJKLLMeta) {
        guard let lastMeta = self.lastMeta, meta > lastMeta else { return }
        self.lastMeta = meta
        let lastSeq = meta.sequence
        var newChunks = [Chunk]()
        for i in 0..<IJKLLPlaylist.chunkLimit {
            let chunk = Chunk(playlistId: playlistId, sequence: lastSeq + i)
            newChunks.append(chunk)
        }
        self.chunks = newChunks
    }
    
    func write() {
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
}

extension IJKLLPlaylist {
    struct Chunk {
        let playlistId: String
        let sequence: Int
        
        var llhls: String {
            return "llhls://d1d7bq76ey2psd.cloudfront.net/getChunk?playlist=\(playlistId)&chunk=\(sequence)"
        }
        
        var next: Chunk {
            return Chunk(playlistId: playlistId, sequence: sequence + 1)
        }
    }
}
