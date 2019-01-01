//
//  IJKLLPlaylist.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/18/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public protocol IJKLLPlaylistDelegate: class {
    func playlistRunFasterThanMeta(_ meta: IJKLLMeta)
}

public class IJKLLPlaylist {
    public weak var delegate: IJKLLPlaylistDelegate?
    static let chunkLimit = 3
    let header: [String] = ["#EXTM3U", "#EXT-X-VERSION:3"]
    var chunks = [Chunk]()
    private var lastMeta: IJKLLMeta?
    public let serialQueue = DispatchQueue(label: "me.mobcast.playlist.serialQueue")
    var refreshCount = 0
    
    public init() {}
    
    func popSync() -> Chunk? {
        var chunk: Chunk?
        serialQueue.sync {
            chunk = pop()
        }
        return chunk
    }
    
    func peekSync() -> Chunk? {
        var chunk: Chunk?
        serialQueue.sync {
            chunk = peek()
        }
        return chunk
    }
    
    func refreshSync(playlistId: String, meta: IJKLLMeta) {
        serialQueue.sync {
            refresh(playlistId: playlistId, meta: meta)
        }
    }
    
    public func pop() -> Chunk? {
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
    
    public func refresh(playlistId: String, meta: IJKLLMeta) {
        if self.lastMeta == nil {
            IJKLLLog.playlist("init refresh only once, tipChunk \(meta.sequence)")
            self.lastMeta = meta
            let lastSeq = meta.sequence
            var newChunks = [Chunk]()
            for i in 0..<IJKLLPlaylist.chunkLimit {
                let chunk = Chunk(playlistId: playlistId, sequence: lastSeq + i)
                newChunks.append(chunk)
            }
            self.chunks = newChunks
            return
        }
        guard let lastMeta = self.lastMeta, meta > lastMeta else { return }
        self.lastMeta = meta
        guard meta.sequence > self.chunks.first?.sequence ?? 0 else {
            // In this case, playlist run faster then server meta, need to re-calibrate
            delegate?.playlistRunFasterThanMeta(meta)
            return
        }
        guard meta.sequence > self.chunks.first?.sequence ?? 0 + 1 else { return }
        let lastSeq = meta.sequence
        var newChunks = [Chunk]()
        for i in 0..<IJKLLPlaylist.chunkLimit {
            let chunk = Chunk(playlistId: playlistId, sequence: lastSeq + i)
            newChunks.append(chunk)
        }
        let oldChunkArr = self.chunks.map { $0.sequence }
        let newChunkArr = newChunks.map { $0.sequence }
        IJKLLLog.playlist("refresh, old \(oldChunkArr) -> new \(newChunkArr)")
        self.chunks = newChunks
        refreshCount += 1
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
        guard chunks.count != 0 else { return }
        guard let playlistId = self.chunks.first?.playlistId else { return }
        let chunkStringArr = chunks.map { "#EXTINF:\(chunkDuration),\n\($0.llhls)" }
        var content = header
        content.insert("## LLHLS-Reload:\(self.refreshCount), chk:\(lastMeta.sequence)", at: 1)
        content.append("#EXT-X-TARGETDURATION:\(chunkDuration)")
        content.append("")
        content.append(contentsOf: chunkStringArr)
        if lastMeta.streamFinished {
            content.append("")
            content.append("#EXT-X-ENDLIST")
        }
        let doc = content.joined(separator: "\n")
        let fileUrl = IJKLLPlayer.getM3U8Url(playlistId)
        do {
            try doc.write(to: fileUrl, atomically: true, encoding: .utf8)
            let chunkArr = chunks.map { $0.sequence }
            IJKLLLog.playlist("write \(chunkArr) to \(fileUrl.absoluteString)")
        } catch {
            IJKLLLog.playlist("write error \(error.localizedDescription)")
        }
    }
    
    private func getNewestMeta(newMeta: IJKLLMeta) -> IJKLLMeta {
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
        
        var cachePath: String = {
            return NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        }()
        
        var llhls: String {
            return "llhls://\(cachePath)/playerloader?playlist_\(playlistId)_chunk_\(sequence).ts"
        }
        
        var urlString: String {
            return "http://d1d7bq76ey2psd.cloudfront.net/getChunk?playlist=\(playlistId)&chunk=\(sequence)"
        }
        
        var requestKey: String {
            return "playlist_\(playlistId)_chunk_\(sequence).ts"
        }
        
        var url: URL? {
            return URL(string: urlString)
        }
        
        var next: Chunk {
            return Chunk(playlistId: playlistId, sequence: sequence + 1)
        }
        
        init(playlistId: String, sequence: Int) {
            self.playlistId = playlistId
            self.sequence = sequence
        }
    }
}
