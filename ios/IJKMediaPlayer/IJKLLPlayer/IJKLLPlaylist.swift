//
//  IJKLLPlaylist.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/18/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public protocol IJKLLPlaylistDelegate: class {
    func playlistRunFasterThanMeta(_ meta: IJKLLMeta, backOff: TimeInterval)
}

public class IJKLLPlaylist {
    public weak var delegate: IJKLLPlaylistDelegate?
    static let chunkLimit = 300
    let header: [String] = ["#EXTM3U", "#EXT-X-VERSION:3"]
    var lastMeta: IJKLLMeta?
    let serialQueue = DispatchQueue(label: "me.mobcast.playlist.serialQueue")
    var refreshCount = 0
    
    var chunks = [IJKLLChunk]()
    //var currentPosition = 0
    
    var nextPosition = 0
    var lastPosition: Int? {
        let last = nextPosition - 1
        guard last >= 0 else { return nil }
        return last
    }
    var tipPosition: Int? {
        guard let tipSeq = lastMeta?.sequence else { return nil }
        return chunks.firstIndex { (chunk) -> Bool in
            return chunk.sequence == tipSeq
        }
    }
    
//    var windowChunks: [Chunk] {
//        guard let tipPosition = self.tipPosition, let lastMeta = self.lastMeta else { return [] }
//        if tipPosition >= currentPosition {
//            // normal case, tip is newer or euqal the currect position
//            let window = chunks[currentPosition...tipPosition]
//            return Array(window)
//        } else {
//            // specail cases
//            let timeElapsed = Date().timeIntervalSince1970 - lastMeta.serverTS
//            // Should keep a meta list to obtain more info of streamer
//            let isProblematicStreamer = lastMeta.chunkUploadDelay! > 1
//            if timeElapsed > 3 && !isProblematicStreamer {
//                // 1. having low freqency meta timer
//                // 2. meta timeout/delay
//                // need to make a better est tip by using last meta
//                let window = chunks[currentPosition...(currentPosition+1)]
//                return Array(window)
//            } else {
//                // 3. upload timeout/delay
//                IJKLLLog.playlist("streamer issue request delay \(timeElapsed), streamer delay \(lastMeta.chunkUploadDelay!)")
//                return []
//            }
//
//        }
//    }
    
    var needRefresh: Bool {
        guard let meta = lastMeta else { return false }
        guard !meta.streamFinished else { return false }
        guard let lastChunk = chunks.last else { return false }
        let distanceToListEnd = lastChunk.sequence - meta.sequence
        return distanceToListEnd <= 3
    }
    
    public init() {}
    
    public func peek() -> IJKLLChunk? {
        guard let meta = lastMeta else { return nil }
        guard !meta.streamFinished else { return nil }
        guard nextPosition < chunks.count else { return nil }
        return chunks[nextPosition]
    }
    
    public func top() -> IJKLLChunk? {
        guard let meta = lastMeta else { return nil }
        guard !meta.streamFinished else { return nil }
        guard nextPosition < chunks.count else { return nil }
        let top = chunks[nextPosition]
        nextPosition += 1
        return top
    }
    
    public func update(meta: IJKLLMeta, streamId: String) {
        guard let lastMeta = self.lastMeta else {
            initRefresh(streamId: streamId, meta: meta)
            return
        }
        //metaUpdateCheck(oldMeta: lastMeta, newMeta: meta)
        // Update meta
        if meta > lastMeta {
            self.lastMeta = meta
        }
        // Need to refresh the playlist
        guard needRefresh else { return }
        let lastSeq = self.lastMeta!.sequence
        // avoid duplicate tip from windowChunks
//        var newSet = Set<Chunk>(windowChunks)
//        for i in 0..<IJKLLPlaylist.chunkLimit {
//            let chunk = Chunk(playlistId: streamId, sequence: lastSeq + i)
//            newSet.insert(chunk)
//        }
//        let newChunks = Array(newSet).sorted { (c1, c2) -> Bool in
//            return c1.sequence < c2.sequence
//        }
        var newChunks = [IJKLLChunk]()
        for i in 0..<IJKLLPlaylist.chunkLimit {
            let chunk = IJKLLChunk(streamId: streamId, sequence: lastSeq + i)
            newChunks.append(chunk)
        }
        
        let oldChunkArr = self.chunks.map { $0.sequence }
        let newChunkArr = newChunks.map { $0.sequence }
        IJKLLLog.playlist("refresh playlist, old [\(oldChunkArr.first ?? -1)...\(oldChunkArr.last ?? -1)] -> new [\(newChunkArr.first ?? -1)...\(newChunkArr.last ?? -1)]")
        self.chunks = newChunks
        refreshCount += 1
        write()
    }
    
    func initRefresh(streamId: String, meta: IJKLLMeta) {
        IJKLLLog.playlist("init refresh only once, tipChunk \(meta.sequence)")
        self.lastMeta = meta
        let lastSeq = meta.sequence
        var newChunks = [IJKLLChunk]()
        for i in 0..<IJKLLPlaylist.chunkLimit {
            let chunk = IJKLLChunk(streamId: streamId, sequence: lastSeq + i)
            newChunks.append(chunk)
        }
        self.chunks = newChunks
        write()
    }
    
    func metaUpdateCheck(oldMeta: IJKLLMeta, newMeta: IJKLLMeta) {
        let lastPosition = self.lastPosition ?? 0
        guard let oldTipPosition = getPosition(meta: oldMeta), let newTipPosition = getPosition(meta: newMeta) else {
            // position out of the chunks, shouldn't happen, need to add protect check, ignore for now
            IJKLLLog.playlist("position out of the chunks")
            return
        }
        guard newTipPosition >= oldTipPosition else {
            // new position come in wrong order, discarded
            IJKLLLog.playlist("new position come in wrong order, discarded")
            return
        }
        //let umpSistance = newTipPosition - oldTipPosition
        switch newTipPosition {
        case _ where newTipPosition == nextPosition:
            break // safe
        case _ where newTipPosition == lastPosition:
            // maybe too close to the tip
            let estRemainTime = Double(newMeta.streamChunkDuration ?? 0) - newMeta.estSecOnServer
            if estRemainTime < 0.3 {
                delegate?.playlistRunFasterThanMeta(newMeta, backOff: 0.3)
            } else {
                delegate?.playlistRunFasterThanMeta(newMeta, backOff: estRemainTime)
            }
        case _ where newTipPosition < lastPosition:
            // 1.meta delay
            // 2.streamer delay
            // 3.big timer interval
            //let offset = lastPosition - newTipPosition
            if newMeta.timeElapsedSinceLastRequest! < 2.5 {
                // meta is on time, playlist goes too fast
                // need to restart
                // should caused by streamer issue or prefetch shift
                IJKLLLog.playlist("should caused by streamer issue \(newMeta.chunkUploadDelay ?? -1) or prefetch shift")
            } else {
                // meta is late, guess if we need to restart/seek
                IJKLLLog.playlist("meta is late, guess if we need to restart/seek")
            }
        case _ where newTipPosition > nextPosition:
            let offset = newTipPosition - nextPosition
            switch offset {
            case 1...2: // seek
                IJKLLLog.playlist("newTipPosition \(newTipPosition) ahead of nextPosition \(nextPosition), seek")
            case 3...: // need to restart
                IJKLLLog.playlist("newTipPosition \(newTipPosition) way ahead of nextPosition \(nextPosition), restart")
            default:
                break
            }
        default:
            fatalError()
        }
        
    }
    
    public func write() {
        guard let lastMeta = self.lastMeta, let chunkDuration = lastMeta.streamChunkDuration else { return }
        guard chunks.count != 0 else { return }
        guard let playlistId = self.chunks.first?.streamId else { return }
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
            IJKLLLog.playlist("write [\(chunkArr.first ?? -1)...\(chunkArr.last ?? -1)] to \(fileUrl.absoluteString)")
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
    
    private func getPosition(meta: IJKLLMeta) -> Int? {
        let tipSeq = meta.sequence
        return chunks.firstIndex { (chunk) -> Bool in
            return chunk.sequence == tipSeq
        }
    }
}
