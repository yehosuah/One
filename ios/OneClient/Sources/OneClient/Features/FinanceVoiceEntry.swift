#if canImport(SwiftUI)
import Foundation
import Combine
#if os(iOS) && canImport(Speech) && canImport(AVFoundation)
import Speech
import AVFoundation
#endif

private func financeVoiceUserFacingError(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError {
        case .transport(let message):
            return message
        case .server(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .unauthorized:
            return "Voice expense entry needs permission before it can listen."
        case .decoding:
            return "Voice expense entry could not understand that response."
        case .conflict:
            return "Voice expense entry hit a local conflict. Try again."
        }
    }
    return String(describing: error)
}

@MainActor
protocol FinanceSpeechRecognizing: AnyObject {
    func refreshAvailability() async -> FinanceVoiceAvailability
    func requestAccessIfNeeded() async -> FinanceVoiceAvailability
    func start(onUpdate: @escaping @MainActor (String) -> Void) async throws
    func stop() async -> String
    func cancel() async
}

@MainActor
final class FinanceVoiceCaptureViewModel: ObservableObject {
    @Published private(set) var availability: FinanceVoiceAvailability = .unsupported
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let recognizer: FinanceSpeechRecognizing
    private let parser: FinanceVoiceExpenseParser

    init(
        recognizer: FinanceSpeechRecognizing = LiveFinanceSpeechRecognizer(),
        parser: FinanceVoiceExpenseParser = FinanceVoiceExpenseParser()
    ) {
        self.recognizer = recognizer
        self.parser = parser
    }

    func refreshAvailability() async {
        availability = await recognizer.refreshAvailability()
    }

    func start() async {
        let access = await recognizer.requestAccessIfNeeded()
        availability = access
        guard access == .available else {
            errorMessage = access.message
            return
        }
        do {
            transcript = ""
            try await recognizer.start { [weak self] value in
                self?.transcript = value
            }
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = financeVoiceUserFacingError(error)
        }
    }

    func stop(categories: [FinanceCategory]) async -> FinanceVoiceParseResult? {
        isRecording = false
        let value = await recognizer.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = value
        await refreshAvailability()
        guard !value.isEmpty else {
            errorMessage = "No speech was captured from that recording."
            return nil
        }
        errorMessage = nil
        return parser.parse(value, categories: categories)
    }

    func cancel() async {
        isRecording = false
        await recognizer.cancel()
        await refreshAvailability()
    }
}

@MainActor
private final class UnavailableFinanceSpeechRecognizer: FinanceSpeechRecognizing {
    func refreshAvailability() async -> FinanceVoiceAvailability { .unsupported }
    func requestAccessIfNeeded() async -> FinanceVoiceAvailability { .unsupported }
    func start(onUpdate: @escaping @MainActor (String) -> Void) async throws {
        throw APIError.transport(FinanceVoiceAvailability.unsupported.message)
    }
    func stop() async -> String { "" }
    func cancel() async {}
}

#if os(iOS) && canImport(Speech) && canImport(AVFoundation)
@MainActor
private final class IOSLiveFinanceSpeechRecognizer: NSObject, FinanceSpeechRecognizing {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""

    func refreshAvailability() async -> FinanceVoiceAvailability {
        evaluateAvailability()
    }

    func requestAccessIfNeeded() async -> FinanceVoiceAvailability {
        let speechStatus = await resolvedSpeechAuthorization()
        guard speechStatus == .authorized else {
            return mapSpeechStatus(speechStatus)
        }
        let microphoneGranted = await resolvedMicrophonePermission()
        guard microphoneGranted else {
            return .microphoneDenied
        }
        return evaluateAvailability()
    }

    func start(onUpdate: @escaping @MainActor (String) -> Void) async throws {
        let availability = await requestAccessIfNeeded()
        guard availability == .available else {
            throw APIError.transport(availability.message)
        }
        latestTranscript = ""
        speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
        guard let speechRecognizer else {
            throw APIError.transport(FinanceVoiceAvailability.unsupported.message)
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else {
                return
            }
            if let result {
                self.latestTranscript = result.bestTranscription.formattedString
                Task { @MainActor in
                    onUpdate(self.latestTranscript)
                }
            }
            if error != nil {
                self.finishAudioSession()
            }
        }
    }

    func stop() async -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        try? await Task.sleep(for: .milliseconds(300))
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return latestTranscript
    }

    func cancel() async {
        latestTranscript = ""
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        finishAudioSession()
    }

    private func finishAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func evaluateAvailability() -> FinanceVoiceAvailability {
        guard let speechRecognizer else {
            return .unsupported
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            return .authorizationRequired
        case .denied:
            return .authorizationDenied
        case .restricted:
            return .restricted
        @unknown default:
            return .unsupported
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            break
        case .denied:
            return .microphoneDenied
        case .undetermined:
            return .authorizationRequired
        @unknown default:
            return .unsupported
        }
        return speechRecognizer.supportsOnDeviceRecognition ? .available : .onDeviceUnavailable
    }

    private func resolvedSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else {
            return status
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { nextStatus in
                continuation.resume(returning: nextStatus)
            }
        }
    }

    private func resolvedMicrophonePermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> FinanceVoiceAvailability {
        switch status {
        case .authorized:
            return .available
        case .denied:
            return .authorizationDenied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .authorizationRequired
        @unknown default:
            return .unsupported
        }
    }
}
#endif

@MainActor
private final class LiveFinanceSpeechRecognizer: FinanceSpeechRecognizing {
    #if os(iOS) && canImport(Speech) && canImport(AVFoundation)
    private let impl = IOSLiveFinanceSpeechRecognizer()
    #else
    private let impl = UnavailableFinanceSpeechRecognizer()
    #endif

    func refreshAvailability() async -> FinanceVoiceAvailability {
        await impl.refreshAvailability()
    }

    func requestAccessIfNeeded() async -> FinanceVoiceAvailability {
        await impl.requestAccessIfNeeded()
    }

    func start(onUpdate: @escaping @MainActor (String) -> Void) async throws {
        try await impl.start(onUpdate: onUpdate)
    }

    func stop() async -> String {
        await impl.stop()
    }

    func cancel() async {
        await impl.cancel()
    }
}
#endif
