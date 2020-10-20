//
//  VideoCaptureController.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/15.
//

import UIKit
import AVFoundation

class Proxy: NSObject {
    
    weak var target: NSObject?
    
    static func  proxyWithTarget(target: NSObject) -> Proxy{
        return Proxy.init(target: target)
    }
    
    convenience init(target: NSObject){
        self.init()
        self.target = target
    }
    
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return target
    }
}

class VideoCaptureController: UIViewController {
    @IBOutlet weak var resolutionLabel: UILabel!
    @IBOutlet weak var FPS: UILabel!
    @IBOutlet weak var exposureSlider: UISlider!
    
    static var videoGravity: Int = 0
    
    var handle = CameraOpration()
    var focusView = AdjustFocusView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configCamera()
        setupGestureRecognizer()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        adjustVideoOrientation()
        NotificationCenter.default.addObserver(self, selector: #selector(adjustVideoOrientation), name: UIDevice.orientationDidChangeNotification, object: nil)
        configFocusView()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { (timer) in
            self.linkFPS()
        }
        exposureSlider.minimumValue = handle.getMinExposureValue()
        exposureSlider.maximumValue = handle.getMaxExposureValue()
        exposureSlider.value = 0
    }
    
    func configCamera() {
        print("\(UIDevice.current.orientation.rawValue)")
        let cameraModel = CameraConfig(previewView: self.view, preset: .hd1280x720, frameRate: 60, resolutionHeight: 720, videoFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, torchMode: .off, focusMode: .locked, exposureMode: .autoExpose, flashMode: .auto, whiteBalanceMode: .autoWhiteBalance, position: .front, videoGravity: .resizeAspectFill, videoOrientation: .landscapeLeft, isEnableVideoStabilization: true)
        handle.delegate = self
        handle.initCameraWithModel(model: cameraModel)
        handle.startRuning()
    }
    
    func configFocusView() {
        focusView.isHidden = true
        view.addSubview(focusView)
    }
    
    func setupGestureRecognizer() {
        let doubleTapAction = UITapGestureRecognizer(target: self, action: #selector(handleDoubleClickAction(recognizer:)))
        doubleTapAction.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapAction)
    }
    
    @objc func handleDoubleClickAction(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: recognizer.view)
        focusView.frameByAnimationCenter(center: point)
        handle.setFocusPoint(point: point)
    }
    
    @objc func adjustVideoOrientation() {
        let orientation = UIInterfaceOrientation(rawValue: UIDevice.current.orientation.rawValue)!
        if orientation == .landscapeLeft || orientation == .landscapeRight {
            handle.adjustVideoOrientationByScreenOrientation(orientation: orientation)
        }
    }
    
    @objc func linkFPS() {
        self.FPS.text = "\(handle.captureVideoFPS)"
        self.resolutionLabel.text = "\(handle.realTimeResolutionWidth)x\(handle.realTimeResolutionHeight)"
    }
    
    @IBAction func switchCamera(_ sender: UIButton) {
        handle.switchCamera()
    }
    @IBAction func settingVC(_ sender: UIButton) {
        
    }
    @IBAction func flashModel(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        handle.tourchState(isOpen: sender.isSelected)
    }
    @IBAction func resolution(_ sender: UIButton) {
        VideoCaptureController.videoGravity += 1
        switch VideoCaptureController.videoGravity {
        case 1:
            handle.setVideoGravity(videoGravity: .resizeAspect)
            break
        case 2:
            handle.setVideoGravity(videoGravity: .resizeAspectFill)
            break
        case 3:
            handle.setVideoGravity(videoGravity: .resize)
            break
        default:
            handle.setVideoGravity(videoGravity: .resizeAspect)
            break
        }
        if VideoCaptureController.videoGravity >= 3 {
            VideoCaptureController.videoGravity = 0
        }
    }
    @IBAction func exposedValueChanged(_ sender: UISlider) {
        handle.exposureNewValue(newValue: sender.value)
    }
    @IBAction func whiteBalanceValueChanged(_ sender: UISlider) {
        handle.setWhiteBlanceValue(newValue: sender.value)
    }
    @IBAction func colorValueChanged(_ sender: UISlider) {
        handle.setWhiteBlanceValueByTint(newValue: sender.value)
    }
}

extension VideoCaptureController: cameraOprationDelegate {
    func captureOutput(_ output: AVCaptureOutput?, didOutputSampleBuffer: CMSampleBuffer?, fromConnection: AVCaptureConnection?) {
        
    }
    
    func captureOutput(_ output: AVCaptureOutput?, didDropSampleBuffer: CMSampleBuffer?, fromConnection: AVCaptureConnection?) {
        
    }
}
