//
//  URLSessionConfiguration+IJKLLPlayer.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/12/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

extension URLSessionConfiguration {
    public static var ijkllDefault: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true
        if #available(iOS 11.0, *) {
            configuration.multipathServiceType = .handover
        }
        return configuration
    }
    
    public static var ijkllMeta: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 5
        if #available(iOS 11.0, *) {
            configuration.multipathServiceType = .handover
        }
        return configuration
    }
}
