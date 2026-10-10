import AVFoundation
import Speech

/// Engine for iOS 17–25 and macOS 14–15: `SFSpeechRecognizer` with on-device recognition required, so
/// no audio ever leaves the phone.
///
/// `SFSpeechRecognizer` keeps growing one partial transcript and rarely finalizes it
/// by itself. So this class splits the transcript into segments itself: when the
/// words stop changing for a moment (a pause), it commits the segment and starts
/// a new recognition request.
final class LegacySpeechTranscriber: CaptionTranscriber {
    var onResult: (@Sendable (String, Bool) -> Void)?
    var onError: (@Sendable (Error) -> Void)?
    let engineName = "SFSpeechRecognizer (on-device)"

    /// How long the words must stay unchanged before the segment is committed.
    private let pauseThreshold: TimeInterval = 1.3
    /// Long monologues are split so captions don't turn into one giant paragraph.
    private let maxSegmentLength = 220

    private let locale: Locale
    private var recognizer: SFSpeechRecognizer?
    private let queue = DispatchQueue(label: "Roundtable.LegacySpeechTranscriber")
    private var timer: DispatchSourceTimer?

    private let lock = NSLock()
    private var running = false
    private var generation = 0
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var lastChange = Date.distantPast

    init(locale: Locale) {
        self.locale = locale
    }

    func prepare() async throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw TranscriptionError.localeNotSupported(locale.identifier)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }
        self.recognizer = recognizer
    }

    func start() async throws {
        guard recognizer != nil else { throw TranscriptionError.onDeviceUnavailable }
        lock.lock()
        running = true
        lock.unlock()
        beginSegment()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.3, repeating: 0.3)
        timer.setEventHandler { [weak self] in self?.checkForPause() }
        timer.resume()
        self.timer = timer
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }

    func stop() async {
        lock.lock()
        running = false
        generation += 1
        let oldTask = task
        let oldRequest = request
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        task = nil
        request = nil
        latestText = ""
        lock.unlock()

        timer?.cancel()
        timer = nil
        oldRequest?.endAudio()
        oldTask?.cancel()
        if !text.isEmpty { onResult?(text, true) }
    }

    // MARK: - Segmenting

    private func beginSegment() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        lock.lock()
        guard running else { lock.unlock(); return }
        generation += 1
        let segment = generation
        self.request = request
        latestText = ""
        lastChange = Date()
        lock.unlock()

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error, segment: segment)
        }

        lock.lock()
        if segment == generation { self.task = task } else { task.cancel() }
        lock.unlock()
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, segment: Int) {
        lock.lock()
        // Callbacks from a segment we've already committed are stale.
        guard running, segment == generation else { lock.unlock(); return }

        if let result {
            let text = result.bestTranscription.formattedString
            if text != latestText {
                latestText = text
                lastChange = Date()
            }
            lock.unlock()
            if result.isFinal {
                commitSegment()
            } else if !text.isEmpty {
                onResult?(text, false)
            }
            return
        }
        lock.unlock()

        if error != nil {
            // Usually "no speech detected" after a long silence. Start over after a short delay
            // so a persistent error can't spin in a tight loop.
            commitSegment(restartDelay: 0.5)
        }
    }

    private func checkForPause() {
        lock.lock()
        let text = latestText
        let idle = Date().timeIntervalSince(lastChange)
        lock.unlock()

        guard !text.isEmpty else { return }
        if idle >= pauseThreshold || text.count > maxSegmentLength {
            commitSegment()
        }
    }

    private func commitSegment(restartDelay: TimeInterval = 0) {
        lock.lock()
        guard running else { lock.unlock(); return }
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldTask = task
        let oldRequest = request
        generation += 1
        task = nil
        request = nil
        latestText = ""
        lock.unlock()

        oldRequest?.endAudio()
        oldTask?.cancel()
        onResult?(text, true)

        if restartDelay > 0 {
            queue.asyncAfter(deadline: .now() + restartDelay) { [weak self] in self?.beginSegment() }
        } else {
            beginSegment()
        }
    }
}
