//
//  AudioQueueCaptureManager.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/12.
//

import UIKit
import AudioToolbox
import AVFoundation

extension Notification.Name {
    static let audioServiceDidUpdateData = Notification.Name(rawValue: "AudioQueueCaptureDidUpdateDataNotification")
}

fileprivate func AudioQueueInputCallback(inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef, inStartTime: UnsafePointer<AudioTimeStamp>, inNumberPacketDescriptions: UInt32, inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?) {
    let audioService = unsafeBitCast(inUserData!, to:AudioQueueCaptureManager.self)
    if audioService.isRecording {
        let bytesPerPacket: UInt32  = audioService.audioFormat.mBytesPerPacket;
        var inNumPackets = inNumberPacketDescriptions
        if (inNumPackets == 0 && bytesPerPacket != 0) {
            inNumPackets = inBuffer.pointee.mAudioDataByteSize / bytesPerPacket;
        }
//        方式一：写入内存，当次有效
        audioService.writePackets(inBuffer: inBuffer)
//        方式二：写入文件
        AudioFileHandler.shared.writeFileWithInNumBytes(inNumBytes: inBuffer.pointee.mAudioDataByteSize, ioNumPackets: inNumPackets, inBuffer: inBuffer.pointee.mAudioData, inPacketDesc: inPacketDescs)
    }
    if audioService.isRunning && audioService.isRecording {
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil);
    }
    
    print("开始数据的buffer: \(audioService.startingPacketCount), 最大数据buffer: \(audioService.maxPacketCount)")
    if (audioService.maxPacketCount <= audioService.startingPacketCount) {
        audioService.stopRecord()
    }
}

fileprivate func AudioQueueOutputCallback(inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef) {
    let audioService = unsafeBitCast(inUserData!, to:AudioQueueCaptureManager.self)
//    方式一：读取内存数据，当次有效
//    audioService.readPackets(inBuffer: inBuffer)
//    if audioService.isPlaying && audioService.isRunning {
//        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil);
//    }
//    方式二：读取录制保存的文件
    audioService.readLocalPackets(inBuffer: inBuffer, inAQ: inAQ)
    
    print("开始数据的buffer: \(audioService.startingPacketCount), 最大数据buffer: \(audioService.maxPacketCount)")
    if (audioService.maxPacketCount <= audioService.startingPacketCount) {
        audioService.startingPacketCount = 0;
        audioService.stop()
    }
}

class AudioQueueCaptureManager {
    
    fileprivate let kNumberPackages = 3
    
    fileprivate var buffer: UnsafeMutableRawPointer
    
    fileprivate var mPacketDescs: UnsafeMutablePointer<AudioStreamPacketDescription>?
    
    fileprivate var audioQueueObject: AudioQueueRef?
    
    fileprivate var bufferByteSize: UInt32
    
    fileprivate var numPacketsToRead: UInt32 = 1024
    
    fileprivate let numPacketsToWrite: UInt32 = 1024
    
    fileprivate var startingPacketCount: UInt32
    
    fileprivate var maxPacketCount: UInt32
    
    fileprivate let bytesPerPacket: UInt32 = 2
    
    /// 设置录音时常，默认30s
    var seconds: UInt32 = 30
    
    private(set) var isRunning = false
    
    private(set) var isRecording = false
    
    private(set) var isPlaying = false
    
    fileprivate var audioFormat: AudioStreamBasicDescription {
        return AudioStreamBasicDescription(mSampleRate: 48000.0, mFormatID: kAudioFormatLinearPCM, mFormatFlags: AudioFormatFlags(kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked), mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    }
    var data: NSData? {
        didSet {
            NotificationCenter.default.post(name: .audioServiceDidUpdateData, object: self)
        }
    }
    
    static let shared = AudioQueueCaptureManager()
    
    private init() {
        startingPacketCount = 0
        bufferByteSize = 0
        maxPacketCount = (48000 * seconds)
        buffer = UnsafeMutableRawPointer(malloc(Int(maxPacketCount * bytesPerPacket)))
    }

    deinit {
        buffer.deallocate()
        isRunning = false
        isRecording = false
        isPlaying = false
    }

    func startRecord() {
        isRunning = true
        isRecording = true
        isPlaying = false
        data = nil
        prepareForRecord()
        guard let queue = audioQueueObject else  { return }
        AudioFileHandler.shared.startVoiceRecordByAudioQueue(audioQueue: queue, isNeedMagicCookie: false, audioDesc: audioFormat)
        let error: OSStatus = AudioQueueStart(queue, nil)
        if error != noErr {
            print("error: \(error)")
        }
    }

    func stopRecord() {
        if startingPacketCount < maxPacketCount {
            maxPacketCount = startingPacketCount
        }
        guard let queue = audioQueueObject else { return }
        data = NSData(bytesNoCopy: buffer, length: Int(maxPacketCount * bytesPerPacket))
        AudioFileHandler.shared.stopVoiceRecordByAudioQueue(audioQueue: queue, isNeedMagicCookie: false)
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
        audioQueueObject = nil
        isRunning = false
        isRecording = false
    }
    
    func play() {
        isRunning = true
        isRecording = false
        isPlaying = true
        prepareForLocalPlay()  //播放当前内存buffer
//        prepareForMemoryPlay()  //播放当前内存buffer
        guard let queue = audioQueueObject else  { return }
        let error: OSStatus = AudioQueueStart(queue, nil)
        if error != noErr {
            print("error: \(error)")
        }
    }

    func stop() {
        guard let queue = audioQueueObject else  { return }
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
        audioQueueObject = nil
        isRunning = false
        isPlaying = false
    }

    func setData(_ data: NSMutableData) {
        self.data = data.copy() as? NSData
        memcpy(buffer, data.mutableBytes, Int(maxPacketCount * bytesPerPacket))
    }

    private func prepareForRecord() {
        print("准备录音")
        var audioFormat = self.audioFormat
    
        AudioQueueNewInput(&audioFormat, AudioQueueInputCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &audioQueueObject)
        
        startingPacketCount = 0;
        var buffers = Array<AudioQueueBufferRef?>(repeating: nil, count: kNumberPackages)
        let bufferByteSize: UInt32 = numPacketsToWrite * audioFormat.mBytesPerPacket
        guard let queue = audioQueueObject else { return }
        for bufferIndex in 0 ..< buffers.count {
            AudioQueueAllocateBuffer(queue, bufferByteSize, &buffers[bufferIndex])
            AudioQueueEnqueueBuffer(queue, buffers[bufferIndex]!, 0, nil)
        }
    }
    
    private func prepareForLocalPlay() {
        print("准备播放")
        guard var audioFormat = AudioFileHandler.shared.configurePlayFilePath() else { return }
    
        AudioQueueNewOutput(&audioFormat, AudioQueueOutputCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &audioQueueObject)
        
        startingPacketCount = 0
        
        var maxPacketSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.stride)
        
        AudioFileGetProperty(AudioFileHandler.shared.playFile!, kAudioFilePropertyPacketSizeUpperBound, &propertySize, &maxPacketSize)
        
        DeriveBufferSize(ASBDesc: audioFormat, maxPacketSize: maxPacketSize, seconds: 0.5, outBufferSize: &bufferByteSize, outNumPacketsToRead: &numPacketsToRead)
        
        // Allocating Memory for a Packet Descriptions Array
        let isFormatVBR = audioFormat.mBytesPerPacket == 0 || audioFormat.mFramesPerPacket == 0

        if isFormatVBR {
            let size = Int(numPacketsToRead * UInt32(MemoryLayout<AudioStreamPacketDescription>.stride))
            mPacketDescs = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: size)
        } else {
            mPacketDescs = nil
        }
        
        // 为播放音频队列设置Magic Cookie
        var cookieSize = UInt32(MemoryLayout<UInt32>.stride)
        let status = AudioFileGetPropertyInfo(AudioFileHandler.shared.playFile!, kAudioFilePropertyMagicCookieData, &cookieSize, nil)
        if status != noErr {
            let magicCookie = UnsafeMutablePointer<CChar>.allocate(capacity: Int(cookieSize))
            AudioFileGetProperty(audioQueueObject!, kAudioFilePropertyMagicCookieData, &cookieSize, magicCookie)
            AudioQueueSetProperty(audioQueueObject!, kAudioQueueProperty_MagicCookie, magicCookie, cookieSize)
            free(magicCookie)
        }
        
        var buffers = Array<AudioQueueBufferRef?>(repeating: nil, count: kNumberPackages)
        
        guard let queue = audioQueueObject else { return }
        for bufferIndex in 0 ..< buffers.count {
            AudioQueueAllocateBuffer(queue, bufferByteSize, &buffers[bufferIndex])
            AudioQueueOutputCallback(inUserData: unsafeBitCast(self, to: UnsafeMutableRawPointer.self), inAQ: queue, inBuffer: buffers[bufferIndex]!)
        }
    }
    
    private func DeriveBufferSize(ASBDesc: AudioStreamBasicDescription, maxPacketSize: UInt32, seconds: Float64, outBufferSize: UnsafeMutablePointer<UInt32>, outNumPacketsToRead: UnsafeMutablePointer<UInt32>) {
        let maxBufferSize: UInt32 = 0x50000 // 320 KB
        let minBufferSize: UInt32 = 0x4000  // 16 KB

        if ASBDesc.mFramesPerPacket != 0 {
            let numPacketsForTime = ASBDesc.mSampleRate / Float64(ASBDesc.mFramesPerPacket) * seconds
            outBufferSize.pointee = UInt32(numPacketsForTime) * maxPacketSize
        } else {
            outBufferSize.pointee = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize
        }

        if outBufferSize.pointee > maxBufferSize && outBufferSize.pointee > maxPacketSize {
            outBufferSize.pointee = maxBufferSize
        } else {
            if outBufferSize.pointee < minBufferSize {
                outBufferSize.pointee = minBufferSize
            }
        }

        outNumPacketsToRead.pointee = outBufferSize.pointee / maxPacketSize
      }
    
    private func prepareForMemoryPlay() {
        print("准备播放")
        var audioFormat = self.audioFormat
    
        AudioQueueNewOutput(&audioFormat, AudioQueueOutputCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &audioQueueObject)
        
        startingPacketCount = 0
        var buffers = Array<AudioQueueBufferRef?>(repeating: nil, count: kNumberPackages)
        let bufferByteSize: UInt32 = numPacketsToRead * audioFormat.mBytesPerPacket
        guard let queue = audioQueueObject else { return }
        for bufferIndex in 0 ..< buffers.count {
            AudioQueueAllocateBuffer(queue, bufferByteSize, &buffers[bufferIndex])
            AudioQueueOutputCallback(inUserData: unsafeBitCast(self, to: UnsafeMutableRawPointer.self), inAQ: queue, inBuffer: buffers[bufferIndex]!)
        }
    }
    
    fileprivate func readLocalPackets(inBuffer: AudioQueueBufferRef, inAQ: AudioQueueRef) {
        var numBytesReadFromFile = bufferByteSize
        var numPackets = numPacketsToRead
        
        AudioFileReadPacketData(AudioFileHandler.shared.playFile!, false, &numBytesReadFromFile, mPacketDescs, Int64(startingPacketCount), &numPackets, inBuffer.pointee.mAudioData)
        if numPackets > 0 {
            inBuffer.pointee.mAudioDataByteSize = numBytesReadFromFile
            AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
            startingPacketCount += numPackets
        } else {
            inBuffer.pointee.mAudioDataByteSize = 0;
            inBuffer.pointee.mPacketDescriptionCount = 0;
            stop()
            maxPacketCount = startingPacketCount
        }
    }

    fileprivate func readPackets(inBuffer: AudioQueueBufferRef) {
        print("正在读取数据")
        var numPackets: UInt32 = maxPacketCount - startingPacketCount
        if numPacketsToRead < numPackets {
            numPackets = numPacketsToRead
        }
        
        if 0 < numPackets {
            memcpy(inBuffer.pointee.mAudioData, buffer.advanced(by: Int(bytesPerPacket * startingPacketCount)), (Int(bytesPerPacket * numPackets)))
            inBuffer.pointee.mAudioDataByteSize = (bytesPerPacket * numPackets)
            inBuffer.pointee.mPacketDescriptionCount = numPackets
            startingPacketCount += numPackets
        } else {
            inBuffer.pointee.mAudioDataByteSize = 0;
            inBuffer.pointee.mPacketDescriptionCount = 0;
        }
    }
    
    fileprivate func writePackets(inBuffer: AudioQueueBufferRef) {
        print("正在写数据\n")
        print("正在写数据 mAudioDataByteSize: \(inBuffer.pointee.mAudioDataByteSize), numPackets: \(inBuffer.pointee.mAudioDataByteSize / 2)\n")
        var numPackets: UInt32 = (inBuffer.pointee.mAudioDataByteSize / bytesPerPacket)
        if ((maxPacketCount - startingPacketCount) < numPackets) {
            numPackets = (maxPacketCount - startingPacketCount)
        }

        if 0 < numPackets {
            memcpy(buffer.advanced(by: Int(bytesPerPacket * startingPacketCount)),
                   inBuffer.pointee.mAudioData,
                   Int(bytesPerPacket * numPackets))
            startingPacketCount += numPackets;
        }
    }
}
