//
//  IJKLLChunkServer.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/13/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation
import Dispatch

class IJKLLChunkServer {
    static let bufferSize = 4096
    
    let port: Int
    var listenSocket: Socket? = nil
    var continueRunning = true
    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "me.mobcast.chunkServer.socketLockQueue")
    
    init(port: Int) {
        self.port = port
    }
    
    deinit {
        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }
        self.listenSocket?.close()
    }
    
    func run() {
        
        let queue = DispatchQueue.global(qos: .userInteractive)
        
        queue.async { [unowned self] in
            
            do {
                try self.listenSocket = Socket.create(family: .unix, type: .stream, proto: .unix)
                
                guard let socket = self.listenSocket else {
                    print("Unable to unwrap socket...")
                    return
                }
                
                try socket.listen(on: self.port)
                
                print("Listening on port: \(socket.listeningPort)")
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()
                    
                    print("Accepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")
                    print("Socket Signature: \(String(describing: newSocket.signature?.description))")
                    
                    self.addNewConnection(socket: newSocket)
                    
                } while self.continueRunning
                
            } catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error...")
                    return
                }
                
                if self.continueRunning {
                    
                    print("Error reported:\n \(socketError.description)")
                    
                }
            }
        }
        dispatchMain()
    }
    
    func addNewConnection(socket: Socket) {
        
        // Add the new socket to the list of connected sockets...
        socketLockQueue.sync { [unowned self, socket] in
            self.connectedSockets[socket.socketfd] = socket
        }
        
        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .default)
        
        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [unowned self, socket] in
            
            var shouldKeepRunning = true
            
            var readData = Data(capacity: IJKLLChunkServer.bufferSize)
            
            do {
                // Write the welcome string...
                // try socket.write(from: "Hello, type 'QUIT' to end session\nor 'SHUTDOWN' to stop server.\n")
                
                repeat {
                    let bytesRead = try socket.read(into: &readData)
                    
                    if bytesRead > 0 {
                        guard let response = String(data: readData, encoding: .utf8) else {
                            IJKLLLog.chunkServer("Error decoding response...")
                            readData.count = 0
                            break
                        }
                        IJKLLLog.chunkServer("Server received from connection at \(socket.remoteHostname):\(socket.remotePort): \(response) ")
                        let reply = "Server response: \n\(response)\n"
                        try socket.write(from: reply)
                    }
                    
                    if bytesRead == 0 {
                        IJKLLLog.chunkServer("server bytesRead == 0, close the connection")
                        shouldKeepRunning = false
                        break
                    }
                    
                    readData.count = 0
                    
                } while shouldKeepRunning
                
                print("Socket: \(socket.remoteHostname):\(socket.remotePort) closed...")
                socket.close()
                
                self.socketLockQueue.sync { [unowned self, socket] in
                    self.connectedSockets[socket.socketfd] = nil
                }
                
            } catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                    return
                }
                if self.continueRunning {
                    print("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }
    }
    
//    func loadReplyData() -> Data {
//        
//    }
    
    func shutdownServer() {
        print("\nShutdown in progress...")
        continueRunning = false
        
        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }
        
        listenSocket?.close()
        
        DispatchQueue.main.sync {
            exit(0)
        }
    }
}
