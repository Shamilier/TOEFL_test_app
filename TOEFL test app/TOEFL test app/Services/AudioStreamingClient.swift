import Foundation
import AVFoundation
import ScreenCaptureKit
import OSLog

final class AudioStreamingClient {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "audio_streaming")
    private let queue = DispatchQueue(label: "com.backuprecorder.audio.streaming")

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private let endpoint = URL(string: "wss://disciplaner.online/audio")!

    private var webSocketTask: URLSessionWebSocketTask?
    private var isActive = false
    private var isConnected = false

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.logger.log("Starting audio streaming")
            self.isActive = true
            self.connectIfNeeded()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.logger.log("Stopping audio streaming")
            self.isActive = false
            self.isConnected = false
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
        }
    }

    func push(sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isActive, self.isConnected else { return }
            guard let data = self.convert(sampleBuffer: sampleBuffer) else { return }
            self.send(data: data)
        }
    }

    private func connectIfNeeded() {
        guard isActive, webSocketTask == nil else { return }

        let task = session.webSocketTask(with: endpoint)
        webSocketTask = task
        task.resume()
        isConnected = true
        logger.log("Audio WebSocket connecting to: \(self.endpoint.absoluteString)")
        listen()
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                self.handleDisconnect()
            case .success:
                self.listen()
            }
        }
    }

    private func handleDisconnect() {
        isConnected = false
        webSocketTask = nil
        guard isActive else { return }
        logger.log("WebSocket disconnected, scheduling reconnect")
        queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.connectIfNeeded()
        }
    }

    private func send(data: Data) {
        guard let task = webSocketTask else { return }

        let maxChunkSize = 64 * 1024
        var offset = 0

        while offset < data.count {
            let end = min(offset + maxChunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            offset = end

            task.send(.data(chunk)) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.logger.error("Failed to send audio chunk: \(error.localizedDescription)")
                    self.handleDisconnect()
                }
            }
        }
    }

    private func convert(sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Audio,
              let inputFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return nil }

        let bufferList = AudioBufferList.allocate(maximumBuffers: Int(inputFormat.channelCount))
        defer { bufferList.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList.unsafeMutablePointer,
            bufferListSize: bufferList.sizeInBytes,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, blockBuffer != nil else {
            logger.error("Failed to get audio buffer list: \(status)")
            return nil
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            logger.error("Failed to allocate input PCM buffer")
            return nil
        }
        inputBuffer.frameLength = frameCount

        let sourcePointers = UnsafeMutableAudioBufferListPointer(bufferList.unsafeMutablePointer)
        let destinationPointers = UnsafeMutableAudioBufferListPointer(inputBuffer.mutableAudioBufferList)

        for index in 0..<destinationPointers.count {
            let source = sourcePointers[index]
            let destination = destinationPointers[index]
            let byteCount = min(Int(source.mDataByteSize), Int(destination.mDataByteSize))
            if let sourceData = source.mData, let destinationData = destination.mData, byteCount > 0 {
                memcpy(destinationData, sourceData, byteCount)
                destination.mDataByteSize = UInt32(byteCount)
            }
        }

        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16_000,
                                               channels: 1,
                                               interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            logger.error("Failed to create audio converter")
            return nil
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            logger.error("Failed to allocate output PCM buffer")
            return nil
        }

        var convertError: NSError?
        let success = converter.convert(to: outputBuffer, error: &convertError) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let convertError {
            logger.error("Audio conversion failed: \(convertError.localizedDescription)")
            return nil
        }

        guard success, let channelData = outputBuffer.int16ChannelData else { return nil }
        let byteCount = Int(outputBuffer.frameLength) * Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
        return Data(bytes: channelData[0], count: byteCount)
    }
}
