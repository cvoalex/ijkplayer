//
//  IJKLLChunkLoader.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/11/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

protocol IJKLLChunkLoaderDelegate {
    func onDownload()
}

struct IJKLLChunkLoaderConfig {
    var fetchTimeout: Double
    var timerInterval: TimeInterval
    
    static let realTime = IJKLLChunkLoaderConfig(fetchTimeout: 3, timerInterval: 1)
    static let concessive = IJKLLChunkLoaderConfig(fetchTimeout: 4, timerInterval: 1)
}

enum IJKLLChunkStatus {
    case none
    case loading
    case done
}

struct IJKLLChunkLoaderStatus {
    var currentChunkStatus: IJKLLChunkStatus = .none
    var prefetchChunkStatus: IJKLLChunkStatus = .none
}

class IJKLLChunkLoader {
//    static let shared = IJKLLChunkLoader()
    
    let configuration: IJKLLChunkLoaderConfig
    let watcher: IJKLLStrategy
    let sessionManager: IJKLLSessionManager
    var timer: Timer?
    
    var loaderStatus = IJKLLChunkLoaderStatus()
    
    init(config: IJKLLChunkLoaderConfig, watcher: IJKLLStrategy) {
        self.configuration = config
        self.watcher = watcher
        self.sessionManager = IJKLLSessionManager()
        //let delegate: SessionDelegate = sessionManager.delegate
    }
    
    func start() {
        self.timer = Timer.scheduledTimer(timeInterval: self.configuration.timerInterval, target: self, selector: #selector(onTimer), userInfo: nil, repeats: true)
    }
    
    func stop() {
        self.timer?.invalidate()
    }
    
    @objc func onTimer() {
        // pass loaderStatus, sessionManager to watcher, get urlSession?
        
        // Watcher may update sessionManager, but sessionManager.session always return proper session
        let urlSession = sessionManager.session
        //let request = URLRequest(url: <#T##URL#>, cachePolicy: <#T##URLRequest.CachePolicy#>, timeoutInterval: <#T##TimeInterval#>)
    }
}
