//
//  IJKLLMeta.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/17/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public struct IJKLLMeta: Codable, Comparable {
    var sequence: Int
    var serverTS: Int
    var firstWriteTS: Int
    var lastWriteTS: Int
    var meta: String
    var chunkMeta: String
    
    public var requestTimeline: Timeline?
    
    public init(sequence: Int, serverTS: Int, firstWriteTS: Int, lastWriteTS: Int, meta: String, chunkMeta: String) {
        self.sequence = sequence
        self.serverTS = serverTS
        self.firstWriteTS = firstWriteTS
        self.lastWriteTS = lastWriteTS
        self.meta = meta
        self.chunkMeta = chunkMeta
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sequenceString = try container.decode(String.self, forKey: .sequence)
        let sequence = Int(sequenceString)!
        
//        let serverTSString = try container.decode(String.self, forKey: .serverTS)
//        let serverTS = Int(serverTSString)!
        let serverTS = try container.decode(Int.self, forKey: .serverTS)
        
        let lastWriteTSString = try container.decode(String.self, forKey: .lastWriteTS)
        let lastWriteTS = Int(lastWriteTSString)!
        
        let firstWriteTSString = try container.decode(String.self, forKey: .firstWriteTS)
        let firstWriteTS = Int(firstWriteTSString)!
        
        let meta = try container.decode(String.self, forKey: .meta)
        
        let chunkMeta = try container.decode(String.self, forKey: .chunkMeta)
        
        self.init(sequence: sequence, serverTS: serverTS, firstWriteTS: firstWriteTS, lastWriteTS: lastWriteTS, meta: meta, chunkMeta: chunkMeta)
    }
    
    enum CodingKeys: String, CodingKey {
        case sequence = "chunk"
        case serverTS = "serverts"
        case lastWriteTS = "lastopts"
        case firstWriteTS = "chunkts"
        case meta = "meta"
        case chunkMeta = "chunkmeta"
    }
    
    // For last chunk
    var estSecOnServer: Double {
        let first = Double(firstWriteTS) / 1000.0
        let last = Double(lastWriteTS) / 1000.0
        return last - first
    }
    
    // Tip PTS when the request was made
    var estPTSOnServerTip: Double? {
        guard let startPTS = chunkStartPTS else { return nil }
        return startPTS + estSecOnServer
    }
    
    // == curStamp-self.hlsRTStreamTipPtsStamp
    var timeElapsedSinceLastRequest: Double? {
        guard let tl = requestTimeline else { return nil }
        let current = Date().timeIntervalSinceReferenceDate
        return current - tl.requestStartTime - tl.latency/2.0
    }
    
    var estCurrentOnTipPTS: Double? {
        guard let tipPTS = estPTSOnServerTip, let timeElapsed = timeElapsedSinceLastRequest else { return nil }
        return tipPTS + timeElapsed
    }
    
    var streamChunkDuration: Int? {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.meta, key: "dur") else { return nil }
        return Int(stringValue)
    }
    
    var streamFPS: Int? {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.meta, key: "fps") else { return nil }
        return Int(stringValue)
    }
    
    var streamFinished: Bool {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.meta, key: "fin") else { return false }
        guard let fin = Int(stringValue) else { return false }
        return fin > 0 ? true : false
    }
    
    var streamFinishedPTS: Double? {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.meta, key: "pts") else { return nil }
        return Double(stringValue)
    }
    
    var chunkStartPTS: Double? {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.chunkMeta, key: "pts") else { return nil }
        return Double(stringValue)
    }
    
    var chunkUploadDelay: Double? {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.chunkMeta, key: "udl") else { return nil }
        return Double(stringValue)
    }
    
    static func getStringValue(source: String, key: String) -> String? {
        let dict = IJKLLMeta.parseString2Dict(source)
        guard let stringValue = dict?[key] else { return nil }
        return stringValue
    }
    
    static func parseString2Dict(_ text: String) -> Dictionary<String, String>? {
        var dict: Dictionary<String, String> = [:]
        let arr = text.components(separatedBy: ",")
        guard !arr.isEmpty, arr.count % 2 == 0 else { return nil }
        for (index, value) in arr.enumerated() {
            if index % 2 == 1 { continue }
            dict[value] = arr[index + 1]
        }
        return dict
    }
    
    public static func < (lhs: IJKLLMeta, rhs: IJKLLMeta) -> Bool {
        if lhs.sequence == rhs.sequence {
            return lhs.lastWriteTS < rhs.lastWriteTS
        } else {
            return lhs.sequence < rhs.sequence
        }
    }
    
    public static func == (lhs: IJKLLMeta, rhs: IJKLLMeta) -> Bool {
        if lhs.sequence == rhs.sequence {
            return lhs.lastWriteTS == rhs.lastWriteTS
        } else {
            return false
        }
    }
}
