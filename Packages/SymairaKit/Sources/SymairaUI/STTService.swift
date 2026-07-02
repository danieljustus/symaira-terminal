import Foundation
import Speech

@MainActor
public protocol STTServiceDelegate: AnyObject {
    func sttService(_ service: STTService, didRecognize text: String)
    func sttService(_ service: STTService, didFailWithError error: Error)
    func sttServiceDidFinishRecording(_ service: STTService)
}

@MainActor
public class STTService: NSObject, ObservableObject {
    @Published public var isRecording = false
    @Published public var recognizedText = ""

    private var _audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?

    public weak var delegate: STTServiceDelegate?

    public init(locale: Locale = Locale.current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    /// `nonisolated` on purpose: `SFSpeechRecognizer.requestAuthorization`
    /// invokes its handler on a private background queue. If this method were
    /// MainActor-isolated, the handler closure would inherit that isolation and
    /// Swift 6's runtime executor check (`swift_task_isCurrentExecutor`) would
    /// abort the process with SIGTRAP when the callback lands off the main
    /// thread. Forming the closure in a nonisolated context removes that check;
    /// we then hop to the main actor explicitly to deliver the result.
    public nonisolated func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            // Do not capture `completion` directly in this closure. Because
            // `completion` is `@MainActor`, capturing it would make the whole
            // `SFSpeechRecognizer` callback implicitly `@MainActor`, but TCC
            // invokes that callback on `com.apple.root.default-qos`. That
            // queue is not the main actor, so Swift 6's runtime executor
            // check aborts with SIGTRAP. Instead, pass the result through a
            // `nonisolated` static helper that only creates a `@MainActor`
            // `Task` and captures the completion there.
            Self.deliverAuthorizationResult(completion, authorized: status == .authorized)
        }
    }

    private nonisolated static func deliverAuthorizationResult(
        _ completion: @escaping @MainActor (Bool) -> Void,
        authorized: Bool
    ) {
        Task { @MainActor in
            completion(authorized)
        }
    }

    public func startRecording() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw STTError.recognizerUnavailable
        }

        let engine = AVAudioEngine()
        _audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw STTError.recognitionRequestFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            // Keep the callback nonisolated: `SFSpeechRecognitionTask` calls this
            // completion handler on a background queue, so it must not carry
            // MainActor isolation. The helper hops to the main actor for UI work.
            Self.handleRecognitionResult(self, result: result, error: error)
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        try engine.start()

        isRecording = true
    }

    public func stopRecording() {
        _audioEngine?.stop()
        _audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        _audioEngine = nil

        isRecording = false
    }

    private nonisolated static func handleRecognitionResult(
        _ service: STTService?,
        result: SFSpeechRecognitionResult?,
        error: (any Error)?
    ) {
        if let result = result {
            let text = result.bestTranscription.formattedString
            Task { @MainActor [weak service] in
                guard let service = service else { return }
                service.recognizedText = text
                service.delegate?.sttService(service, didRecognize: text)
            }
        }

        if error != nil || (result?.isFinal ?? false) {
            Task { @MainActor [weak service] in
                guard let service = service else { return }
                service.stopRecording()
                if let error = error {
                    service.delegate?.sttService(service, didFailWithError: error)
                } else {
                    service.delegate?.sttServiceDidFinishRecording(service)
                }
            }
        }
    }
}

public enum STTError: Error, LocalizedError {
    case recognizerUnavailable
    case recognitionRequestFailed

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer is not available"
        case .recognitionRequestFailed: return "Failed to create recognition request"
        }
    }
}
