import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @EnvironmentObject private var model: RecordingModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Прямой эфир")
                    .font(.largeTitle.weight(.semibold))
                Text("Одно касание — начинаем или останавливаем поток на сервер без локального сохранения.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if model.needsPermission {
                PermissionView()
            }

            Button(action: {
                Task {
                    if model.isRecording {
                        await model.stopStreaming()
                    } else {
                        await model.startStreaming()
                    }
                }
            }) {
                Label(model.isRecording ? "Остановить запись" : "Начать запись",
                      systemImage: model.isRecording ? "stop.circle" : "record.circle")
                    .font(.title2.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            VStack(spacing: 8) {
                Label(model.statusMessage, systemImage: model.isRecording ? "dot.radiowaves.left.and.right" : "pause")
                    .foregroundStyle(model.isRecording ? .red : .primary)
                Text(timerText(from: model.elapsed))
                    .monospacedDigit()
                    .font(.title3)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .task {
            await model.prepare()
        }
        .frame(minWidth: 360)
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
            Label("Нужны разрешения", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("Включите захват экрана и системного звука для приложения в Настройки → Конфиденциальность и безопасность.")
            Text("Разрешения нужны только для прямой трансляции без хранения файлов на устройстве.")
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
