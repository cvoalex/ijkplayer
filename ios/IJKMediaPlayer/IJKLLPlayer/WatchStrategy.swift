//
//  WatchStrategy.swift
//  DVGPlayer
//
//  Created by Xinzhe Wang on 11/28/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import Foundation

protocol WatchStrategy {
    
}

class RealTimeWatchStrategy: WatchStrategy {
    
}

class Watcher {
    var watcher = RealTimeWatchStrategy()
}
