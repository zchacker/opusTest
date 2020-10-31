//
//  ViewController.swift
//  lightVoIP
//
//  Created by Ahmed Adm on 10/03/1442 AH.
//  Copyright © 1442 Ahmed Adm. All rights reserved.
//

import UIKit
import SwiftSocket
import AudioToolbox
import AVFoundation

// MARK: for speaker
func QueueInputCallback(inUserData: UnsafeMutableRawPointer?,inAQ: AudioQueueRef,inBuffer: AudioQueueBufferRef,inStartTime: UnsafePointer<AudioTimeStamp>,inNumberPacketDescriptions: UInt32,inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?) {
    
    
    let audioService = unsafeBitCast(inUserData!, to: ViewController.self)
    //let audioData: NSMutableData = NSMutableData(length: Int(inBuffer.pointee.mAudioDataByteSize))!
    //let audioData:NSData = NSData(bytes: inBuffer.pointee.mAudioData.advanced(by: 0), length: Int(inBuffer.pointee.mAudioDataBytesCapacity))
    let audioData:Data = Data(bytes: inBuffer.pointee.mAudioData.advanced(by: 0), count: Int(inBuffer.pointee.mAudioDataByteSize))
    
    //memcpy(audioData.mutableBytes.advanced(by: 0) ,inBuffer.pointee.mAudioData.advanced(by: 0) ,Int(inBuffer.pointee.mAudioDataByteSize))
    //print("inNumberPacketDescriptions \(inNumberPacketDescriptions), \(Int(inBuffer.pointee.mAudioDataByteSize))")
    
    //audioService.ringBufferEncodedAudio.write(audioData) // <== send data
    
    if audioService.isStreaming{
        let encodedData = OpusSwiftPort.shared.encodeData(audioData)// as! Data)
         //print("encoded: \(encodedData!.count)")
         if encodedData != nil{
             audioService.sendAudioPacket(packet: encodedData!)
         }
    }

    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0 , nil)
}

// MARK: for player
func QueueOutputCallback(inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef) {
    
    let audioService = unsafeBitCast(inUserData!, to: ViewController.self)
    var data = audioService.ringBufferDecodedAudio.read()
    
    if data != nil && audioService.mutted == false {
        memcpy(inBuffer.pointee.mAudioData , data!.mutableBytes.advanced(by: 0) , data!.length)
        inBuffer.pointee.mAudioDataByteSize = UInt32(data!.length)
        inBuffer.pointee.mPacketDescriptionCount = UInt32(data!.length) / 2
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
        //print("has audio \(data!.length)")
    } else {
        memset(inBuffer.pointee.mAudioData, 0x00, 5760)
        inBuffer.pointee.mAudioDataByteSize = 5760
        inBuffer.pointee.mPacketDescriptionCount = 5760 / 2
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
        //print("No audio")
    }
    
    data = nil
    
}

class ViewController: UIViewController {

    // 51.91.18.8 <-- remote
    // 192.168.100.191 <-- local
    
    let client = UDPClient(address: "51.91.18.8", port: 49000)
    var mutted:Bool = false
    var ringBufferDecodedAudio:RingBuffer = RingBuffer<NSMutableData>(size: 120)
    var ringBufferEncodedAudio:RingBuffer = RingBuffer<Data>(size: 120)
    
    // audio queue object
    var  audioQueueObject :AudioQueueRef?
    var  micQueueObject :AudioQueueRef?
    var  audioFormat = AudioStreamBasicDescription()
    let audioSession = AVAudioSession.sharedInstance()
    
    /**
    * Audio frame size
    * It is divided by time. When calling, you must use the audio data of exactly one frame (multiple of 2.5ms: 2.5, 5, 10, 20, 40, 60ms).
    * Fs/ms   2.5     5       10      20      40      60
    * 8kHz    20      40      80      160     320     480
    * 16kHz   40      80      160     320     640     960
    * 24KHz   60      120     240     480     960     1440
    * 48kHz   120     240     480     960     1920    2880
    */
    // audio settings
    let sample_rate:opus_int32 = 48000
    let channel:Int32 = 1
    let frameSize:opus_int32 = 2880 // 60 120 240 480 960 1440
    let encodeBlockSize:opus_int32 = 280//
    
    @IBOutlet weak var streaming:UIButton!
    var isStreaming:Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        // this example form
        // MARK: https://stackoverflow.com/questions/41082760/extracting-segments-of-data-object-in-swift-3
        /*var data = Data(bytes: [24, 163, 209, 194, 255, 1, 184, 230, 37, 208, 140, 201, 6, 0, 64, 0, 7, 98, 108, 117, 42, 63, 78, 200, 3, 34, 36])
        var copyData = data
        
        
        // First extraction
        let first = extract_length(from: &data)
        print(first!) // Prints 4 bytes
        print(data) // Prints 23 bytes
        print(copyData)*/
        
        let testData = Data("0".utf8)
        let result = self.client.send(data: testData)
        
        print("sent")
        print(result)
        
        self.open_codec()
        
        /*
        DispatchQueue.global(qos: .background).async {
            while true{
                let audioData = self.ringBufferEncodedAudio.read()
                if audioData != nil{
                    let encodedData = OpusSwiftPort.shared.encodeData(audioData!)//! as Data)
                    if encodedData != nil{
                        if self.isStreaming{
                            self.sendAudioPacket(packet: encodedData!)
                        }
                    }
                }else{
                    usleep(50000)
                }
            }
        }*/
        
        // background thread for recive udp packets
        DispatchQueue.global(qos: .background).async {
            while true{
                
                let message = self.client.recv(65535)
                //print("wait")
                //var audioData:Data = Data(capacity: message.0!.count)
                //var data = NSData(bytes: message.0!, length: message.0!.count)
                
                var full_buffer = Data(bytes: message.0!, count: message.0!.count)// this is full data
                self.extract_length(from: &full_buffer)
                                
                //var copy_from_buffer = full_buffer
                /*var lengthBuffer = Data(count: MemoryLayout<UInt32>.size)
                lengthBuffer.withUnsafeBytes { (p: UnsafePointer<UInt32>) in
                    message.0!
                }
                print(lengthBuffer)*/
                
                /*let lengthBuffer = self.extract_length(from: &full_buffer)
                let dd = lengthBuffer!.withUnsafeBytes { [unowned self] (p: UnsafePointer<UInt32>) in
                    Int(UInt32(bigEndian: p.pointee))
                }*/

                // decode the chunk of audio and buffer it in ring buffer
                if let decodedDataChunk = OpusSwiftPort.shared.decodeData(full_buffer) { // this after decode it give me a Data object holding bytes
                    if decodedDataChunk.count > 0 {
                        self.ringBufferDecodedAudio.write( NSMutableData(data: decodedDataChunk) )// this is old one
                    }
                }
                
                /*var data = NSData(bytes: message.0!, length: message.0!.count)
                var str = String(decoding: data as Data, as: UTF8.self)
                print("count \(data.count)")
                print("get message: \(str)")*/
            }
        }
        
    }
    
    @IBAction func stramign_toggle(_ sender:Any){
        if isStreaming {
            isStreaming = false
            streaming.setTitle("Start Streaming", for: .normal)
        }else{
            isStreaming = true
            streaming.setTitle("Stop Streaming", for: .normal)
        }
    }
    
    func extract_length(from data: inout Data) -> Data? {
        guard data.count > 0 else {
            return nil
        }

        // Define the length of data to return
        let length = Int.init(data[0])

        // Create a range based on the length of data to return
        //let range = Range(0..<length)
        let range = 0..<4
        
        // Get a new copy of data
        let subData = data.subdata(in: range)

        // Mutate data
        data.removeSubrange(range)

        // Return the new copy of data
        return subData
    }
    
    func extract(from data: inout Data) -> Data? {
        guard data.count > 0 else {
            return nil
        }

        // Define the length of data to return
        let length = Int.init(data[0])

        // Create a range based on the length of data to return
        //let range = Range(0..<length)
        let range = 4..<length
        
        // Get a new copy of data
        let subData = data.subdata(in: range)

        // Mutate data
        data.removeSubrange(range)

        // Return the new copy of data
        return subData
    }
    
    func setup_format(){
        audioFormat.mSampleRate       = 48000.0
        audioFormat.mFormatID         = kAudioFormatLinearPCM
        audioFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        audioFormat.mFramesPerPacket  = 1
        audioFormat.mChannelsPerFrame = 1
        audioFormat.mBitsPerChannel   = 16
        audioFormat.mBytesPerFrame    = (audioFormat.mBitsPerChannel / 8) * audioFormat.mChannelsPerFrame
        audioFormat.mBytesPerPacket   = audioFormat.mBytesPerFrame
        audioFormat.mReserved = 0
    }
    
    // MARK: open mic for streaming
    func oepnQueueServiceRecorder(){
        var audioFormat = self.audioFormat
        AudioQueueNewInput(&audioFormat,
                           QueueInputCallback,
                           unsafeBitCast(self, to: UnsafeMutableRawPointer.self),
                           CFRunLoopGetCurrent(),
                           CFRunLoopMode.commonModes.rawValue,
                           0,
                           &micQueueObject)
               
        var buffers = Array<AudioQueueBufferRef?>(repeating: nil, count: 1)
        let bufferByteSize: UInt32 = UInt32(frameSize) * audioFormat.mBytesPerPacket //numPacketsToWrite * audioFormat.mBytesPerPacket
        
        for bufferIndex in 0 ..< buffers.count {
            AudioQueueAllocateBuffer(micQueueObject!, bufferByteSize, &buffers[bufferIndex])
            AudioQueueEnqueueBuffer(micQueueObject!, buffers[bufferIndex]!, 0, nil)
        }
        
        let err: OSStatus = AudioQueueStart(micQueueObject!, nil)
        print("err: \(err)")
    }

    func openQueueServicePlayer(){
        var audioFormat = self.audioFormat
        AudioQueueNewOutput(&audioFormat,
                            QueueOutputCallback,
                            unsafeBitCast(self, to: UnsafeMutableRawPointer.self),
                            CFRunLoopGetCurrent(),
                            CFRunLoopMode.commonModes.rawValue,
                            0,
                            &audioQueueObject)
               
        var buffers = Array<AudioQueueBufferRef?>(repeating: nil, count: 3)
        let bufferByteSize: UInt32 = UInt32(frameSize) * audioFormat.mBytesPerPacket
        
        for bufferIndex in 0 ..< buffers.count {
            AudioQueueAllocateBuffer( audioQueueObject!, bufferByteSize, &buffers[bufferIndex])
            QueueOutputCallback( inUserData: unsafeBitCast(self , to: UnsafeMutableRawPointer.self) , inAQ: audioQueueObject!, inBuffer: buffers[bufferIndex]! )
        }
        
        let err: OSStatus = AudioQueueStart(audioQueueObject!, nil)
        print("err: \(err)")
    }

    func open_codec(){
        
        // open decoder
        OpusSwiftPort.shared.initialize(sampleRate: self.sample_rate, numberOfChannels: self.channel, frameSize: self.frameSize, encodeBlockSize: self.encodeBlockSize)

        do {

            try self.audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            try self.audioSession.setCategory( .playAndRecord , mode: .default , options: [.defaultToSpeaker , .allowBluetooth , .mixWithOthers])
            try self.audioSession.setPreferredIOBufferDuration(0.02)
            
            try self.audioSession.setPreferredSampleRate(44800.0)
                                    
            self.audioSession.requestRecordPermission(){ allowed in
                if allowed{
                    print("recod is ok")
                }else{
                    print("record is not ok")
                }
            }

            try self.audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            
            try self.audioSession.setPreferredOutputNumberOfChannels(1)
            try self.audioSession.setPreferredInputNumberOfChannels(1)
                        
            print("Prefered output channel: \(self.audioSession.outputNumberOfChannels)")
            print("ioBufferDuration : \(self.audioSession.ioBufferDuration)")
            print("preferredIOBufferDuration : \(self.audioSession.preferredIOBufferDuration)")
            print("Prefered SampleRate: \(self.audioSession.preferredSampleRate)")
            
            // MARK: this is new Player
            self.setup_format()
            self.openQueueServicePlayer()
            self.oepnQueueServiceRecorder()
            
            print("audio session category configured. and audio queue service for mic and speaker are started!")
            
        } catch  {
            print("Failed to set audio session category. \(error)")
        }
    }
    
    func sendAudioPacket(packet: Data){
        let buf: [UInt8]    = Array(packet)
        let size: [UInt8]   = intToByteArray(number: buf.count)
        
        let msg: [UInt8]    = size + buf
        //print("sent: \(buf.count)")
        self.client.send(data: msg)
    }
    
    func intToByteArray(number:Int) -> [UInt8]{
        var result:[UInt8] = Array()
        var _number:Int = number
        let mask_8Bits = 0xFF
        var c = 0
        
        // MemoryLayout<Int>.size
        // .reversed()
        
        for i in ( 0 ..< 4).reversed(){
            
            // at: 0 -> insert at the beginning of the array
            result.insert( UInt8( _number & mask_8Bits ) , at:0)
            _number >>= 8 // shift 8 times from left to right
        }
        
        return result
    }


}

