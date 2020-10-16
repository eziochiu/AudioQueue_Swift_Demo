//
//  VideoCaptureController.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/15.
//

import UIKit
import AVFoundation

class VideoCaptureController: UIViewController {
    
    var handle = CameraOpration()
    

    override func viewDidLoad() {
        super.viewDidLoad()
        configCamera()
        setupGestureRecognizer()
    }
    
    func configCamera() {
        let cameraModel = CameraConfig(previewView: self.view, preset: .hd1920x1080, frameRate: 60, resolutionHeight: 1080, videoFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, torchMode: .off, focusMode: .locked, exposureMode: .autoExpose, flashMode: .auto, whiteBalanceMode: .autoWhiteBalance, position: .back, videoGravity: .resizeAspect, videoOrientation: .portrait, isEnableVideoStabilization: true)
        handle.delegate = self
        handle.initCameraWithModel(model: cameraModel)
        handle.startRuning()
    }
    
    func setupGestureRecognizer() {
        let doubleTapAction = UITapGestureRecognizer.init(target: self, action: #selector(handleDoubleClickAction(recognizer:)))
        doubleTapAction.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapAction)
    }
    
    @objc func handleDoubleClickAction(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: recognizer.view)
        handle.setFocusPoint(point: point)
    }
    
    @IBAction func switchCamera(_ sender: UIButton) {
        handle.switchCamera()
    }
}

extension VideoCaptureController: cameraOprationDelegate {
    
}
