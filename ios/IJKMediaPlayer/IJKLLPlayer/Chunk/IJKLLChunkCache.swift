//
//  IJKLLChunkCache.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/13/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

class IJKLLChunkCache {
    static let shared = IJKLLChunkCache()
    
    let memoryStorage: MemoryStorage<Data> = {
        let config = MemoryConfig(expiry: .seconds(10), countLimit: 0, totalCostLimit: 0)
        let storage = MemoryStorage<Data>(config: config)
        return storage
    }()
    
    lazy var syncStorage: SyncStorage<Data> = {
        return SyncStorage(
            storage: self.memoryStorage,
            serialQueue: DispatchQueue(label: "me.mobcast.Cache.SyncStorage.SerialQueue")
        )
    }()
    
    
}
