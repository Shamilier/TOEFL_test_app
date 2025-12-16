import Foundation
import ScreenCaptureKit
import Combine
import OSLog

@MainActor
final class RecordingModel: NSObject, ObservableObject, CaptureServiceDelegate {
    @Published var isRecording: Bool = false
    @Published var elapsed: TimeInterval = 0
    @Published var selectedDisplay: SCDisplay?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var statusMessage: String = "Idle"
    @Published var needsPermission: Bool = true

    let settingsStore = SettingsStore()
    let uploader = Uploader()

    private let captureService = CaptureService()
    private var rotator: SegmentRotator?
    private var timer: Timer?
    private var startDate: Date?
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "model")

    override init() {
        super.init()
        captureService.delegate = self
    }

    func loadDisplays() async {
        do {
            try await captureService.requestPermissionIfNeeded()
            needsPermission = false
            availableDisplays = try await captureService.availableDisplays()
            selectedDisplay = availableDisplays.first
            if let display = selectedDisplay { captureService.setTarget(display: display) }
        } catch {
            needsPermission = true
            statusMessage = "Permission required"
        }
    }

    func updateDisplay(_ display: SCDisplay) {
        selectedDisplay = display
        captureService.setTarget(display: display)
        statusMessage = "Target: \(display.displayName ?? "Display")"
    }

    func startRecording(manual: Bool = true) async {
        guard manual || settingsStore.settings.autoBackupEnabled else {
            statusMessage = "Auto-backup disabled"
            return
        }
        guard let display = selectedDisplay else {
            statusMessage = "Select a display"
            return
        }

        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let folder = moviesDirectory.appendingPathComponent("BackupRecorder", isDirectory: true)
        rotator = SegmentRotator(baseDirectory: folder, segmentDuration: settingsStore.settings.segmentDuration, diskQuota: settingsStore.settings.diskQuotaBytes)
        rotator?.onSegmentFinished = { [weak self] url in
            guard let self else { return }
            self.uploader.uploadIfNeeded(file: url, endpoint: self.settingsStore.settings.uploadEndpoint, enabled: self.settingsStore.settings.uploadEnabled)
        }

        do {
            captureService.setTarget(display: display)
            try await captureService.start()
            try rotator?.startNewSegment(width: Int(display.width), height: Int(display.height))
            startTimer()
            isRecording = true
            statusMessage = "Recording"
            LogStore.shared.write("Recording started on \(display.displayName ?? "display")")
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
            logger.error("Start failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        do {
            try await captureService.stop()
            _ = await rotator?.finishCurrentSegment()
            stopTimer()
            isRecording = false
            statusMessage = "Stopped"
            LogStore.shared.write("Recording stopped")
        } catch {
            statusMessage = "Stop failed: \(error.localizedDescription)"
        }
    }

    private func startTimer() {
        elapsed = 0
        startDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startDate else { return }
            self.elapsed = Date().timeIntervalSince(startDate)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: CaptureServiceDelegate
    func captureService(_ service: CaptureService, didOutput sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        rotator?.append(sampleBuffer, type: type)
    }

    func captureService(_ service: CaptureService, didStopWith error: Error?) {
        Task { @MainActor in
            if let error {
                self.statusMessage = "Capture error: \(error.localizedDescription)"
                LogStore.shared.write("Capture error: \(error.localizedDescription)")
            }
            self.isRecording = false
        }
    }
}
