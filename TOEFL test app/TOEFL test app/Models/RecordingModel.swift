import Foundation
import ScreenCaptureKit
import Combine
import OSLog
import AppKit

extension NSScreen {
    var cgDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) } ?? 0
    }
}

extension SCDisplay {
    var friendlyName: String {
        if let screen = NSScreen.screens.first(where: { $0.cgDisplayID == self.displayID }) {
            return screen.localizedName
        }
        return "Display \(displayID)"
    }
}


@MainActor
final class RecordingModel: NSObject, ObservableObject, CaptureServiceDelegate {
    @Published var isRecording: Bool = false
    @Published var elapsed: TimeInterval = 0
    @Published var selectedDisplay: SCDisplay?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var statusMessage: String = "Ожидание"
    @Published var needsPermission: Bool = true

    private let captureService = CaptureService()
    private let streamer = StreamingClient()
    private let audioStreamer = AudioStreamingClient()
    private var timer: Timer?
    private var startDate: Date?
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "model")

    override init() {
        super.init()
        captureService.delegate = self
    }

    func prepare() async {
        do {
            try await captureService.requestPermissionIfNeeded()
            needsPermission = false
            availableDisplays = try await captureService.availableDisplays()
            selectedDisplay = availableDisplays.first
            if let display = selectedDisplay { captureService.setTarget(display: display) }
            statusMessage = "Готов к стриму"
        } catch {
            needsPermission = true
            statusMessage = "Требуется разрешение"
        }
    }

    func updateDisplay(_ display: SCDisplay) {
        selectedDisplay = display
        captureService.setTarget(display: display)
        statusMessage = "Target: \(display.friendlyName)"
        LogStore.shared.write("Streaming started on \(display.friendlyName)")

    }

    func startStreaming() async {
        guard needsPermission == false else {
            statusMessage = "Не хватает разрешений"
            return
        }
        guard let display = selectedDisplay else {
            statusMessage = "Нет доступного экрана"
            return
        }

        do {
            captureService.setTarget(display: display)
            try await captureService.start()
            streamer.startStreaming()
            audioStreamer.start()
            startTimer()
            isRecording = true
            statusMessage = "Стрим запущен"
            statusMessage = "Target: \(display.friendlyName)"
            LogStore.shared.write("Streaming started on \(display.friendlyName)")
            hideApplicationWindows()

        } catch {
            statusMessage = "Ошибка запуска: \(error.localizedDescription)"
            logger.error("Start failed: \(error.localizedDescription)")
        }
    }

    func stopStreaming() async {
        do {
            try await captureService.stop()
            audioStreamer.stop()
            streamer.stopStreaming()
            stopTimer()
            isRecording = false
            statusMessage = "Остановлено"
            LogStore.shared.write("Streaming stopped")
        } catch {
            statusMessage = "Ошибка остановки: \(error.localizedDescription)"
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

    private func hideApplicationWindows() {
        NSApp.windows.forEach { $0.orderOut(nil) }
        NSApp.hide(nil)
    }

    // MARK: CaptureServiceDelegate
    func captureService(_ service: CaptureService, didOutput sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        switch type {
        case .screen:
            streamer.push(sampleBuffer: sampleBuffer, type: type)
        case .audio:
            audioStreamer.push(sampleBuffer: sampleBuffer)
        @unknown default:
            break
        }
    }

    func captureService(_ service: CaptureService, didStopWith error: Error?) {
        Task { @MainActor in
            if let error {
                self.statusMessage = "Ошибка захвата: \(error.localizedDescription)"
                LogStore.shared.write("Capture error: \(error.localizedDescription)")
            }
            self.isRecording = false
            self.audioStreamer.stop()
            self.streamer.stopStreaming()
            self.stopTimer()
        }
    }
}
