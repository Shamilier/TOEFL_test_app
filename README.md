# Backup Recorder (macOS 13+)

A transparent backup screen + system audio recorder built with SwiftUI and ScreenCaptureKit. It keeps a visible status indicator and only records after explicit user actions. Optional auto-backup mode allows automatic start after a crash *only* when the user enabled it ahead of time.

## Features
- Menu bar extra and status window showing **Recording** state, timer, and selected display/window.
- ScreenCaptureKit capture of screen and system audio; encoding via AVAssetWriter (H.264 + AAC) to MP4.
- Segment rotation (default 5 minutes) with disk-quota enforcement and log file for diagnostics.
- Optional HTTPS uploads via configurable endpoint and background `URLSession`.
- Permissions screen guides users through Screen Recording + system audio access.

## Project structure
- `Models/RecordingModel.swift` — UI-facing observable object orchestrating capture, rotation, uploads, timers.
- `Services/CaptureService.swift` — ScreenCaptureKit stream setup and delegate delivery of sample buffers.
- `Services/RecordingWriter.swift` — AVAssetWriter wrapper for H.264 + AAC MP4 segments.
- `Services/SegmentRotator.swift` — segment lifecycle, rotation, and disk-quota cleanup.
- `Services/Uploader.swift` — optional background uploads.
- `Services/SettingsStore.swift` — user defaults backed settings.
- `Services/LogStore.swift` — OSLog + file log helper.
- `Resources/BackupRecorder.entitlements` — sample entitlements for sandboxed builds.
- `ContentView.swift` — visible status window with controls and settings.
- `TOEFL_test_appApp.swift` — SwiftUI app entry + menu bar extra.

## Permissions
On first launch macOS will prompt for **Screen Recording** and system audio capture (ScreenCaptureKit). The app shows an inline callout explaining why access is needed. If the user declines, the status remains idle until permissions are granted in *System Settings → Privacy & Security → Screen Recording*.

## Building
1. Open `TOEFL test app.xcodeproj` in Xcode 15+ on macOS 13 or later.
2. Ensure the target has the `Resources/BackupRecorder.entitlements` file set for sandbox builds.
3. Run the `TOEFL test app` scheme. The menu bar extra and status window will appear.

## Recording behavior
- Start/stop is manual via the window or menu bar. Auto-backup can only start if the toggle was enabled beforehand.
- Segments are written to `~/Movies/BackupRecorder/segment_<timestamp>.mp4`.
- Uploads occur only when the user enables "Upload recordings" *and* provides an HTTPS endpoint.

## Troubleshooting
- Logs are written to `~/Library/Logs/BackupRecorder.log`.
- If capture fails, verify permissions, then restart the app.
