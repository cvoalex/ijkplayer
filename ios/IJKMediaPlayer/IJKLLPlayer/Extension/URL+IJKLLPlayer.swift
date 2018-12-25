//
//  URL+IJKLLPlayer.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/25/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

extension URL {
    func param(_ name: String) -> String? {
        guard let url = URLComponents(string: self.absoluteString) else { return nil }
        return url.queryItems?.first(where: { $0.name == name })?.value
    }
}
