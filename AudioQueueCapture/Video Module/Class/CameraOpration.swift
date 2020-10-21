//
//  CameraOpration.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/16.
//

import UIKit
import MetalPerformanceShaders
import MetalPerformanceShadersGraph
import MetalKit
import CoreMedia
import GLKit
import AVFoundation

@objc protocol cameraOprationDelegate {
    @objc optional func captureOutput(_ output: AVCaptureOutput?, didOutputSampleBuffer: CMSampleBuffer?, fromConnection: AVCaptureConnection?)
    @objc optional func captureOutput(_ output: AVCaptureOutput?, didDropSampleBuffer: CMSampleBuffer?,fromConnection: AVCaptureConnection?)
}

class CameraOpration: NSObject {
    
    // Metal
    var mtkView: MTKView?
    var commandQueue: MTLCommandQueue?
    var vertexBuffer: MTLBuffer?
    var textureCache: CVMetalTextureCache?
    var yuv2rgbComputePipeline: MTLComputePipelineState?
    var convertMatrix: float3x3?
    var texture: MTLTexture?
    let textureRenderSignal = DispatchSemaphore(value: 0)
    let textureUpdateSignal = DispatchSemaphore(value: 1)
    var luminance: MTLTexture?
    var chroma: MTLTexture?
    var renderPipelineState: MTLRenderPipelineState?
    
    var delegate: cameraOprationDelegate?
    var model: CameraConfig?
    
    fileprivate static var count: Int = 0
    fileprivate static var lastTime: Float = 0
    
    fileprivate(set) var session: AVCaptureSession?
    fileprivate var input: AVCaptureDeviceInput?
    fileprivate var videoDataOutput: AVCaptureVideoDataOutput?
    fileprivate(set) var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var captureVideoFPS = 0
    var realTimeResolutionWidth = 0
    var realTimeResolutionHeight = 0
    
    func startRuning() {
        session?.startRunning()
    }
    
    func stopRunning() {
        session?.stopRunning()
    }
    
    // MARK: - getparams
    func getMaxExposureValue() -> Float {
        return self.input!.device.maxExposureTargetBias
    }
    
    func getMinExposureValue() -> Float {
        return self.input!.device.minExposureTargetBias
    }
    
    func exposureNewValue(newValue: Float) {
        if ((try? self.input!.device.lockForConfiguration()) != nil) {
            self.input?.device.setExposureTargetBias(newValue, completionHandler: nil)
            self.input?.device.unlockForConfiguration()
        }
    }
    
    func setWhiteBlanceValue(newValue: Float) {
        if self.input!.device.isWhiteBalanceModeSupported(.locked) {
            try? self.input?.device.lockForConfiguration()
            guard let currentGains = self.input?.device.deviceWhiteBalanceGains else { return }
            guard let currentTint = self.input?.device.temperatureAndTintValues(for: currentGains).tint else { return }
            var tempAndTintValues = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues()
            tempAndTintValues.temperature = newValue
            tempAndTintValues.tint = currentTint
            guard let deviceGain = self.input?.device.deviceWhiteBalanceGains(for: tempAndTintValues) else { return }
            let deviceGains = clampGains(deviceGain, toMinVal: 1.0, andMaxVal: self.input!.device.maxWhiteBalanceGain)
            self.input?.device.setWhiteBalanceModeLocked(with: deviceGains, completionHandler: nil)
            self.input?.device.unlockForConfiguration()
        }
    }

    fileprivate func clampGains(_ gains: AVCaptureDevice.WhiteBalanceGains, toMinVal minVal: Float, andMaxVal maxVal: Float) -> AVCaptureDevice.WhiteBalanceGains {
        var tmpGains = gains
        tmpGains.blueGain = Float(max(min(tmpGains.blueGain, maxVal), minVal))
        tmpGains.redGain = Float(max(min(tmpGains.redGain, maxVal), minVal))
        tmpGains.greenGain = Float(max(min(tmpGains.greenGain, maxVal), minVal))
        return tmpGains
    }
    
    func setWhiteBlanceValueByTint(newValue: Float) {
        if self.input!.device.isWhiteBalanceModeSupported(.locked) {
            try? self.input?.device.lockForConfiguration()
            guard let currentGains = self.input?.device.deviceWhiteBalanceGains else { return }
            var deviceGains = clampGains(self.input!.device.deviceWhiteBalanceGains, toMinVal: 1.0, andMaxVal: self.input!.device.maxWhiteBalanceGain)
            guard let currentTemperature = self.input?.device.temperatureAndTintValues(for: currentGains).temperature else { return }
            var tempAndTintValues = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues()
            tempAndTintValues.temperature = currentTemperature
            tempAndTintValues.tint = newValue
            guard let deviceGain = self.input?.device.deviceWhiteBalanceGains(for: tempAndTintValues) else { return }
            deviceGains = clampGains(deviceGain, toMinVal: 1.0, andMaxVal: self.input!.device.maxWhiteBalanceGain)
            self.input?.device.setWhiteBalanceModeLocked(with: deviceGains, completionHandler: nil)
            self.input?.device.unlockForConfiguration()
        }
    }
    
    func tourchState(isOpen: Bool) {
        if (self.input!.device.hasTorch) {
            try? self.input?.device.lockForConfiguration()
            self.input!.device.torchMode = isOpen ? .on : .off
            self.input?.device.unlockForConfiguration()
        }else {
            print("The device not support torch!")
        }
    }
    
    func setVideoGravity(videoGravity: AVLayerVideoGravity) {
        session?.beginConfiguration()
        videoPreviewLayer?.videoGravity = videoGravity
        session?.commitConfiguration()
    }
    
    func setCameraForHFRWithFrameRate(frameRate: Int) {
        var frameRate = frameRate
        let maxFrameRate = getMaxFrameRateByCurrentResolution()
        if frameRate > maxFrameRate {
            frameRate = maxFrameRate
        }
        model?.frameRate = frameRate
        _ = CameraOpration.setCameraFrameRateAndResolutionWithFrameRate(rate: frameRate, resolutionHeight: model!.resolutionHeight, session: session!, position: model!.position, videoFormat: model!.videoFormat)
    }
    
    func setCameraResolutionByActiveFormatWithHeight(height: Int) {
        var height = height
        let maxResolutionHeight = getMaxSupportResolutionByActiveFormat()
        if height > maxResolutionHeight {
            height = maxResolutionHeight
        }
        model?.resolutionHeight = height
        _ = CameraOpration.setCameraFrameRateAndResolutionWithFrameRate(rate: model!.frameRate, resolutionHeight: height, session: session!, position: model!.position, videoFormat: model!.videoFormat)
    }
    
    fileprivate func getMaxSupportResolutionByActiveFormat() -> Int {
        return getDeviceSupportMaxResolutionByFrameRate(frameRate: model!.frameRate, position: model!.position, videoFormat: model!.videoFormat)
    }
    
    fileprivate func getDeviceSupportMaxResolutionByFrameRate(frameRate: Int, position: AVCaptureDevice.Position, videoFormat: OSType) -> Int {
        var maxResolutionHeight = 0
        guard let captureDevice = CameraOpration.getCaptureDevicePosition(position: position) else { return 0}
        for vFormat in captureDevice.formats {
            let description = vFormat.formatDescription
            let maxRate = Float((vFormat.videoSupportedFrameRateRanges[0]).maxFrameRate)
            let dims = CMVideoFormatDescriptionGetDimensions(description)
            if CMFormatDescriptionGetMediaSubType(description) == videoFormat && frameRate <= Int(maxRate) {
                if CameraOpration.getResolutionWidthByHeight(height: Int(dims.height)) == dims.width {
                    maxResolutionHeight = Int(dims.height)
                }
            }
        }
        return maxResolutionHeight
    }
    
    // MARK: - setFocusPoint
    
    @objc fileprivate func setFocusPointAuto() {
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
        
        if videoPreviewLayer.connection!.isVideoOrientationSupported  {
            videoPreviewLayer.connection?.videoOrientation = model.videoOrientation
        }
        previewViewLayer?.insertSublayer(videoPreviewLayer, at: 0)
//        setupMTKView()
        self.input = input;
        self.session = session
        self.videoDataOutput = videoDataOutput
        self.videoPreviewLayer = videoPreviewLayer
        
        NotificationCenter.default.addObserver(self, selector: #selector(setFocusPointAuto), name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }
    
    fileprivate func setupMTKView() {
        mtkView = MTKView(frame: model!.previewView!.frame)
        mtkView?.device = MTLCreateSystemDefaultDevice()
        model!.previewView?.insertSubview(mtkView!, at: 0)
        mtkView?.delegate = self
        mtkView?.framebufferOnly = false
        commandQueue = mtkView?.device?.makeCommandQueue()
        let library = mtkView?.device!.makeDefaultLibrary()!
                
        // setup compute pipeline
        let yuv2rgbFunc = library?.makeFunction(name: "yuvToRGB")!
        yuv2rgbComputePipeline = try! mtkView?.device!.makeComputePipelineState(function: yuv2rgbFunc!)
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, mtkView!.device!, nil, &textureCache)
        convertMatrix = float3x3(SIMD3<Float>(1.164, 1.164, 1.164), SIMD3<Float>(0, -0.231, 2.112), SIMD3<Float>(1.793, -0.533, 0))
        
        // setup render pipeline
        let vertexFunc = library!.makeFunction(name: "vertexShader")!
        let fragmentFunc = library!.makeFunction(name: "fragmentShader")!
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.colorAttachments[0].pixelFormat = mtkView!.colorPixelFormat
        renderPipelineState = try! mtkView?.device!.makeRenderPipelineState(descriptor: pipelineDesc)
        
        let vertices = [PWMVertex(position: vector_float2(-1, -1), coordinate: vector_float2(1, 1)),
                        PWMVertex(position: vector_float2(1, -1), coordinate: vector_float2(1, 0)),
                        PWMVertex(position: vector_float2(-1, 1), coordinate: vector_float2(0, 1)),
                        PWMVertex(position: vector_float2(1, 1), coordinate: vector_float2(0, 0))]
        vertexBuffer = mtkView?.device!.makeBuffer(length: MemoryLayout<PWMVertex>.size * vertices.count, options: MTLResourceOptions.storageModeShared)!
        memcpy(vertexBuffer!.contents(), vertices, MemoryLayout<PWMVertex>.size * vertices.count)
        
        let textureDesc = MTLTextureDescriptor()
        textureDesc.width = Int(model!.previewView!.frame.width)
        textureDesc.height = Int(model!.previewView!.frame.height)
        textureDesc.pixelFormat = .bgra8Unorm
        textureDesc.usage = MTLTextureUsage(rawValue: MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue)
        texture = mtkView?.device!.makeTexture(descriptor: textureDesc)!
    }
    
    fileprivate func adjustVideoStabilizationWithOutput(output: AVCaptureVideoDataOutput) {
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
    
    fileprivate static func setCameraFrameRateAndResolutionWithFrameRate(rate: Int, resolutionHeight: Int, session: AVCaptureSession, position: AVCaptureDevice.Position, videoFormat: OSType) -> Bool {
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
    
    fileprivate static func getResolutionWidthByHeight(height: Int) -> Int32 {
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
    
    fileprivate static func getCaptureDevicePosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
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
    
    // MARK: - Orientation
    func adjustVideoOrientationByScreenOrientation(orientation: UIInterfaceOrientation) {
        adjustVideoOrientation(orientation: orientation, previewFrame: model!.previewView!.frame, previewLayer: videoPreviewLayer!, videoOutput: videoDataOutput!)
    }
    
    fileprivate func adjustVideoOrientation(orientation: UIInterfaceOrientation, previewFrame: CGRect, previewLayer: AVCaptureVideoPreviewLayer, videoOutput: AVCaptureVideoDataOutput) {
        previewLayer.frame = previewFrame
        switch orientation {
        case .portrait:
            adjustAVOutputOrientation(avcaptureOrientation: .portrait, videoOutput: videoOutput)
            break
        case .portraitUpsideDown:
            adjustAVOutputOrientation(avcaptureOrientation: .portraitUpsideDown, videoOutput: videoOutput)
            break
        case .landscapeLeft:
            previewLayer.connection?.videoOrientation = .landscapeLeft
            adjustAVOutputOrientation(avcaptureOrientation: .landscapeLeft, videoOutput: videoOutput)
            break
        case .landscapeRight:
            previewLayer.connection?.videoOrientation = .landscapeRight
            adjustAVOutputOrientation(avcaptureOrientation: .landscapeRight, videoOutput: videoOutput)
            break
        default:
            break
        }
    }
    
    fileprivate func adjustAVOutputOrientation(avcaptureOrientation: AVCaptureVideoOrientation, videoOutput: AVCaptureVideoDataOutput) {
        for connection in videoOutput.connections {
            for port in connection.inputPorts {
                if port.mediaType == .video {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = avcaptureOrientation
                    }
                }
            }
        }
    }
}

extension CameraOpration: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output.isKind(of: AVCaptureVideoDataOutput.self) {
//            print("Video Output")
        } else {
//            print("Audio Output")
        }
        delegate?.captureOutput?(output, didDropSampleBuffer: sampleBuffer, fromConnection: connection)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output.isKind(of: AVCaptureVideoDataOutput.self) {
            calculatorCaptureFPS()
            guard let pix = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            realTimeResolutionWidth = CVPixelBufferGetWidth(pix)
            realTimeResolutionHeight = CVPixelBufferGetHeight(pix)
            if self.mtkView != nil {
                updateTexture(sampleBuffer: sampleBuffer)
            }
        } else {
//            print("Audio Output")
        }
        delegate?.captureOutput?(output, didOutputSampleBuffer: sampleBuffer, fromConnection: connection)
    }
    
    fileprivate func updateTexture(sampleBuffer: CMSampleBuffer) {
            guard textureUpdateSignal.wait(timeout: .now()) == .success else {
                return
            }
            
            let imagePixel = CMSampleBufferGetImageBuffer(sampleBuffer)!
            let yWidth = CVPixelBufferGetWidthOfPlane(imagePixel, 0)
            let yHeight = CVPixelBufferGetHeightOfPlane(imagePixel, 0)
            
            let uvWidth = CVPixelBufferGetWidthOfPlane(imagePixel, 1)
            let uvHeight = CVPixelBufferGetHeightOfPlane(imagePixel, 1)
            
            CVPixelBufferLockBaseAddress(imagePixel, CVPixelBufferLockFlags(rawValue: 0))
            var yTexture: CVMetalTexture?
            var uvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, imagePixel, nil, .r8Unorm, yWidth, yHeight, 0, &yTexture)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, imagePixel, nil, .rg8Unorm, uvWidth, uvHeight, 1, &uvTexture)
            
            CVPixelBufferUnlockBaseAddress(imagePixel, CVPixelBufferLockFlags(rawValue: 0))
            guard yTexture != nil && uvTexture != nil else {
                return
            }
            
            // Get MTLTexture instance
            luminance = CVMetalTextureGetTexture(yTexture!)
            chroma = CVMetalTextureGetTexture(uvTexture!)
            
            textureRenderSignal.signal()
        }
    
    fileprivate func calculatorCaptureFPS() {
        let hostClockRef = CMClockGetHostTimeClock()
        let hostTime = CMClockGetTime(hostClockRef)
        let nowTime: Float = Float(CMTimeGetSeconds(hostTime))
        if nowTime - CameraOpration.lastTime >= 1 {
            self.captureVideoFPS = CameraOpration.count
            CameraOpration.lastTime = nowTime
            CameraOpration.count = 0
        } else {
            CameraOpration.count += 1
        }
        
    }
}

extension CameraOpration: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        guard textureRenderSignal.wait(timeout: .now()) == .success else {
                    return
        }
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            return
        }
        
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        // compute pass
        computeEncoder.setComputePipelineState(yuv2rgbComputePipeline!)
        computeEncoder.setTexture(luminance, index: 0)
        computeEncoder.setTexture(chroma, index: 1)
        computeEncoder.setTexture(texture, index: 2)
        computeEncoder.setBytes(&convertMatrix, length: MemoryLayout<float3x3>.size, index: 0)
        
        let width = texture!.width
        let height = texture!.height
        
        let groupSize = 32
        let groupCountW = (width + groupSize) / groupSize - 1
        let groupCountH = (height + groupSize) / groupSize - 1
        computeEncoder.dispatchThreadgroups(MTLSize(width: groupCountW, height: groupCountH, depth: 1),
                                            threadsPerThreadgroup: MTLSize(width: groupSize, height: groupSize, depth: 1))
        computeEncoder.endEncoding()
        
        // render pass
        guard let renderPassDesc = view.currentRenderPassDescriptor else {
            return
        }
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }

        renderEncoder.setRenderPipelineState(renderPipelineState!)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(texture, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
        
        textureUpdateSignal.signal()
    }
}
