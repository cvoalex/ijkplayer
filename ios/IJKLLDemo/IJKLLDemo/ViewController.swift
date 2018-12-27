//
//  ViewController.swift
//  IJKLLDemo
//
//  Created by Xinzhe Wang on 12/23/18.
//  Copyright © 2018 MobZ. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var streamIdTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    @IBAction func onStartPlayer(_ sender: Any) {
        guard let streamId = streamIdTextField.text, !streamId.isEmpty else { return }
        let vc = PlayerViewController.instantiate(streamId)
        present(vc, animated: true, completion: nil)
    }
    
    @IBAction func onStartDownloader(_ sender: Any) {
        guard let streamId = streamIdTextField.text, !streamId.isEmpty else { return }
        let vc = DownloaderViewController.instantiate(streamId)
        present(vc, animated: true, completion: nil)
    }
}

