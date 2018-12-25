//
//  Logs.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/13/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

let log = SwiftyBeaver.self

class IJKLLLog {
    static let shared = IJKLLLog()
    private init() {
        // add log destinations. at least one is needed!
        let console = ConsoleDestination()  // log to Xcode Console
        // add the destinations to SwiftyBeaver
        log.addDestination(console)
    }
    
    static func player(_ msg: String) {
        print("[LLPlayer]: \(msg)")
    }
    
    static func chunkServer(_ msg: String) {
        print("[ChunkServer]: \(msg)")
    }
    
    static func chunkLoader(_ msg: String) {
        print("[ChunkLoader]: \(msg)")
    }
    
    static func playlist(_ msg: String) {
        print("[Playlist]: \(msg)")
    }
    
    static func sessionManager(_ msg: String) {
        print("[SessionManager]: \(msg)")
    }
    
    static func downloadTester(_ msg: String) {
        print("[DownloadTester]: \(msg)")
    }
}


