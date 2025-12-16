import Foundation
import os

final class LogStore {
    static let shared = LogStore()
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "filelog")
    private let fileHandle: FileHandle?
    let logURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("BackupRecorder.log")

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logURL)
        try? fileHandle?.seekToEnd()
    }

    func write(_ message: String) {
        logger.log("\(message, privacy: .public)")
        guard let data = ("\(Date()) - \(message)\n").data(using: .utf8) else { return }
        try? fileHandle?.write(contentsOf: data)
    }
}
