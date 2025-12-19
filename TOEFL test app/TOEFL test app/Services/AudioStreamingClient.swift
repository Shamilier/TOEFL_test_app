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
              CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Audio else {
            return nil
        }
        
        // ✅ init НЕ optional → guard let тут не нужен
        let inputFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return nil }
        
        // ✅ Выделяем AudioBufferList вручную (flexible array)
        let maxBuffers = max(1, Int(inputFormat.channelCount))
        let ablSize = MemoryLayout<AudioBufferList>.size + (maxBuffers - 1) * MemoryLayout<AudioBuffer>.size
        let ablRaw = UnsafeMutableRawPointer.allocate(
            byteCount: ablSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { ablRaw.deallocate() }
        
        let ablPointer = ablRaw.bindMemory(to: AudioBufferList.self, capacity: 1)
        ablPointer.pointee.mNumberBuffers = UInt32(maxBuffers)
        
        // Инициализируем буферы нулями
        let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
        for i in 0..<abl.count {
            abl[i].mNumberChannels = 0
            abl[i].mDataByteSize = 0
            abl[i].mData = nil
        }
        
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPointer,
            bufferListSize: ablSize,
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
        
        // Копируем данные из ABL в AVAudioPCMBuffer
        let src = UnsafeMutableAudioBufferListPointer(ablPointer)
        let dst = UnsafeMutableAudioBufferListPointer(inputBuffer.mutableAudioBufferList)
        let copyCount = min(src.count, dst.count)
        
        for i in 0..<copyCount {
            let s = src[i]
            var d = dst[i]
            
            let byteCount = min(Int(s.mDataByteSize), Int(d.mDataByteSize))
            if let sData = s.mData, let dData = d.mData, byteCount > 0 {
                memcpy(dData, sData, byteCount)
                d.mDataByteSize = UInt32(byteCount)
            }
            dst[i] = d
        }
        
        // ✅ Целевой формат: 16kHz mono Int16 interleaved
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16_000,
                                               channels: 1,
                                               interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            logger.error("Failed to create audio converter")
            return nil
        }
        
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 32
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            logger.error("Failed to allocate output PCM buffer")
            return nil
        }
        
        var convertError: NSError?
        var didProvideInput = false
        
        // ✅ convert(...) возвращает AVAudioConverterOutputStatus, не Bool
        let outStatus = converter.convert(to: outputBuffer, error: &convertError) { _, out in
            if didProvideInput {
                out.pointee = .endOfStream
                return nil
            } else {
                didProvideInput = true
                out.pointee = .haveData
                return inputBuffer
            }
        }
        
        if let convertError {
            logger.error("Audio conversion failed: \(convertError.localizedDescription)")
            return nil
        }
        
        guard outStatus != .error else {
            logger.error("Audio conversion returned .error")
            return nil
        }
        
        // ✅ Для interleaved надёжнее брать через audioBufferList
        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return nil }
        
        return Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
    }
}
