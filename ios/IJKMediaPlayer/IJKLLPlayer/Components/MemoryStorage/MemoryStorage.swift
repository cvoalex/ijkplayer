//
//  MemoryStorage.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/10/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

public class MemoryStorage<T>: StorageAware {
    fileprivate let cache = NSCache<NSString, MemoryCapsule>()
    // Memory cache keys
    fileprivate var keys = Set<String>()
    /// Configuration
    fileprivate let config: MemoryConfig
    
    public init(config: MemoryConfig) {
        self.config = config
        self.cache.countLimit = Int(config.countLimit)
        self.cache.totalCostLimit = Int(config.totalCostLimit)
    }
}

extension MemoryStorage {
    public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil, dataSent: Int = 0) {
        let capsule = MemoryCapsule(value: object, expiry: .date(expiry?.date ?? config.expiry.date), dataSent: dataSent)
        cache.setObject(capsule, forKey: NSString(string: key))
        keys.insert(key)
    }
    
    public func removeAll() {
        cache.removeAllObjects()
        keys.removeAll()
    }
    
    public func removeExpiredObjects() {
        let allKeys = keys
        for key in allKeys {
            removeObjectIfExpired(forKey: key)
        }
    }
    
    public func removeObjectIfExpired(forKey key: String) {
        if let capsule = cache.object(forKey: NSString(string: key)), capsule.expiry.isExpired {
            removeObject(forKey: key)
        }
    }
    
    public func removeObject(forKey key: String) {
        cache.removeObject(forKey: NSString(string: key))
        keys.remove(key)
    }
    
    public func entry(forKey key: String) throws -> Entry<T> {
        guard let capsule = cache.object(forKey: NSString(string: key)) else {
            throw StorageError.notFound
        }
        
        guard let object = capsule.object as? T else {
            throw StorageError.typeNotMatch
        }
        
        return Entry(object: object, expiry: capsule.expiry, dataSent: capsule.dataSent)
    }
}

public extension MemoryStorage {
    func transform<U>() -> MemoryStorage<U> {
        let storage = MemoryStorage<U>(config: config)
        return storage
    }
}
