//
//  IJKLLSessionManager.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/12/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

class IJKLLSessionManager {
    var session: URLSession? {
        self.sessions = self.sessions.filter { !$0.isInvalidated }
        let validSessions = self.sessions.filter { !$0.isOutdated }
        if validSessions.isEmpty {
            let newSession = IJKLLSession.make(configuration: self.urlSessionConfig)
            self.sessions.append(newSession)
            return newSession.urlSession
        } else if validSessions.count == 1 {
            return validSessions.first?.urlSession
        } else {
            // There shouldn't be more than one valid session
            return validSessions.first?.urlSession
        }
    }
    var urlSessionConfig: URLSessionConfiguration = .ijkllDefault
    private var sessions = [IJKLLSession]()
    
    func update(configuration: URLSessionConfiguration) {
        for s in sessions {
            s.isOutdated = true
            s.finishTasksAndInvalidate()
        }
        self.urlSessionConfig = configuration
    }
    
}

// URLSession wrapper for tracing isInvalidated
class IJKLLSession: NSObject {
    var urlSession: URLSession?
    var isOutdated = false // set to true immediately after applying the new config
    var isInvalidated = false // set to true by URLSessionDelegate
    
    func load(configuration: URLSessionConfiguration) {
        guard self.urlSession == nil, isInvalidated == false else { return }
        self.urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    func finishTasksAndInvalidate() {
        self.urlSession?.finishTasksAndInvalidate()
    }
    
    static func make(configuration: URLSessionConfiguration = .ijkllDefault) -> IJKLLSession {
        let session = IJKLLSession()
        session.load(configuration: configuration)
        return session
    }
}

extension IJKLLSession: URLSessionDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        self.isInvalidated = true
    }
}

extension IJKLLSession: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
    }
}

extension IJKLLSession: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        
    }
}
