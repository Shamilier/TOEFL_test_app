import Foundation
import OSLog
import ScreenCaptureKit


final class SegmentRotator {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "rotator")
    private let baseDirectory: URL
    private let segmentDuration: TimeInterval
    private let diskQuota: Int64
    private var currentWriter: RecordingWriter?
    private var segmentStartDate: Date?
    private var width: Int = 0
    private var height: Int = 0
    var onSegmentFinished: ((URL) -> Void)?

    init(baseDirectory: URL, segmentDuration: TimeInterval, diskQuota: Int64) {
        self.baseDirectory = baseDirectory
        self.segmentDuration = segmentDuration
        self.diskQuota = diskQuota
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func startNewSegment(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        let url = segmentURL()
        let writer = RecordingWriter()
        try writer.startWriting(to: url, width: width, height: height)
        currentWriter = writer
        segmentStartDate = Date()
        rotateIfNeeded()
    }

    func append(_ buffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard let writer = currentWriter else { return }
        writer.append(buffer, type: type)
        if let start = segmentStartDate, Date().timeIntervalSince(start) > segmentDuration {
            Task { await finishCurrentSegment() }
        }
    }

    @discardableResult
    func finishCurrentSegment() async -> URL? {
        guard let writer = currentWriter else { return nil }
        let url = writer.outputURL
        try? await writer.finish()
        currentWriter = nil
        segmentStartDate = nil
        if let url { onSegmentFinished?(url) }
        if width > 0 && height > 0 {
            try? startNewSegment(width: width, height: height)
        }
        enforceDiskQuota()
        return url
    }

    private func segmentURL() -> URL {
        let formatter = ISO8601DateFormatter()
        let filename = "segment_\(formatter.string(from: Date())).mp4"
        return baseDirectory.appendingPathComponent(filename)
    }

    private func enforceDiskQuota() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles)) ?? []
        let sorted = urls.compactMap { url -> (URL, Int64, Date)? in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values?.fileSize, let date = values?.contentModificationDate else { return nil }
            return (url, Int64(size), date)
        }.sorted { $0.2 < $1.2 }

        var totalSize = sorted.reduce(Int64(0)) { $0 + $1.1 }
        for entry in sorted where totalSize > diskQuota {
            do {
                try FileManager.default.removeItem(at: entry.0)
                totalSize -= entry.1
                logger.log("Removed old segment to honor disk quota: \(entry.0.lastPathComponent)")
            } catch {
                logger.error("Failed removing segment: \(error.localizedDescription)")
            }
        }
    }

    private func rotateIfNeeded() {
        enforceDiskQuota()
    }
}
