import AppKit
import Carbon
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RecordingModel?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let logger = Logger(subsystem: "com.backuprecorder.app", category: "appdelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotKey()
    }

    private func registerHotKey() {
        let modifiers: UInt32 = cmdKey | optionKey | controlKey
        var hotKeyID = EventHotKeyID(signature: 0x424B5550, id: 1) // "BKUP"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_R), modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)

        guard status == noErr else {
            logger.error("Failed to register hotkey: status \(status)")
            return
        }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let handler: EventHandlerUPP = { _, _, userData in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            delegate.toggleRecording()
            return noErr
        }

        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventSpec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &hotKeyHandler)

        if installStatus != noErr {
            logger.error("Failed to install hotkey handler: status \(installStatus)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
    }

    private func toggleRecording() {
        Task { @MainActor in
            guard let model else { return }

            if model.isRecording {
                await model.stopStreaming()
            } else {
                await model.startStreaming()
            }
        }
    }
}

@main
struct TOEFL_test_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = RecordingModel()

    init() {
        appDelegate.model = model
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    appDelegate.model = model
                }
        }
        .handlesExternalEvents(matching: ["*"])

        MenuBarExtra("Backup Recorder", systemImage: model.isRecording ? "dot.radiowaves.left.and.right" : "record.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.statusMessage)
                Text("Elapsed: \(format(interval: model.elapsed))")
                    .monospacedDigit()
                Button(model.isRecording ? "Stop" : "Start") {
                    Task {
                        if model.isRecording {
                            await model.stopStreaming()
                        } else {
                            await model.startStreaming()
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func format(interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }
}
