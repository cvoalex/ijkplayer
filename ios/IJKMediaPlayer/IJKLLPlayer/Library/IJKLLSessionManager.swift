//
//  IJKLLSessionManager.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/12/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public protocol IJKLLSessionManagerDelegate: class {
    func taskReceiveResponse(request: URLRequest)
    func taskBeginReceiveData(request: URLRequest, data: Data)
    func taskReceiveData(request: URLRequest, data: Data)
    func taskComplete(request: URLRequest)
    func taskCompleteWithError(request: URLRequest, error: Error)
}

public class IJKLLSessionManager {
    public weak var delegate: IJKLLSessionManagerDelegate?
    var session: URLSession? {
        self.sessions = self.sessions.filter { !$0.isInvalidated }
        let validSessions = self.sessions.filter { !$0.isOutdated }
        if validSessions.isEmpty {
            let newSession = IJKLLSession.make(configuration: self.urlSessionConfig)
            newSession.delegate = self
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
    
    public var activedDownloads = 0
    public var activedWaits = 0
    
    // Aollow to change config on the fly
    func update(configuration: URLSessionConfiguration) {
        for s in sessions {
            s.isOutdated = true
            s.finishTasksAndInvalidate()
        }
        self.urlSessionConfig = configuration
    }
    
}

extension IJKLLSessionManager: IJKLLSessionDelegate {
    func ijkSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        IJKLLLog.sessionManager("didBecomeInvalidWithError error: \(error), actived sessions \(sessions.count)")
    }
    
    func ijkSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) {
        let filename = dataTask.originalRequest?.url?.lastPathComponent ?? "unknown"
        let time = Date().timeIntervalSince1970
        IJKLLLog.sessionManager("didReceive response\(filename) at time \(time)")
        activedWaits += 1
        guard let req = dataTask.originalRequest else { return }
        delegate?.taskReceiveResponse(request: req)
    }
    
    func ijkSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let request = dataTask.originalRequest, let chunk = IJKLLChunk(request) else { return }
        let key = chunk.requestKey
        if let entry = try? IJKLLChunkCache.shared.syncStorage.entry(forKey: key) {
            var savedData = entry.object
            IJKLLLog.sessionManager("didReceive data from \(key), new \(data.count), existed \(savedData.count)")
            savedData.append(data)
            IJKLLChunkCache.shared.syncStorage.setObject(savedData, forKey: key, expiry: entry.expiry, dataSent: entry.dataSent)
            guard let req = dataTask.originalRequest else { return }
            delegate?.taskReceiveData(request: req, data: data)
            IJKLLChunkCache.shared.syncStorage.removeExpiredObjects()
        } else {
            IJKLLChunkCache.shared.syncStorage.setObject(data, forKey: key, dataSent: 0)
            IJKLLLog.sessionManager("didReceive data from \(key), new \(data.count)")
            activedDownloads += 1
            activedWaits -= 1
            guard let req = dataTask.originalRequest else { return }
            delegate?.taskBeginReceiveData(request: req, data: data)
        }
    }
    
    func ijkSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let chunk = IJKLLChunk(task.originalRequest!)!
        if let err = error {
            IJKLLLog.debug("didCompleteWithError \(chunk.sequence) data received \(task.countOfBytesReceived)/\(task.countOfBytesExpectedToReceive) error \(err)")
            guard let req = task.originalRequest else { return }
            delegate?.taskCompleteWithError(request: req, error: err)
        } else {
            IJKLLLog.debug("didCompleteWithError \(chunk.sequence) data received \(task.countOfBytesReceived)/\(task.countOfBytesExpectedToReceive) success")
            guard let req = task.originalRequest else { return }
            delegate?.taskComplete(request: req)
        }
        activedDownloads -= 1
    }
}

protocol IJKLLSessionDelegate: class {
    func ijkSession(_ session: URLSession, didBecomeInvalidWithError error: Error?)
    func ijkSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse)
    func ijkSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
    func ijkSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
}

// URLSession wrapper for tracing isInvalidated
public class IJKLLSession: NSObject {
    weak var delegate: IJKLLSessionDelegate?
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
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        self.isInvalidated = true
        delegate?.ijkSession(session, didBecomeInvalidWithError: error)
    }
}

extension IJKLLSession: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        delegate?.ijkSession(session, dataTask: dataTask, didReceive: response)
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        delegate?.ijkSession(session, task: task, didCompleteWithError: error)
    }
}

extension IJKLLSession: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        delegate?.ijkSession(session, dataTask: dataTask, didReceive: data)
    }
}
