//
//  PlayerViewController.swift
//  IJKLLDemo
//
//  Created by Xinzhe Wang on 12/26/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import UIKit
import IJKMediaFramework

class PlayerViewController: UIViewController {
    
    var streamId: String!
    var player: IJKLLPlayer!
    
    static func instantiate(_ streamId: String) -> PlayerViewController {
        let vc = PlayerViewController()
        vc.streamId = streamId
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        player = IJKLLPlayer(config: .default, state: .default)
        player.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.main.async {
            self.player.prepareToPlay(self.streamId)
            if let playerView = self.player.view {
                playerView.frame = self.view.bounds
                self.view.addSubview(playerView)
            }
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.main.async {
            self.player.prepareToRelease()
        }
        
    }

}

extension PlayerViewController: IJKLLPlayerDelegate {
    func onPlayerUpdate(player: IJKMediaPlayback?) {
        
    }
    
    func onError(error: Error) {
        
    }
    
    func onStart() {
        
    }
    
    func onFinish() {
        
    }
    
    func onStatsUpdate(loader: IJKLLChunkLoader) {
        
    }
    
}
