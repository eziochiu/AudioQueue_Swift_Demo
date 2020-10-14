//
//  AudioFileHandler.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/12.
//

import UIKit
import AudioToolbox

class AudioFileHandler: NSObject {
    static let kModuleName = "Audio File";
    /// AudioFileID
    var recordFile: AudioFileID?
    /// 当前recordFile的packet
    var recordCurrentPacket: Int64 = 0
    /// recordFile路径
    var recordFilePath: String?
    
    /// playFile AudioFileID
    var playFile: AudioFileID?
    /// 当前recordFile的packet
    var playCurrentPacket: Int64 = 0
    /// recordFile路径
    var playFilePath: CFURL?
    
    
    
    static let shared = AudioFileHandler()
    
    private override init() {
        
    }
    
    // MARK: - public method
    func startVoiceRecordByAudioUnitByAudioConverter(audioConverter: AudioConverterRef, isNeedMagicCookie: Bool, audioDesc: AudioStreamBasicDescription) {
        recordFilePath = createFilePath()
        recordFile = createAudioFileWithFilePath(filePath: recordFilePath!, audioDesc: audioDesc)
        if isNeedMagicCookie && recordFile != nil {
            copyEncoderCookieToFileByAudioConverter(audioConverter: audioConverter, inFile: recordFile!)
        }
    }
    
    func stopVoiceRecordAudioConverter(audioConverter: AudioConverterRef, isNeedMagicCookie: Bool) {
        if isNeedMagicCookie {
            copyEncoderCookieToFileByAudioConverter(audioConverter: audioConverter, inFile: recordFile!)
        }
        AudioFileClose(recordFile!)
        recordCurrentPacket = 0
    }
    
    func startVoiceRecordByAudioQueue(audioQueue: AudioQueueRef, isNeedMagicCookie: Bool, audioDesc: AudioStreamBasicDescription) {
        recordFilePath = createFilePath()
        recordFile = createAudioFileWithFilePath(filePath: recordFilePath!, audioDesc: audioDesc)
        if isNeedMagicCookie && recordFile != nil {
            copyEncoderCookieToFileByAudioQueue(queue: audioQueue, file: recordFile!)
        }
    }
    
    func stopVoiceRecordByAudioQueue(audioQueue: AudioQueueRef, isNeedMagicCookie: Bool) {
        if isNeedMagicCookie {
            copyEncoderCookieToFileByAudioQueue(queue: audioQueue, file: recordFile!)
        }
        AudioFileClose(recordFile!)
        recordCurrentPacket = 0
    }
    
    func writeFileWithInNumBytes(inNumBytes: UInt32, ioNumPackets: UInt32, inBuffer: UnsafeRawPointer, inPacketDesc: UnsafePointer<AudioStreamPacketDescription>?) {
        var ioNumPackets = ioNumPackets
        if recordFile == nil {
            return
        }
        let status = AudioFileWritePackets(recordFile!, false, inNumBytes, inPacketDesc, recordCurrentPacket, &ioNumPackets, inBuffer)
        if status == noErr {
            print("\(AudioFileHandler.kModuleName): - write file status = scuess\n")
            recordCurrentPacket += Int64(ioNumPackets) // 用于记录起始位置
        } else {
            print("\(AudioFileHandler.kModuleName): - write file status = \(status) \n")
        }
    }
    
    func configurePlayFilePath() -> AudioStreamBasicDescription? {
        var filePathArray = Array(createFilePath().utf8)
        let filePathSize = createFilePath().count
        let audioFileUrl = CFURLCreateFromFileSystemRepresentation(nil, &filePathArray, filePathSize, false)
        let  status = AudioFileOpenURL(audioFileUrl!, .readPermission, kAudioFileCAFType, &self.playFile)
        if status == noErr{
            print("打开URL成功")
        }
        var descSize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        var dataFormat = AudioStreamBasicDescription()
        if AudioFileGetProperty(self.playFile!, kAudioFilePropertyDataFormat, &descSize, &dataFormat) == noErr {
            return dataFormat
        } else {
            return nil
        }
    }
    
    // MARK: - private method
    fileprivate func createFilePath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        _ = dateFormatter.string(from: Date())
        let searchPaths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentPath = (searchPaths.first! as NSString).appendingPathComponent("Voice")
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: documentPath) == false {//没有先创建路径
            try? fileManager.createDirectory(atPath: documentPath, withIntermediateDirectories: true, attributes: nil)
        }
//        let fullFileName = "\(date).caf"
        let fullFileName = "test.caf"
        let filePath = (documentPath as NSString).appendingPathComponent(fullFileName)
        return filePath
    }
    
    fileprivate func createAudioFileWithFilePath(filePath: String, audioDesc: AudioStreamBasicDescription) -> AudioFileID? {
        let url = CFURLCreateWithString(kCFAllocatorDefault, filePath as CFString, nil)!
        var audioFile: AudioFileID?
        var audioDescNew = audioDesc
        let status = AudioFileCreateWithURL(url, kAudioFileCAFType, &audioDescNew, .eraseFile, &audioFile)
        if status == noErr {
            print("AudioFileCreateWithURL successful")
        }
        return audioFile
    }
    
    fileprivate func copyEncoderCookieToFileByAudioQueue(queue: AudioQueueRef, file: AudioFileID) {
        var result = noErr
        var cookieSize: UInt32 = 0
        result = AudioQueueGetPropertySize(queue, kAudioQueueProperty_MagicCookie, &cookieSize)
        if result == noErr {
            guard let magicCookie = malloc(Int(cookieSize)) else {
                print("get Magic cookie successful")
                return
            }
            result = AudioQueueGetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie, &cookieSize)
            if result == noErr {
                result = AudioQueueSetProperty(queue, kAudioFilePropertyMagicCookieData, magicCookie, cookieSize)
                result == noErr ? print("Magic cookie successful") : print("Magic cookie failed")
            }
            free (magicCookie)
        } else {
            print("Magic cookie: get size failed")
        }
    }
    
    fileprivate func copyEncoderCookieToFileByAudioConverter(audioConverter: AudioConverterRef, inFile: AudioFileID) {
        var cookieSize: UInt32 = 0
        var status = AudioConverterGetPropertyInfo(audioConverter, kAudioConverterCompressionMagicCookie, &cookieSize, nil)
        if status == noErr && cookieSize != 0 {
            guard let cookie = malloc(Int(cookieSize) * MemoryLayout<Int8>.size) else {
                print("get Magic cookie successful")
                return
            }
            status = AudioConverterGetProperty(audioConverter, kAudioConverterCompressionMagicCookie, &cookieSize, cookie)
            if status == noErr {
                status = AudioFileSetProperty(inFile, kAudioFilePropertyMagicCookieData, cookieSize, cookie)
                if status == noErr {
                    var willEatTheCookie: UInt32 = 0
                    status = AudioFileGetPropertyInfo(inFile, kAudioFilePropertyMagicCookieData, nil, &willEatTheCookie)
                }
            }
            free(cookie)
        }
    }
}
