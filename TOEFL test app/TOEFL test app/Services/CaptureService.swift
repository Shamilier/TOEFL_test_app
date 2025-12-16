import AVFoundation
import ScreenCaptureKit
import OSLog

enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case streamUnavailable
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Screen recording permission was denied."
        case .streamUnavailable: return "Unable to start screen capture stream."
        case .noDisplay: return "No display was selected."
        }
    }
}

protocol CaptureServiceDelegate: AnyObject {
    func captureService(_ service: CaptureService, didOutput sampleBuffer: CMSampleBuffer, type: SCStreamOutputType)
    func captureService(_ service: CaptureService, didStopWith error: Error?)
}

final class CaptureService: NSObject, SCStreamOutput {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "capture")
    weak var delegate: CaptureServiceDelegate?

    private var stream: SCStream?
    private var filter: SCContentFilter?
    private var configuration = SCStreamConfiguration()
    private var captureQueue = DispatchQueue(label: "com.backuprecorder.capture")

    @MainActor
    func requestPermissionIfNeeded() async throws {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            logger.error("Permission check failed: \(error.localizedDescription)")
            throw CaptureError.permissionDenied
        }
    }

    func availableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.displays
    }

    func setTarget(display: SCDisplay) {
        filter = SCContentFilter(display: display, excludingWindows: [])
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = false
    }

    func start() async throws {
        guard let filter else { throw CaptureError.noDisplay }
        if stream != nil { try await stop() }

        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)

        do {
            try await stream?.startCapture()
            logger.log("Screen capture started")
        } catch {
            logger.error("Failed to start capture: \(error.localizedDescription)")
            throw CaptureError.streamUnavailable
        }
    }

    func stop() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
        try? stream.removeStreamOutput(self, type: .audio)
        self.stream = nil
        logger.log("Screen capture stopped")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        delegate?.captureService(self, didOutput: sampleBuffer, type: outputType)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Stream stopped with error: \(error.localizedDescription)")
        delegate?.captureService(self, didStopWith: error)
    }
}
