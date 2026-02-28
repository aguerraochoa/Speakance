import AVFoundation
import Foundation
import Speech

@MainActor
final class AudioCaptureService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording(startedAt: Date, fileURL: URL)
        case processing
    }

    struct VoiceCaptureResult: Equatable {
        let rawText: String
        let durationSeconds: Int
        let localAudioFilePath: String?
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var speechPermissionDenied = false

    private var recorder: AVAudioRecorder?
    private var autoStopTask: Task<Void, Never>?
    private var speechTask: SFSpeechRecognitionTask?
    private var preferredSpeechLocaleIdentifier: String?
    private let maxDurationSeconds = 15
    private let minimumUsefulDurationSeconds = 1

    var maxRecordingDurationSeconds: Int {
        maxDurationSeconds
    }

    func setPreferredSpeechLocaleIdentifier(_ identifier: String?) {
        preferredSpeechLocaleIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    func startRecording() {
        guard !isBusy else { return }
        lastErrorMessage = nil
        permissionDenied = false

        Task { [weak self] in
            await self?.startRecordingFlow()
        }
    }

    func stopRecording() async -> VoiceCaptureResult? {
        autoStopTask?.cancel()
        autoStopTask = nil

        let result = await finalizeRecordingIfNeeded(triggeredByAutoStop: false)
        if result == nil, case .requestingPermission = state {
            // User released while permission prompt was showing. Reset gracefully.
            state = .idle
        }
        return result
    }

    func cancelRecording() {
        autoStopTask?.cancel()
        autoStopTask = nil
        speechTask?.cancel()
        speechTask = nil

        switch state {
        case .recording(_, let fileURL):
            recorder?.stop()
            recorder = nil
            try? FileManager.default.removeItem(at: fileURL)
            lastErrorMessage = nil
            state = .idle
        case .requestingPermission, .processing:
            recorder?.stop()
            recorder = nil
            lastErrorMessage = nil
            state = .idle
        case .idle:
            break
        }
    }

    deinit {
        recorder?.stop()
        autoStopTask?.cancel()
        speechTask?.cancel()
    }

    private var isBusy: Bool {
        switch state {
        case .idle:
            return false
        case .requestingPermission, .recording, .processing:
            return true
        }
    }

    private func startRecordingFlow() async {
        let granted = await ensureRecordPermission()
        guard granted else {
            permissionDenied = true
            lastErrorMessage = "Microphone access is required to record expenses."
            state = .idle
            return
        }

        await ensureSpeechPermissionIfNeeded()
        beginRecording()
    }

    private func ensureRecordPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            state = .requestingPermission
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func ensureSpeechPermissionIfNeeded() async {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechPermissionDenied = false
        case .denied, .restricted:
            speechPermissionDenied = true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            speechPermissionDenied = !granted
        @unknown default:
            speechPermissionDenied = true
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true, options: [])

            let fileURL = try makeRecordingFileURL()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.prepareToRecord()
            recorder.record()

            self.recorder = recorder
            state = .recording(startedAt: .now, fileURL: fileURL)

            autoStopTask?.cancel()
            autoStopTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.maxDurationSeconds))
                await MainActor.run {
                    guard case .recording = self.state else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        _ = await self.finalizeRecordingIfNeeded(triggeredByAutoStop: true)
                    }
                }
            }
        } catch {
            recorder = nil
            state = .idle
            lastErrorMessage = "Could not start recording. \(error.localizedDescription)"
        }
    }

    private func activeSpeechRecognizer() -> SFSpeechRecognizer? {
        if let preferredSpeechLocaleIdentifier,
           let preferred = SFSpeechRecognizer(locale: Locale(identifier: preferredSpeechLocaleIdentifier)),
           preferred.isAvailable {
            return preferred
        }
        if let local = SFSpeechRecognizer(locale: Locale.current), local.isAvailable {
            return local
        }
        if let spanish = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")), spanish.isAvailable {
            return spanish
        }
        if let fallback = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), fallback.isAvailable {
            return fallback
        }
        return nil
    }

    private func transcribeAudioIfPossible(fileURL: URL) async -> String? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return nil
        }
        guard let recognizer = activeSpeechRecognizer() else {
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }

        return await withCheckedContinuation { continuation in
            var finished = false
            speechTask?.cancel()
            speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if finished { return }
                if let result, result.isFinal {
                    finished = true
                    self?.speechTask = nil
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text.isEmpty ? nil : text)
                    return
                }
                if error != nil {
                    finished = true
                    self?.speechTask = nil
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func finalizeRecordingIfNeeded(triggeredByAutoStop: Bool) async -> VoiceCaptureResult? {
        guard case let .recording(startedAt, fileURL) = state else { return nil }

        state = .processing
        recorder?.stop()
        recorder = nil

        let duration = min(max(1, Int(Date().timeIntervalSince(startedAt))), maxDurationSeconds)
        if !triggeredByAutoStop && duration < minimumUsefulDurationSeconds {
            try? FileManager.default.removeItem(at: fileURL)
            lastErrorMessage = "Hold a bit longer to record (minimum \(minimumUsefulDurationSeconds)s)."
            state = .idle
            return nil
        }

        let nativeTranscript = await transcribeAudioIfPossible(fileURL: fileURL)
        let rawText = nativeTranscript ?? "Voice recording"

        if triggeredByAutoStop {
            lastErrorMessage = "Recording reached \(maxDurationSeconds) seconds and was stopped automatically."
        } else if nativeTranscript == nil && speechPermissionDenied {
            lastErrorMessage = "Speech recognition is disabled. We'll transcribe after upload."
        }

        state = .idle
        return VoiceCaptureResult(
            rawText: rawText,
            durationSeconds: duration,
            localAudioFilePath: fileURL.path
        )
    }

    private func makeRecordingFileURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let capturesDir = base
            .appendingPathComponent("Speakance", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)

        if !fm.fileExists(atPath: capturesDir.path) {
            try fm.createDirectory(at: capturesDir, withIntermediateDirectories: true)
        }

        return capturesDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
