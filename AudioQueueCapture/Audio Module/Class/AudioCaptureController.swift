//
//  ViewController.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/12.
//

import UIKit

class AudioCaptureController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    deinit {
    }
    @IBAction func startRecord(_ sender: UIButton) {
//        AudioQueueCaptureManager.shared.startRecord()
        AudioUnitCaptrueManager.shared.startRecord()
    }

    @IBAction func stopRecord(_ sender: UIButton) {
//        AudioQueueCaptureManager.shared.stopRecord()
        AudioUnitCaptrueManager.shared.stopRecord()
    }
    @IBAction func playRecord(_ sender: UIButton) {
//        AudioQueueCaptureManager.shared.play()
        AudioUnitCaptrueManager.shared.play()
    }
}

