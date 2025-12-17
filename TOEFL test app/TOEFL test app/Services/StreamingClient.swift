import Foundation
import ScreenCaptureKit
import OSLog
import AppKit
import CoreImage
import CoreMedia

final class StreamingClient {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "streaming")
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.backuprecorder.streaming")

    private let endpoint = URL(string: "https://disciplaner.online/ingest")!

    private var isActive = false
    private let ciContext = CIContext()

    // throttling (чтобы не слать 30fps POST-ами)
    private var lastSent: CFAbsoluteTime = 0
    private let minInterval: Double = 0.2 // 5 fps

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

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSent >= minInterval else { return }
        lastSent = now

        // ✅ делаем копию sampleBuffer, чтобы безопасно использовать в async
        var copied: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault,
                                              sampleBuffer: sampleBuffer,
                                              sampleBufferOut: &copied)
        guard status == noErr, let sb = copied else {
            logger.error("CMSampleBufferCreateCopy failed: \(status)")
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sb) else { return }

            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let data = bitmap.representation(using: .jpeg,
                                                   properties: [.compressionFactor: 0.6]) else { return }

            var request = URLRequest(url: self.endpoint)
            request.httpMethod = "POST"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

            let task = self.session.uploadTask(with: request, from: data) { [weak self] _, response, error in
                guard let self else { return }

                if let error {
                    self.logger.error("Upload failed: \(error.localizedDescription)")
                    return
                }
                if let http = response as? HTTPURLResponse {
                    self.logger.log("Upload status: \(http.statusCode)")
                } else {
                    self.logger.log("Upload finished (no HTTP response)")
                }
            }
            task.resume()
        }
    }
}
