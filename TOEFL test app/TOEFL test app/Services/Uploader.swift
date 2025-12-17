import Foundation
import OSLog
import Combine

final class Uploader: NSObject, URLSessionTaskDelegate, ObservableObject {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "uploader")
    private var session: URLSession!

    @Published var lastUploadStatus: String = "Idle"

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.backuprecorder.upload")
        config.waitsForConnectivity = true
        config.allowsCellularAccess = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func uploadIfNeeded(file url: URL, endpoint: String, enabled: Bool) {
        guard enabled else { return }
        guard let requestURL = URL(string: endpoint) else {
            lastUploadStatus = "Invalid endpoint"
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")

        let task = session.uploadTask(with: request, fromFile: url)
        lastUploadStatus = "Uploading \(url.lastPathComponent)"
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.lastUploadStatus = "Failed: \(error.localizedDescription)"
                self.logger.error("Upload failed: \(error.localizedDescription)")
            } else {
                self.lastUploadStatus = "Uploaded \(task.originalRequest?.url?.absoluteString ?? "endpoint")"
            }
        }
    }
}
