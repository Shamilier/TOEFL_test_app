import SwiftUI
import OSLog
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
    }
}

@main
struct TOEFL_test_appApp: App {
    @StateObject private var model = RecordingModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HeadlessRunnerView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct HeadlessRunnerView: View {
    @EnvironmentObject private var model: RecordingModel
    @State private var hasStarted = false

    var body: some View {
        Color.clear
            .frame(width: 200, height: 200)
            .task {
                await startStreamingOnLaunch()
            }
    }

    @MainActor
    private func startStreamingOnLaunch() async {
        guard hasStarted == false else { return }
        hasStarted = true
        await model.prepare()
        await model.startStreaming()
    }
}
