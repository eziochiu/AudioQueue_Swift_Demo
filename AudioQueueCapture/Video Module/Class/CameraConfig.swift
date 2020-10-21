//
//  CameraConfig.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/16.
//

import UIKit
import AVFoundation

class CameraConfig: NSObject {
    var previewView: UIView?
    var preset: AVCaptureSession.Preset = .hd1920x1080
    var frameRate: Int = 60
    var resolutionHeight: Int = 1080
    var videoFormat: OSType = kCVPixelFormatType_32BGRA
    /// 闪光灯模式
    var torchModel: AVCaptureDevice.TorchMode = .off
    /// 聚焦模式
    var focusMode: AVCaptureDevice.FocusMode = .autoFocus
    /// 曝光模式
    var exposureMode: AVCaptureDevice.ExposureMode = .autoExpose
    var flashMode: AVCaptureDevice.FlashMode = .auto
    /// 白平衡模式
    var whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .autoWhiteBalance
    /// 相机位置
    var position: AVCaptureDevice.Position = .back
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var videoOrientation: AVCaptureVideoOrientation = .landscapeRight
    var isEnableVideoStabilization: Bool = false
    
    init(previewView: UIView?, preset: AVCaptureSession.Preset, frameRate: Int, resolutionHeight: Int, videoFormat: OSType, torchMode: AVCaptureDevice.TorchMode, focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, flashMode: AVCaptureDevice.FlashMode, whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode, position: AVCaptureDevice.Position, videoGravity: AVLayerVideoGravity, videoOrientation: AVCaptureVideoOrientation, isEnableVideoStabilization: Bool) {
        super.init()
        self.previewView = previewView
        self.preset = preset
        self.frameRate = frameRate
        self.resolutionHeight = resolutionHeight
        self.videoFormat = videoFormat
        self.torchModel = torchMode
        self.focusMode = focusMode
        self.exposureMode = exposureMode
        self.flashMode = flashMode
        self.whiteBalanceMode = whiteBalanceMode
        self.position = position
        self.videoGravity = videoGravity
        self.videoOrientation = videoOrientation
        self.isEnableVideoStabilization = isEnableVideoStabilization
    }
}
