//
//  ViewController.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/12.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    deinit {
    }
    @IBAction func startRecord(_ sender: UIButton) {
        AudioQueueCaptureManager.shared.startRecord()
    }

    @IBAction func stopRecord(_ sender: UIButton) {
        AudioQueueCaptureManager.shared.stopRecord()
    }
    @IBAction func playRecord(_ sender: UIButton) {
        AudioQueueCaptureManager.shared.play()
    }
}

