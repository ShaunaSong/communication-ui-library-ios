//
//  RawOutgoingVideoSender.swift
//  ACSCallingTestAppALPHA
//
//  Copyright © 2022 Microsoft. All rights reserved.
//

import AzureCommunicationCalling
import OSLog

// Send frames to a call using RawOutgoingVideo API.
final class RawOutgoingVideoSender: NSObject {
    enum StreamKind {
        case screenShare
        case virtualVideo
    }

    let frameProducer: FrameProducerProtocol
    var rawOutgoingStream: RawOutgoingVideoStream!
    
    private var lock: NSRecursiveLock = NSRecursiveLock()

    private var timer: Timer?
    private var syncSema: DispatchSemaphore?
    private(set) weak var call: Call?
    private var running: Bool = false
    private let frameQueue: DispatchQueue = DispatchQueue(label: "org.microsoft.frame-sender")
    private let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "RawOutgoingVideoSender")
    private var options: RawOutgoingVideoStreamOptions!
    init(frameProducer: FrameProducerProtocol, streamKind: StreamKind) {
        self.frameProducer = frameProducer
        super.init()
        options = RawOutgoingVideoStreamOptions()
        options.videoFormats = frameProducer.videoFormats
        self.rawOutgoingStream = streamKind == .screenShare
            ? ScreenShareRawOutgoingVideoStream(videoStreamOptions: options)
            : VirtualRawOutgoingVideoStream(videoStreamOptions: options)
    }
    
    public func SendVideoFrame(videoFrameBuffer: RawVideoFrameBuffer) -> Void
    {
        if (rawOutgoingStream.videoStreamState == .started)
        {
            rawOutgoingStream.send(videoFrame: videoFrameBuffer) { error in
                
            }
        }
    }
  
    func startSending(to call: Call) {
        self.call = call
        self.startRunning()
        self.call?.startVideo(stream: rawOutgoingStream) { error in
            os_log("[OutgoingRawVideo] Start Raw video: %@", log: self.log, type: .debug, String(describing: error))
        }
    }
    
    func stopSending() {
        self.stopRunning()
        call?.stopVideo(stream: rawOutgoingStream) { error in
            os_log("[OutgoingRawVideo] Stop Raw video: %@", log: self.log, type: .debug, String(describing: error))
        }
    }
    
    private func startRunning() {
        lock.lock(); defer { lock.unlock() }

        self.running = true
        self.startFrameGenerator()
        /*if sender != nil {
        }*/
    }
    
    private func startFrameGenerator() {
        os_log("[OutgoingRawVideo] startFrameGenerator", log: log, type: .debug)
        /*guard let sender = self.sender else {
            return
        }*/

        let interval = TimeInterval((1 as Float) / 15)
        os_log("[OutgoingRawVideo] startFrameGenerator at %d FPS", log: log, type: .debug, sender.videoFormat.framesPerSecond)
        frameQueue.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self = self, let sender = self.sender else {
                    return
                }
                guard self.frameProducer.isReady else {
                    return
                }

                let planeData = self.frameProducer.nextFrame(for: sender.videoFormat)
            }
            RunLoop.current.run()
            self?.timer?.fire()
        }
    }

    private func stopRunning() {
        lock.lock(); defer { lock.unlock() }

        running = false
        stopFrameGeneration()
    }

    private func stopFrameGeneration() {
        os_log("[OutgoingRawVideo] stopFrameGeneration", log: log, type: .debug)

        lock.lock(); defer { lock.unlock() }
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        os_log("[OutgoingRawVideo] RawOutgoingVideoSender deinit", log: log, type: .debug)
        timer?.invalidate()
        timer = nil
    }
}

extension RawOutgoingVideoSender: RawOutgoingVideoStreamOptionsDelegate {
    func rawOutgoingVideoStreamOptions(_ rawOutgoingVideoStreamOptions: RawOutgoingVideoStreamOptions, didChangeOutgoingVideoStreamState args: OutgoingVideoStreamStateChangedEventArgs) {
        os_log("[OutgoingRawVideo] rawOutgoingVideoStreamOptions state: %@", log: log, type: .debug, Utilities.description(for: args.outgoingVideoStreamState))
    }

    func rawOutgoingVideoStreamOptions(_ rawOutgoingVideoStreamOptions: RawOutgoingVideoStreamOptions,
                                       didChangeVideoFrameSender args: VideoFrameSenderChangedEventArgs) {
        os_log("[OutgoingRawVideo] onVideoFrameSenderChanged", log: log, type: .debug)
        if running {
            stopRunning()
            sender = args.videoFrameSender
            startRunning()
        } else {
            sender = args.videoFrameSender
        }
    }
}
