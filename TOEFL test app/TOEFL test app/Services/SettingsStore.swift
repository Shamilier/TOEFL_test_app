import Foundation
import os

struct RecordingSettings: Codable, Equatable {
    var autoBackupEnabled: Bool
    var uploadEnabled: Bool
    var uploadEndpoint: String
    var segmentDuration: TimeInterval
    var diskQuotaBytes: Int64

    static let `default` = RecordingSettings(
        autoBackupEnabled: false,
        uploadEnabled: false,
        uploadEndpoint: "",
        segmentDuration: 300,
        diskQuotaBytes: 5 * 1024 * 1024 * 1024 // 5 GB by default
    )
}

final class SettingsStore: ObservableObject {
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "settings")
    private let storageKey = "backup.recorder.settings"

    @Published var settings: RecordingSettings {
        didSet {
            persist()
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(RecordingSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to persist settings: \(error.localizedDescription)")
        }
    }
}
