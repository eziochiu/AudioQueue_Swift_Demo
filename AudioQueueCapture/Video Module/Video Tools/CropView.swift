//
//  CropView.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/20.
//

import UIKit
import Metal
import AVFoundation

class CropView: UIView {
    
    enum UICurrentDeviceScale: Int {
        
        case equal = 0

        case bigger = 1

        case smaller = 2
    }
    
    private(set) var open4K: Bool = false
    
    private(set) var useGPU: Bool = false
    
    private(set) var screenResolutionW: Int = 0
    
    private(set) var screenResolutionH: Int = 0
    
    private(set) var descendantOfMainView: Bool = false
    
    private(set) var cropX: CGFloat = 0
    
    private(set) var cropY: CGFloat = 0
    
    private(set) var screenWidth: CGFloat = 0
    
    private(set) var screenHeight: CGFloat = 0
    
    private(set) var cropViewWidth: CGFloat = 0
    
    private(set) var cropViewHeight: CGFloat = 0
    
    var videoRect: CGRect = .zero
    
    fileprivate static var lastAddressStart: Int = 0
    
    fileprivate static var pixbuffer: CVPixelBuffer?
    
    fileprivate static var videoInfo: CMVideoFormatDescription?
    
    static var ciContext: CIContext?
    
    
    var deviceScale: UICurrentDeviceScale?
    
    func initWithOPen4K(open4k: Bool, useGPU: Bool, cropWidth: Float, cropHeight: Float, screenResolutionW: Int, screenResolutionH: Int) -> CropView {
        backgroundColor = .clear
        judgeDeviceScale()
        updateVideoRect()
        self.open4K = open4k
        self.useGPU = useGPU
        self.screenResolutionW = screenResolutionW
        self.screenResolutionH = screenResolutionH
        return self
    }
    
    fileprivate func judgeDeviceScale() {
        let screenWidth = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.width : UIScreen.main.bounds.height
        let screenHeight = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.height : UIScreen.main.bounds.width
        let scale: CGFloat = 16 / 9
        let currentScale = screenWidth / screenHeight
        if currentScale - scale > 0.1 {
            self.deviceScale = .bigger
        } else if scale - currentScale > 0.1 {
            self.deviceScale = .smaller
        } else {
            self.deviceScale = .equal
        }
    }
    
    fileprivate func updateVideoRect() {
        let screenWidth = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.width : UIScreen.main.bounds.height
        let screenHeight = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.height : UIScreen.main.bounds.width
        var videoX: CGFloat = 0;
        var videoY: CGFloat = 0;
        var videoWidth: CGFloat = screenWidth;
        var videoHeight: CGFloat = screenHeight;
        switch self.deviceScale {
        case .equal:
            break
        case .bigger:
            videoWidth = screenHeight * 16 / 9
            videoX = (screenWidth - videoWidth) / 2
            break
        case .smaller:
            videoHeight = screenWidth * 9 / 16
            videoY = (screenHeight - screenHeight) / 2
            break
        default:
            break
        }
        videoRect = CGRect(x: videoX, y: videoY, width: videoWidth, height: videoHeight)
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        let lengths: [CGFloat] = [10,10]
        context?.setStrokeColor(UIColor.white.cgColor)
        context?.addRect(CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height))
        context?.setFillColor(UIColor.green.cgColor)
        context?.setLineDash(phase: 2, lengths: lengths)
        context?.strokePath()
    }
    
    func isEnableCrop(_ enableCrop: Bool, session: AVCaptureSession?, capture captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?, mainView: UIView?) {
        // 配置cropView相关部分最好事先停止相机，因为涉及到分辨率改变等因素，如果项目中存在encoder, 避免回调中数据变换产生问题。
        if session?.isRunning ?? false {
            session?.stopRunning()
        }

        if enableCrop {
            // The device screen is not 16 : 9, So we need to reset it.
            if deviceScale != .equal {
                if !(captureVideoPreviewLayer?.videoGravity == .resizeAspect) {
                    captureVideoPreviewLayer?.videoGravity = .resizeAspect
                    print("裁剪的设备不是16:9，所以我们需要调整!")
                }
            }

            if let mainView = mainView {
                if !isDescendant(of: mainView) {
                    mainView.addSubview(self)
                    descendantOfMainView = true
                }
            }

            updateCropViewWithParamOpen4KResolution(open4k: open4K, isOpenGPU: useGPU)
        } else {
            if deviceScale != .equal {
                if !(captureVideoPreviewLayer?.videoGravity == .resizeAspectFill) {
                    captureVideoPreviewLayer?.videoGravity = .resizeAspectFill
                }
            }

            if let mainView = mainView {
                if isDescendant(of: mainView) {
                    removeFromSuperview()
                    descendantOfMainView = false
                }
            }
        }

        session?.startRunning()
    }
    
    fileprivate func updateCropViewWithParamOpen4KResolution(open4k: Bool, isOpenGPU: Bool) {
        screenWidth = videoRect.size.width
        screenHeight = videoRect.size.height
        cropViewWidth = screenWidth / CGFloat(screenResolutionW) * 1280
        cropViewHeight = screenHeight / CGFloat(screenResolutionH) * 720
        let cropViewCenterX = (screenWidth  - cropViewWidth ) / 2 + videoRect.origin.x;
        let cropViewCenterY = (screenHeight - cropViewHeight) / 2 + videoRect.origin.y;
        self.frame = CGRect(x: cropViewCenterX, y: cropViewCenterY, width: cropViewWidth, height: cropViewHeight);
        updateCropViewOriginOfResolutionWithOpenGpu(isOpenGpu: isOpenGPU)
    }
    
    fileprivate func updateCropViewOriginOfResolutionWithOpenGpu(isOpenGpu: Bool) {
        cropX = CGFloat(screenResolutionW) / screenWidth * (frame.origin.x - videoRect.origin.x)
        if isOpenGpu {
            cropY  = CGFloat(screenResolutionH) / screenHeight * (screenHeight - (self.frame.origin.y - self.videoRect.origin.y) -  self.frame.size.height)
        } else {
            cropY  = CGFloat(screenResolutionH) / screenHeight * (self.frame.origin.y - self.videoRect.origin.y)
        }
    }
    
    func longPressedWithCurrentPoint(point: CGPoint, isOpenGPU: Bool) {
        var currentPointX = point.x
        var currentPointY = point.y
        
        if (currentPointX - videoRect.origin.x) < cropViewWidth / 2 {
            currentPointX = cropViewWidth / 2 + videoRect.origin.x
        } else if (currentPointX - videoRect.origin.x) > screenWidth - cropViewWidth / 2 {
            currentPointX = screenWidth - cropViewWidth / 2 + videoRect.origin.x
        }
        
        if (currentPointY - videoRect.origin.y) < cropViewHeight / 2 {
            currentPointY = cropViewHeight / 2 + videoRect.origin.y
        } else if (currentPointY - videoRect.origin.y) > screenHeight - cropViewHeight / 2 {
            currentPointY = videoRect.origin.y + screenHeight - cropViewHeight / 2
        }
        
        center = CGPoint(x: currentPointX, y: currentPointY)
        
        updateCropViewOriginOfResolutionWithOpenGpu(isOpenGpu: isOpenGPU)
    }
    
    func cropSampleBufferBySoftware(sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        var status: OSStatus = noErr
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        
        let bytesPerPixel = bytesPerRow / width
        
        if cropX.truncatingRemainder(dividingBy: 2) != 0 {
            cropX += 1
        }
        
        let baseAddressStart = Int(cropY) * bytesPerRow + bytesPerPixel * Int(cropX)
        CropView.lastAddressStart = baseAddressStart
        
        if CropView.lastAddressStart != baseAddressStart {
            if CropView.pixbuffer != nil {
                CropView.pixbuffer = nil
            }
            
            if CropView.videoInfo != nil {
                CropView.videoInfo = nil
            }
        }
        
        if CropView.pixbuffer == nil {
            
            let option = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferWidthKey: 1280, kCVPixelBufferHeightKey: 720] as [CFString : Any]
            
            let destData = malloc(baseAddressStart)
            
            status = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, 1280, 720, kCVPixelFormatType_32BGRA, destData!, bytesPerRow, nil, nil, option as CFDictionary, &CropView.pixbuffer)
            
            free(destData)
            
            if status != noErr {
                return nil
            }
        }
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        var sampleTime = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sampleBuffer), presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer))
        
        if CropView.videoInfo == nil {
            status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: CropView.pixbuffer!, formatDescriptionOut: &CropView.videoInfo)
            if status != noErr {
                return nil
            }
        }
        
        var cropBuffer: CMSampleBuffer?
        
        status = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: CropView.pixbuffer!, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: CropView.videoInfo!, sampleTiming: &sampleTime, sampleBufferOut: &cropBuffer)
        if status != noErr {
            print("CMSampleBufferCreateForImageBuffer error")
        }
        
        CropView.lastAddressStart = baseAddressStart
        
        return cropBuffer
    }
    func cropSampleBufferByHardware(sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let rect = CGRect(x: cropX, y: cropY, width: 1280, height: 720)
        
        var status: OSStatus = noErr
        
        if CropView.pixbuffer != nil {
            CropView.pixbuffer = nil
        }
        
        if CropView.videoInfo != nil {
            CropView.videoInfo = nil
        }
        
        if CropView.pixbuffer == nil {
            let option = [kCVPixelBufferWidthKey: 1280, kCVPixelBufferHeightKey: 720] as [CFString : Any]
            
            status = CVPixelBufferCreate(kCFAllocatorDefault, 1280, 720, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, option as CFDictionary, &CropView.pixbuffer)
            if status != noErr {
                return nil
            }
            
            if status != noErr {
                print("CVPixelBufferCreate error")
                return nil
            }
        }
        
        var ciImage = CIImage(cvImageBuffer: imageBuffer)
        ciImage = ciImage.cropped(to: rect)
        ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
        
        if CropView.ciContext == nil {
            guard let mtlDevice: MTLDevice = MTLCreateSystemDefaultDevice() else { return nil }
            CropView.ciContext = CIContext(mtlDevice: mtlDevice, options: nil)
        }
        CropView.ciContext?.render(ciImage, to: CropView.pixbuffer!)
        var sampleTime = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sampleBuffer), presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer))
        if CropView.videoInfo == nil {
            status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: CropView.pixbuffer!, formatDescriptionOut: &CropView.videoInfo)
            if status != noErr {
                return nil
            }
        }
        
        var cropBuffer: CMSampleBuffer?
        
        status = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: CropView.pixbuffer!, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: CropView.videoInfo!, sampleTiming: &sampleTime, sampleBufferOut: &cropBuffer)
        if status != noErr {
            print("CMSampleBufferCreateForImageBuffer error")
        }
        
        return cropBuffer
    }
}
