import SwiftUI
import OSLog

@main
struct TOEFL_test_appApp: App {
    @StateObject private var model = RecordingModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
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
