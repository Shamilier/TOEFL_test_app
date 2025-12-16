import AVFoundation
import OSLog

final class RecordingWriter {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "writer")
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private(set) var outputURL: URL?

    func startWriting(to url: URL, width: Int, height: Int) throws {
        outputURL = url
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 128_000
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        guard let assetWriter, let videoInput, let audioInput else {
            throw NSError(domain: "com.backuprecorder.app", code: -1, userInfo: [NSLocalizedDescriptionKey: "Writer not configured"])
        }

        if assetWriter.canAdd(videoInput) { assetWriter.add(videoInput) }
        if assetWriter.canAdd(audioInput) { assetWriter.add(audioInput) }

        assetWriter.startWriting()
    }

    func append(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard let assetWriter, assetWriter.status != .failed else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if assetWriter.status == .unknown {
            assetWriter.startSession(atSourceTime: presentationTime)
        }

        switch type {
        case .screen:
            if let videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            if let audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        @unknown default:
            break
        }
    }

    func finish() async throws {
        guard let assetWriter else { return }
        await withCheckedContinuation { continuation in
            audioInput?.markAsFinished()
            videoInput?.markAsFinished()
            assetWriter.finishWriting {
                self.logger.log("Finished writing: \(self.outputURL?.lastPathComponent ?? "unknown")")
                continuation.resume()
            }
        }
        self.assetWriter = nil
        self.videoInput = nil
        self.audioInput = nil
    }
}
