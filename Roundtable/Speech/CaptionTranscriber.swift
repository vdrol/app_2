import AVFoundation

enum TranscriptionError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case localeNotSupported(String)
    case onDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is off. Turn it on in (System) Settings › Privacy & Security › Microphone."
        case .speechPermissionDenied:
            return "Speech recognition is off. Turn it on in (System) Settings › Privacy & Security › Speech Recognition."
        case .localeNotSupported(let identifier):
            return "On-device captions aren't available for \(identifier) yet."
        case .onDeviceUnavailable:
            #if os(macOS)
            return "On-device speech recognition isn't available. In System Settings › Keyboard, turn on Dictation so macOS downloads the speech model, then try again."
            #else
            return "On-device speech recognition isn't available. In Settings › General › Keyboard, turn on Dictation so iOS downloads the speech model, then try again."
            #endif
        }
    }
}

/// A speech-to-text engine that runs entirely on the device.
///
/// It reports one segment at a time: any number of updates with `isFinal == false`
/// while the words are still changing, then one with `isFinal == true`. The next
/// update after that starts a new segment.
protocol CaptionTranscriber: AnyObject {
    /// `(text, isFinal)`. May be called on any thread.
    var onResult: (@Sendable (String, Bool) -> Void)? { get set }
    /// May be called on any thread.
    var onError: (@Sendable (Error) -> Void)? { get set }
    var engineName: String { get }

    /// Checks support and downloads speech models if needed. Call once.
    func prepare() async throws
    func start() async throws
    /// Called on the audio thread with mono Float32 buffers.
    func append(_ buffer: AVAudioPCMBuffer)
    func stop() async
}

enum TranscriberFactory {
    /// Uses `SpeechAnalyzer` on iOS/macOS 26 and later, and on-device `SFSpeechRecognizer` otherwise.
    static func makeTranscriber(locale: Locale) async throws -> CaptionTranscriber {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            let modern = ModernSpeechTranscriber(locale: locale)
            do {
                try await modern.prepare()
                return modern
            } catch {
                // Older hardware or an unsupported language: fall through to the classic recognizer.
            }
        }
        #endif
        let legacy = LegacySpeechTranscriber(locale: locale)
        try await legacy.prepare()
        return legacy
    }
}
