//
//  MemoryCapsule.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/10/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

/// Helper class to hold cached instance and expiry date.
/// Used in memory storage to work with NSCache.
class MemoryCapsule: NSObject {
    /// Object to be cached
    let object: Any
    /// Expiration date
    let expiry: Expiry
    
    let dataSent: Int
    /**
     Creates a new instance of Capsule.
     - Parameter value: Object to be cached
     - Parameter expiry: Expiration date
     */
    init(value: Any, expiry: Expiry, dataSent: Int) {
        self.object = value
        self.expiry = expiry
        self.dataSent = dataSent
    }
}
