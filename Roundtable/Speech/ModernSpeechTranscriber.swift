#if compiler(>=6.2)
import AVFoundation
import Speech

/// iOS 26+ engine built on `SpeechAnalyzer` and `SpeechTranscriber`.
/// It is faster and more accurate than `SFSpeechRecognizer` and handles long-form
/// conversation. It finalizes segments at natural pauses.
@available(iOS 26.0, *)
final class ModernSpeechTranscriber: CaptionTranscriber {
    var onResult: (@Sendable (String, Bool) -> Void)?
    var onError: (@Sendable (Error) -> Void)?
    let engineName = "SpeechAnalyzer (on-device)"

    private let requestedLocale: Locale
    private var resolvedLocale: Locale?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private let converter = BufferConverter()

    private let lock = NSLock()
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?

    init(locale: Locale) {
        requestedLocale = locale
    }

    func prepare() async throws {
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = requestedLocale.identifier(.bcp47)
        guard let locale = supported.first(where: { $0.identifier(.bcp47) == wanted })
            ?? supported.first(where: { $0.language.languageCode == requestedLocale.language.languageCode })
        else {
            throw TranscriptionError.localeNotSupported(requestedLocale.identifier)
        }

        // The model is downloaded once (this needs internet the first time only) and
        // after that it works fully offline.
        let module = makeModule(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        resolvedLocale = locale
    }

    private func makeModule(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale,
                          transcriptionOptions: [],
                          reportingOptions: [.volatileResults],
                          attributeOptions: [])
    }

    func start() async throws {
        guard let resolvedLocale else { throw TranscriptionError.onDeviceUnavailable }

        // Create a new module and analyzer for each session; an analyzer can't be restarted after it finishes.
        let transcriber = makeModule(locale: resolvedLocale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format: AVAudioFormat? = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()

        lock.lock()
        analyzerFormat = format
        inputBuilder = builder
        lock.unlock()
        self.analyzer = analyzer

        let onResult = self.onResult
        let onError = self.onError
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    onResult?(String(result.text.characters), result.isFinal)
                }
            } catch {
                if !Task.isCancelled { onError?(error) }
            }
        }

        try await analyzer.start(inputSequence: stream)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let builder = inputBuilder
        let format = analyzerFormat
        lock.unlock()
        guard let builder else { return }

        let input: AVAudioPCMBuffer
        if let format {
            guard let converted = try? converter.convert(buffer, to: format) else { return }
            input = converted
        } else {
            input = buffer
        }
        builder.yield(AnalyzerInput(buffer: input))
    }

    func stop() async {
        lock.lock()
        let builder = inputBuilder
        inputBuilder = nil
        lock.unlock()

        builder?.finish()
        // Delivers the last final result, then ends the results stream (and resultsTask).
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        resultsTask = nil
    }
}
#endif
