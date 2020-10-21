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
    
    var cropView: CropView?
    
    /// 是否截图
    var isCrop = false
    
    /// 是否开启GPU截图
    var isUseGPU = true
    
    var displayLink: CADisplayLink?
    
    static var videoGravity: Int = 0
    
    static var resolutionHeight: Int = 0
    
    static var frameRate: Int = 0
    
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
        displayLink = CADisplayLink.init(target: Proxy(target: self), selector: #selector(linkFPS))
        displayLink?.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
        
        exposureSlider.minimumValue = handle.getMinExposureValue()
        exposureSlider.maximumValue = handle.getMaxExposureValue()
        exposureSlider.value = 0
    }
    
    func configCamera() {
        print("\(UIDevice.current.orientation.rawValue)")
        let cameraModel = CameraConfig(previewView: self.view, preset: .hd1920x1080, frameRate: 60, resolutionHeight: 1080, videoFormat:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, torchMode: .off, focusMode: .locked, exposureMode: .autoExpose, flashMode: .auto, whiteBalanceMode: .autoWhiteBalance, position: .front, videoGravity: .resizeAspectFill, videoOrientation: .landscapeLeft, isEnableVideoStabilization: true)
        handle.delegate = self
        handle.initCameraWithModel(model: cameraModel)
        handle.startRuning()
    }
    
    func configFocusView() {
        focusView.isHidden = true
        view.addSubview(focusView)
        
        cropView = CropView().initWithOPen4K(open4k: false, useGPU: isUseGPU, cropWidth: 1280, cropHeight: 720, screenResolutionW: 1920, screenResolutionH: 1080)
        cropView?.isEnableCrop(true, session: handle.session, capture: handle.videoPreviewLayer, mainView: self.view)
        self.view.bringSubviewToFront(cropView!)
    }
    
    func setupGestureRecognizer() {
        let doubleTapAction = UITapGestureRecognizer(target: self, action: #selector(handleDoubleClickAction(recognizer:)))
        doubleTapAction.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapAction)
        
        let pressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(recognizer:)))
        
        view.addGestureRecognizer(pressGesture)
    }
    
    @objc func handleDoubleClickAction(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: recognizer.view)
        focusView.frameByAnimationCenter(center: point)
        handle.setFocusPoint(point: point)
    }
    
    @objc func longPressed(recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: recognizer.view)
        cropView?.longPressedWithCurrentPoint(point: point, isOpenGPU: isUseGPU)
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
        VideoCaptureController.resolutionHeight += 1
        switch VideoCaptureController.resolutionHeight {
        case 1:
            handle.setCameraResolutionByActiveFormatWithHeight(height: 480)
            break
        case 2:
            handle.setCameraResolutionByActiveFormatWithHeight(height: 720)
            break
        case 3:
            handle.setCameraResolutionByActiveFormatWithHeight(height: 1080)
            break
        case 4:
            handle.setCameraResolutionByActiveFormatWithHeight(height: 2160)
            break
        default:
            break
        }
        if VideoCaptureController.resolutionHeight >= 4 {
            VideoCaptureController.resolutionHeight = 0
        }
    }
    @IBAction func changeFrameRate(_ sender: UIButton) {
        VideoCaptureController.frameRate += 1
        switch VideoCaptureController.frameRate {
        case 1:
            handle.setCameraForHFRWithFrameRate(frameRate: 25)
            break
        case 2:
            handle.setCameraForHFRWithFrameRate(frameRate: 30)
            break
        case 3:
            handle.setCameraForHFRWithFrameRate(frameRate: 50)
            break
        case 4:
            handle.setCameraForHFRWithFrameRate(frameRate: 60)
            break
        default:
            break
        }
        if VideoCaptureController.frameRate >= 4 {
            VideoCaptureController.frameRate = 0
        }
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
    @IBAction func cropImageAction(_ sender: UIButton) {
        isCrop = true
    }
}

extension VideoCaptureController: cameraOprationDelegate {
    func captureOutput(_ output: AVCaptureOutput?, didOutputSampleBuffer: CMSampleBuffer?, fromConnection: AVCaptureConnection?) {
        guard let sampleBuffer = didOutputSampleBuffer else { return }
        var cropedBuffer: CMSampleBuffer?
        if isCrop {
            if self.isUseGPU {
                cropedBuffer = cropView?.cropSampleBufferByHardware(sampleBuffer: sampleBuffer)
            } else {
                cropedBuffer = cropView?.cropSampleBufferBySoftware(sampleBuffer: sampleBuffer)
            }
            if let sampleBuffer = cropedBuffer {
                getSnapImage(sampleBuffer: sampleBuffer)
            }
            isCrop = false
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput?, didDropSampleBuffer: CMSampleBuffer?, fromConnection: AVCaptureConnection?) {
        
    }
    
    func getSnapImage(sampleBuffer: CMSampleBuffer) {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let ciimage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciimage, from: ciimage.extent)!
        let image = UIImage(cgImage: cgImage)
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        if error != nil {
            print("保存图片失败")
        } else {
            print("保存图片成功")
        }
    }
}
