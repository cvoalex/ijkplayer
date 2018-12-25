//
//  DownloaderViewController.swift
//  IJKLLDemo
//
//  Created by Xinzhe Wang on 12/23/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import UIKit
import IJKMediaFramework

class DownloaderViewController: UIViewController {
    
    var streamId: String!
    var chart: DVGLLPlayerStatChart!
    var downloadTester: IJKLLDownloadTester!
    
    static func instantiate(_ streamId: String) -> DownloaderViewController {
        let vc = DownloaderViewController()
        vc.streamId = streamId
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        let chartFrame = CGRect(x: 0, y: 40, width: view.frame.size.width*0.95, height: view.frame.size.height*0.3)
        self.chart = DVGLLPlayerStatChart.init(frame: chartFrame)
        view.addSubview(chart)
        self.downloadTester = IJKLLDownloadTester(streamId: streamId)
        self.downloadTester.delegate = self
    }
    
}

extension DownloaderViewController: IJKLLDownloadTesterDelegate {
    func onStatsUpdate(loader: IJKLLChunkLoader, timestamp: TimeInterval) {
        DispatchQueue.main.async {
            self.chart.updateTotalData(loader.state.totalDataCount)
        }
    }
}
