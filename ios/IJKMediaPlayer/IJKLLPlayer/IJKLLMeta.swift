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
    var serverTS: Double
    var firstWriteTS: Double
    var lastWriteTS: Double
    var meta: String
    
    public var requestTimeline: Timeline?
    
    public init(sequence: Int, serverTS: Double, firstWriteTS: Double, lastWriteTS: Double, meta: String) {
        self.sequence = sequence
        self.serverTS = serverTS
        self.firstWriteTS = firstWriteTS
        self.lastWriteTS = lastWriteTS
        self.meta = meta
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sequenceString = try container.decode(String.self, forKey: .sequence)
        let sequence = Int(sequenceString)!
        
//        let serverTSString = try container.decode(String.self, forKey: .serverTS)
//        let serverTS = Int(serverTSString)!
        let serverTSInt = try container.decode(Int.self, forKey: .serverTS)
        let serverTS = Double(serverTSInt) / 1000.0
        
        let lastWriteTSString = try container.decode(String.self, forKey: .lastWriteTS)
        let lastWriteTSInt = Int(lastWriteTSString)!
        let lastWriteTS = Double(lastWriteTSInt) / 1000.0
        
        let firstWriteTSString = try container.decode(String.self, forKey: .firstWriteTS)
        let firstWriteTSInt = Int(firstWriteTSString)!
        let firstWriteTS = Double(firstWriteTSInt) / 1000.0
        
        let meta = try container.decode(String.self, forKey: .meta)
        
        self.init(sequence: sequence, serverTS: serverTS, firstWriteTS: firstWriteTS, lastWriteTS: lastWriteTS, meta: meta)
    }
    
    enum CodingKeys: String, CodingKey {
        case sequence = "chunk"
        case serverTS = "serverts"
        case lastWriteTS = "lastopts"
        case firstWriteTS = "chunkts"
        case meta = "meta"
    }
    
    // For last chunk
    var estSecOnServer: Double {
        return lastWriteTS - firstWriteTS
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
    
    var serverTimeElapsed: Double {
        let current = Date().timeIntervalSince1970
        return current - serverTS
    }
    
    var isLate: Bool {
        return serverTimeElapsed > 2.6
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
        guard let stringValue = IJKLLMeta.getStringValue(source: self.meta, key: "ch_pts") else { return nil }
        return Double(stringValue)
    }
    
    var chunkMuxTS: Double? {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.meta, key: "ch_ptsts") else { return nil }
        return Double(stringValue)
    }
    
    var chunkUploadDelay: Double? {
        guard let stringValue = IJKLLMeta.getStringValue(source: self.meta, key: "ch_udl") else { return nil }
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
        return lhs.sequence < rhs.sequence
//        if lhs.sequence == rhs.sequence {
//            return lhs.lastWriteTS < rhs.lastWriteTS
//        } else {
//            return lhs.sequence < rhs.sequence
//        }
    }
    
    public static func == (lhs: IJKLLMeta, rhs: IJKLLMeta) -> Bool {
        return lhs.sequence == rhs.sequence
//        if lhs.sequence == rhs.sequence {
//            return lhs.lastWriteTS == rhs.lastWriteTS
//        } else {
//            return false
//        }
    }
}
