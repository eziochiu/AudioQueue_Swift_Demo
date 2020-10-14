//
//  AudioQueueCaptureManager.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/12.
//

import UIKit
import AudioToolbox
import AVFoundation

fileprivate func AudioUnitInputCallback(inUserData: UnsafeMutableRawPointer, ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, inTimeStamp: UnsafePointer<AudioTimeStamp>, inBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    print("recording...")
    let audioUnit = unsafeBitCast(inUserData, to:AudioUnitCaptrueManager.self)
    var status = noErr;
    if audioUnit.type.method == 0 {
        status = AudioUnitRender(audioUnit.audioUnit!, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData!)
        AudioFileHandler.shared.writeFileWithInNumBytes(inNumBytes: (ioData?.pointee.mBuffers.mDataByteSize)!, ioNumPackets: inNumberFrames, inBuffer: (ioData?.pointee.mBuffers.mData)!, inPacketDesc: nil)
    } else {
        /// 创建一个新的buffer
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(inNumberFrames * 2), alignment: MemoryLayout<Int8>.alignment)
        let bindPointee = buffer.bindMemory(to: Int8.self, capacity: Int(inNumberFrames * 2))
        bindPointee.initialize(to: 0)
        let buffers = AudioBuffer(mNumberChannels: 1, mDataByteSize: inNumberFrames * 2, mData: buffer)
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: buffers)
        status = AudioUnitRender(audioUnit.audioUnit!, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)
        audioUnit.audioBuffers.append((buffers, Int(inNumberFrames * 2)))
    }
        
    return status
}

fileprivate func AudioUnitOutputCallback(inUserData: UnsafeMutableRawPointer, ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, inTimeStamp: UnsafePointer<AudioTimeStamp>, inBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    print("playing...")
    let status = noErr;
    let audioUnit = unsafeBitCast(inUserData, to:AudioUnitCaptrueManager.self)
    if ioData == nil{
        return status
    }
    if audioUnit.type.method == 2 {
        var inNumberFrames = inNumberFrames
        ExtAudioFileRead(audioUnit.audioFile!, &inNumberFrames, audioUnit.bufferList!)
    }
    let buffCount = ioData?.pointee.mNumberBuffers
    if buffCount != 1 {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        for _ in buffers! {
            //to do...
        }
    } else {
        if audioUnit.audioBuffers.count > 0 {
            let tempBuffer = audioUnit.audioBuffers[0];
            memcpy(ioData?.pointee.mBuffers.mData, tempBuffer.0.mData, Int(tempBuffer.0.mDataByteSize))
            ioData?.pointee.mNumberBuffers = 1
            tempBuffer.0.mData?.deallocate()
            audioUnit.audioBuffers.removeFirst()
        } else {
            
        }
    }
        
    return status
}

class AudioUnitCaptrueManager {
    
    struct callBackType {
        
        /// 0 : 只录制保存到本地文件，1：边录边播，不保存本地文件，2：只播放本地文件
        var method = 0
    }
    
    fileprivate let kOutputBus = AudioUnitElement(0)
    
    fileprivate let kInputBus = AudioUnitElement(1)
    
    fileprivate var audioUnit: AudioUnit?
    
    fileprivate var audioBuffers = [(AudioBuffer, Int)]()
    
    fileprivate var bufferList: UnsafeMutablePointer<AudioBufferList>?
    
    fileprivate var type = callBackType()
    
    fileprivate var audioFile: ExtAudioFileRef?
    
    /// 设置录音时常，默认30s
    var seconds: UInt32 = 30
    
    private(set) var isRunning = false
    
    private(set) var isRecording = false
    
    private(set) var isPlaying = false
    
    fileprivate var audioFormat: AudioStreamBasicDescription {
        return AudioStreamBasicDescription(mSampleRate: 48000.0, mFormatID: kAudioFormatLinearPCM, mFormatFlags: AudioFormatFlags(kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked), mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    }
    
    static let shared = AudioUnitCaptrueManager()
    
    private init() {
        type.method = 1
        initBufferList()
    }
    
    fileprivate func initBufferList() {
        let size = Int(MemoryLayout<AudioBufferList>.stride)
        bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: size)
        bufferList?.pointee.mNumberBuffers = 1
        bufferList?.pointee.mBuffers.mNumberChannels = 1
        bufferList?.pointee.mBuffers.mDataByteSize = 0x1000
        bufferList?.pointee.mBuffers.mData = malloc(Int(MemoryLayout<UInt32>.stride))
    }

    deinit {
        isRunning = false
        isRecording = false
        isPlaying = false
    }

    func startRecord() {
        isRunning = true
        isRecording = true
        isPlaying = false
        prepareForUnit()
        guard let queue = audioUnit else  { return }
        if type.method == 0 {
            AudioFileHandler.shared.startVoiceRecordByAudioUnitByAudioConverter(audioConverter: nil, isNeedMagicCookie: false, audioDesc: self.audioFormat)
        }
        let error: OSStatus = AudioOutputUnitStart(queue)
        if error != noErr {
            print("error: \(error)")
        }
    }

    func stopRecord() {
        guard let queue = audioUnit else { return }
        if type.method == 0 {
            AudioFileHandler.shared.stopVoiceRecordAudioConverter(audioConverter: nil, isNeedMagicCookie: false)
        }
        AudioOutputUnitStop(queue)
        isRunning = false
        isRecording = false
    }
    
    func play() {
        isRunning = true
        isRecording = false
        isPlaying = true
        prepareForUnit()
        guard let queue = audioUnit else  { return }
        let error: OSStatus = AudioOutputUnitStart(queue)
        if error != noErr {
            print("error: \(error)")
        }
    }

    func stop() {
        guard let queue = audioUnit else  { return }
        AudioOutputUnitStop(queue)
        audioUnit = nil
        isRunning = false
        isPlaying = false
    }
    
    fileprivate func prepareUnit() -> AudioUnit? {
        var audioUnit: AudioUnit?
        
        var audioDesc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_VoiceProcessingIO, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        
        guard let inputComponent = AudioComponentFindNext(nil, &audioDesc) else { return audioUnit }
        
        let status = AudioComponentInstanceNew(inputComponent, &audioUnit)
        
        if status == noErr {
            print("initialize AudioUnit scuessful")
        }
        return audioUnit
    }

    private func prepareForUnit() {
        print("准备录音")
        var status: OSStatus
        var audioFormat: AudioStreamBasicDescription?
        if type.method == 0 || type.method == 1 {
            audioFormat = self.audioFormat
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .defaultToSpeaker)
            try? AVAudioSession.sharedInstance().setActive(true, options: AVAudioSession.SetActiveOptions.init())
            audioFormat = AudioFileHandler.shared.configurePlayFilePath()
            ExtAudioFileOpenURL(AudioFileHandler.shared.configureUnitPlayFilePath()!, &audioFile)
        }
        
        guard let audioUnit = prepareUnit() else { return }
        self.audioUnit = audioUnit
        //Enable IO for Recording
        var flag:UInt32 = 1
        status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &flag, UInt32(MemoryLayout<UInt32>.size))
        
        //Enable IO for Playback
        flag = 1
        status |= AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, kOutputBus, &flag, UInt32(MemoryLayout<UInt32>.size))
        
        if status != noErr{
            return
        }
        
        //set recording and playback audio format
        
        status |= AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, &audioFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        
        status |= AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &audioFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        
        //enable echo cancellation (default is 0, don't need to set, just for test)
        flag = 0
        status |= AudioUnitSetProperty(audioUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, kOutputBus, &flag, UInt32(MemoryLayout<UInt32>.size))
        
        
        var callbackStruct = AURenderCallbackStruct(inputProc: AudioUnitInputCallback, inputProcRefCon: unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
        if type.method == 1 || type.method == 0 {
            status |= AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, kInputBus, &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        } else {
            status |= AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, kOutputBus, &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        }
        if type.method == 1 || type.method == 2 {
            callbackStruct = AURenderCallbackStruct(inputProc: AudioUnitOutputCallback, inputProcRefCon: unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
            status |= AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, kOutputBus, &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        }
        
        
        flag = 0
        status |= AudioUnitSetProperty(audioUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, kInputBus, &flag, UInt32(MemoryLayout<UInt32>.size))
        
        status |= AudioUnitInitialize(audioUnit)
        
        if status != noErr {
            return
        }
    }
}
