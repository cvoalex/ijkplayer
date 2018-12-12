//
//  Date+Extensions.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/10/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

/**
 Helper NSDate extension.
 */
extension Date {
    
    /// Checks if the date is in the past.
    var inThePast: Bool {
        return timeIntervalSinceNow < 0
    }
}
