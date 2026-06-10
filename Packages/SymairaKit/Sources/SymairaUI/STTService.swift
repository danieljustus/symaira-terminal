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

    public func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                completion(status == .authorized)
            }
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
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.recognizedText = text
                    self.delegate?.sttService(self, didRecognize: text)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor [weak self] in
                    self?.stopRecording()
                    if let error = error {
                        self?.delegate?.sttService(self!, didFailWithError: error)
                    } else {
                        self?.delegate?.sttServiceDidFinishRecording(self!)
                    }
                }
            }
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
