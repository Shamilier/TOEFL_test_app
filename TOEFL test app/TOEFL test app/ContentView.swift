import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @EnvironmentObject private var model: RecordingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if model.needsPermission {
                PermissionView()
            }
            Picker("Capture target", selection: Binding(get: {
                model.selectedDisplay?.displayID ?? 0
            }, set: { newValue in
                if let display = model.availableDisplays.first(where: { $0.displayID == newValue }) {
                    model.updateDisplay(display)
                }
            })) {
                ForEach(model.availableDisplays, id: \.displayID) { display in
                    Text(display.displayName ?? "Display").tag(display.displayID)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.availableDisplays.isEmpty)

            HStack {
                Button(action: { Task { await model.startRecording(manual: true) } }) {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .disabled(model.isRecording)

                Button(action: { Task { await model.stopRecording() } }) {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(!model.isRecording)
            }
            statusPanel
            settingsPanel
            uploadPanel
            logLocation
        }
        .padding()
        .task {
            await model.loadDisplays()
        }
        .frame(minWidth: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backup Recorder")
                .font(.largeTitle.weight(.semibold))
            Text("Legit backup capture with visible status. Recording starts only when you press the button or if auto-backup is pre-enabled.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading) {
            HStack {
                Label(model.statusMessage, systemImage: model.isRecording ? "dot.radiowaves.left.and.right" : "pause")
                    .foregroundStyle(model.isRecording ? .red : .primary)
                Spacer()
                Text(timerText(from: model.elapsed))
                    .monospacedDigit()
                    .font(.title3)
            }
            if let display = model.selectedDisplay {
                Text("Target: \(display.displayName ?? "Display")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if model.isRecording == false {
                Toggle("Auto-backup recording", isOn: $model.settingsStore.settings.autoBackupEnabled)
                    .toggleStyle(.switch)
            } else {
                Text("Auto-backup toggle is locked while recording")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local recording")
                .font(.headline)
            Stepper(value: $model.settingsStore.settings.segmentDuration, in: 60...900, step: 30) {
                Text("Segment duration: \(Int(model.settingsStore.settings.segmentDuration))s")
            }
            Stepper(value: Binding(get: {
                Double(model.settingsStore.settings.diskQuotaBytes) / 1_073_741_824
            }, set: { newValue in
                model.settingsStore.settings.diskQuotaBytes = Int64(newValue * 1_073_741_824)
            }), in: 1...20, step: 1) {
                Text("Disk quota: \(model.settingsStore.settings.diskQuotaBytes / 1_073_741_824) GB")
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var uploadPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional upload")
                .font(.headline)
            Toggle("Upload recordings", isOn: $model.settingsStore.settings.uploadEnabled)
            TextField("Upload endpoint (HTTPS)", text: $model.settingsStore.settings.uploadEndpoint)
                .textFieldStyle(.roundedBorder)
                .disabled(!model.settingsStore.settings.uploadEnabled)
            Text("Status: \(model.uploader.lastUploadStatus)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var logLocation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diagnostics")
                .font(.headline)
            Text("Log file: \(LogStore.shared.logURL.path)")
                .font(.footnote)
                .textSelection(.enabled)
        }
    }

    private func timerText(from interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct PermissionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permissions needed", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("Enable Screen Recording and system audio capture for Backup Recorder in System Settings → Privacy & Security.")
            Text("We ask only so a visible backup recording can run if the main recorder crashes.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
        .environmentObject(RecordingModel())
}
