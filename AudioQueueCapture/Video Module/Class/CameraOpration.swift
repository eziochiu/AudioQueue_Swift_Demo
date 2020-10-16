//
//  CameraOpration.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/16.
//

import UIKit
import AVFoundation

@objc protocol cameraOprationDelegate {
    @objc optional func captureOutput(_ output: AVCaptureOutput?, didOutputSampleBuffer: CMSampleBuffer?, fromConnection: AVCaptureConnection?)
    @objc optional func captureOutput(_ output: AVCaptureOutput?, didDropSampleBuffer: CMSampleBuffer?,fromConnection: AVCaptureConnection?)
}

class CameraOpration: NSObject {
    
    var delegate: cameraOprationDelegate?
    var model: CameraConfig?
    
    fileprivate var session: AVCaptureSession?
    fileprivate var input: AVCaptureDeviceInput?
    fileprivate var videoDataOutput: AVCaptureVideoDataOutput?
    fileprivate var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    fileprivate var captureVideoFPS = 0
    fileprivate var realTimeResolutionWidth = 0
    fileprivate var realTimeResolutionHeight = 0
    
    func startRuning() {
        session?.startRunning()
    }
    
    // MARK: - setFocusPoint
    
    @objc fileprivate func setFocusPointAuto() {
        print("FocusPointAuto")
        setFocusPoint(point: self.model!.previewView!.center)
    }
    
    func setFocusPoint(point: CGPoint) {
        if self.input!.device.isFocusPointOfInterestSupported {
            let convertedFocusPoint = convertToPointOfInterestFromViewCoordinates(viewCoordinates: point, captureVideoPreviewLayer: self.videoPreviewLayer!)
            autoFocusAtPoint(point: convertedFocusPoint)
        }
    }
    
    fileprivate func autoFocusAtPoint(point: CGPoint) {
        if self.input!.device.isFocusPointOfInterestSupported && self.input!.device.isFocusModeSupported(.autoFocus) {
            try? self.input?.device.lockForConfiguration()
            input!.device.exposurePointOfInterest = point
            input!.device.exposureMode = .autoExpose
            input!.device.focusPointOfInterest = point
            input!.device.focusMode = .autoFocus
            input!.device.unlockForConfiguration()
        }
    }
    
    fileprivate func convertToPointOfInterestFromViewCoordinates(viewCoordinates: CGPoint, captureVideoPreviewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        var pointOfInterest = CGPoint(x: 0.5, y: 0.5)
        var viewCoordinates = viewCoordinates
        
        let frameSize = captureVideoPreviewLayer.frame.size
        if captureVideoPreviewLayer.connection!.isVideoMirrored {
            viewCoordinates.x = frameSize.width - viewCoordinates.x
        }
        pointOfInterest = captureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint: viewCoordinates)
        return pointOfInterest
    }
    
    // MARK: - switchCamera
    func switchCamera() {
        let position: AVCaptureDevice.Position = self.input!.device.position == .back ? .front : .back
        self.model?.position = position
        setCameraPosition(position: position, session: session!, input: input!, videoFormat: model!.videoFormat, height: model!.resolutionHeight, frameRate: model!.frameRate)
    }
    
    fileprivate func setCameraPosition(position: AVCaptureDevice.Position, session: AVCaptureSession, input: AVCaptureDeviceInput, videoFormat: OSType, height: Int, frameRate: Int) {
        session.beginConfiguration()
        session.removeInput(input)
        guard let device = CameraOpration.getCaptureDevicePosition(position: position) else { return }
        guard let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        session.sessionPreset = .low
        
        if session.canAddInput(newInput) {
            self.input = newInput
            session.addInput(newInput)
        }
        let maxResolution = getMaxSupportResolutionByPreset()
        
        var resolutionHeight = height
        if height > maxResolution {
            resolutionHeight = maxResolution
            self.model?.resolutionHeight = resolutionHeight
        }
        
        let maxFrameRate = getMaxFrameRateByCurrentResolution()
        var frameRate = frameRate
        if frameRate > maxFrameRate {
            frameRate = maxFrameRate
            self.model?.frameRate = frameRate
        }
        _ = CameraOpration.setCameraFrameRateAndResolutionWithFrameRate(rate: frameRate, resolutionHeight: resolutionHeight, session: session, position: position, videoFormat: videoFormat)
        session.commitConfiguration()
    }
    
    fileprivate func getMaxFrameRateByCurrentResolution() -> Int {
        var maxFrameRate = 0
        let captureDevice = CameraOpration.getCaptureDevicePosition(position: self.model!.position)
        for vFormat in captureDevice!.formats {
            let dims = vFormat.formatDescription.dimensions
            if dims.height == self.model!.resolutionHeight && dims.width == CameraOpration.getResolutionWidthByHeight(height: self.model!.resolutionHeight) {
                let maxRate = vFormat.videoSupportedFrameRateRanges.first?.maxFrameRate
                if Int(maxRate!) > maxFrameRate {
                    maxFrameRate = Int(maxRate!)
                }
            }
        }
        return maxFrameRate
    }
    
    fileprivate func getMaxSupportResolutionByPreset() -> Int {
        if self.session!.canSetSessionPreset(.hd4K3840x2160) {
            return 2160
        } else if self.session!.canSetSessionPreset(.hd1920x1080) {
            return 1080
        } else if self.session!.canSetSessionPreset(.hd1280x720) {
            return 720
        } else if self.session!.canSetSessionPreset(.vga640x480) {
            return 480
        } else if self.session!.canSetSessionPreset(.cif352x288) {
            return 288
        } else {
            return -1
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - init
    func initCameraWithModel(model: CameraConfig) {
        
        self.model = model
        
        let session = AVCaptureSession()
        
        session.sessionPreset = model.preset
        guard let device = CameraOpration.getCaptureDevicePosition(position: model.position) else { return }
        _ = CameraOpration.setCameraFrameRateAndResolutionWithFrameRate(rate: model.frameRate, resolutionHeight: model.resolutionHeight, session: session, position: model.position, videoFormat: model.videoFormat)
        
        if device.hasTorch {
            try? device.lockForConfiguration()
            if device.isTorchModeSupported(model.torchModel) {
                device.torchMode = model.torchModel
                device.addObserver(self, forKeyPath: "torchMode", options: .new, context: nil)
            }
            device.unlockForConfiguration()
        }
        
        if device.isFocusModeSupported(model.focusMode) {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            device.focusMode = model.focusMode
        }
        
        if device.isExposureModeSupported(model.exposureMode) {
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            device.exposureMode = model.exposureMode
        }
        
        if device.hasFlash {
            if #available(iOS 10.0, *) {
                for output in session.outputs {
                    if output.isMember(of: AVCapturePhotoOutput.self) {
                        let photoOutput = output as! AVCapturePhotoOutput
                        if photoOutput.isFlashScene {
                            photoOutput.photoSettingsForSceneMonitoring?.flashMode = .auto
                        }
                    }
                }
            } else {
                if device.isFlashModeSupported(model.flashMode) {
                    device.flashMode = model.flashMode
                }
            }
        }
        
        if device.isWhiteBalanceModeSupported(model.whiteBalanceMode) {
            device.whiteBalanceMode = model.whiteBalanceMode
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        input.device.isSubjectAreaChangeMonitoringEnabled = true
        session.addInput(input)
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        let audioDataOutput = AVCaptureAudioDataOutput()
        session.addOutput(videoDataOutput)
        session.addOutput(audioDataOutput)
        
        let formatTypeKey = kCVPixelBufferPixelFormatTypeKey as String
        videoDataOutput.videoSettings = [formatTypeKey: model.videoFormat]
        videoDataOutput.alwaysDiscardsLateVideoFrames = false
        
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        audioDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
        
        if model.isEnableVideoStabilization {
            adjustVideoStabilizationWithOutput(output: videoDataOutput)
        }
        
        let previewViewLayer = model.previewView?.layer
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewViewLayer?.backgroundColor = UIColor.black.cgColor
        videoPreviewLayer.frame = model.previewView!.frame
        videoPreviewLayer.videoGravity = model.videoGravity
        
        if videoPreviewLayer.connection!.isVideoStabilizationSupported {
            videoPreviewLayer.connection?.videoOrientation = model.videoOrientation
        }
        previewViewLayer?.insertSublayer(videoPreviewLayer, at: 0)
        
        self.input = input;
        self.session = session
        self.videoDataOutput = videoDataOutput
        self.videoPreviewLayer = videoPreviewLayer
        
        NotificationCenter.default.addObserver(self, selector: #selector(setFocusPointAuto), name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }
    
    func adjustVideoStabilizationWithOutput(output: AVCaptureVideoDataOutput) {
        var devices: [AVCaptureDevice]?
        if #available(iOS 10.0, *) {
            let deviceSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: self.model!.position)
            devices = deviceSession.devices
        } else {
            devices = AVCaptureDevice.devices()
        }
        for device in devices! {
            if device.hasMediaType(.video) {
                if device.activeFormat.isVideoStabilizationModeSupported(.auto) {
                    for connection in output.connections {
                        for port in connection.inputPorts {
                            if port.mediaType == .video {
                                if connection.isVideoStabilizationSupported {
                                    connection.preferredVideoStabilizationMode = .standard
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    static func setCameraFrameRateAndResolutionWithFrameRate(rate: Int, resolutionHeight: Int, session: AVCaptureSession, position: AVCaptureDevice.Position, videoFormat: OSType) -> Bool {
        guard let capture = getCaptureDevicePosition(position: position) else { return false }
        var isSucess = false
        for vFormat in capture.formats {
            let descripition = vFormat.formatDescription
            let maxRate = vFormat.videoSupportedFrameRateRanges.first?.maxFrameRate
            if Int(maxRate ?? 0) >= rate && descripition.mediaSubType.rawValue == videoFormat {
                if ((try? capture.lockForConfiguration()) != nil) {
                    // 对比镜头支持的分辨率和当前设置的分辨率
                    let dims = descripition.dimensions
                    if dims.height == resolutionHeight && dims.width == getResolutionWidthByHeight(height: resolutionHeight) {
                        session.beginConfiguration()
                        if ((try? capture.lockForConfiguration()) != nil) {
                            capture.activeFormat = vFormat
                            capture.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(rate))
                            capture.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(rate))
                            capture.unlockForConfiguration()
                        }
                        session.commitConfiguration()
                        isSucess = true
                    }
                }
            }
        }
        return isSucess
    }
    
    static func getResolutionWidthByHeight(height: Int) -> Int32 {
        switch height {
            case 2160:
                return 3840
            case 1080:
                return 1920
            case 720:
                return 1280
            case 480:
                return 640
            default:
                return -1
        }
    }
    
    static func getCaptureDevicePosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        var devices: [AVCaptureDevice]?
        if #available(iOS 10.0, *) {
            let deviceSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: position)
            devices = deviceSession.devices
        } else {
            devices = AVCaptureDevice.devices()
        }
        for device in devices! {
            if device.position == position {
                return device
            }
        }
        return nil
    }
}

extension CameraOpration: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
}
