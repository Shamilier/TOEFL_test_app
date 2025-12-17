import Foundation
import ScreenCaptureKit
import OSLog
import AppKit

final class StreamingClient {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "streaming")
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.backuprecorder.streaming")
    private let endpoint = URL(string: "https://example.com/stream")!
    private var isActive = false
    private let ciContext = CIContext()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func startStreaming() {
        isActive = true
        logger.log("Streaming session started for endpoint: \(self.endpoint.absoluteString)")
    }

    func stopStreaming() {
        isActive = false
        logger.log("Streaming session stopped")
    }

    func push(sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard isActive else { return }
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        queue.async { [weak self] in
            guard let self else { return }
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let data = bitmap.representation(using: .jpeg,
                                                   properties: [.compressionFactor: 0.6]) else { return }

            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return }

            var request = URLRequest(url: self.endpoint)
            request.httpMethod = "POST"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

            let task = self.session.uploadTask(with: request, from: data)
            task.resume()
        }
    }
}
