import AVFoundation

/// Records from the built-in microphone, in stereo when the device supports it.
/// Each buffer goes to the direction estimator (stereo) and, mixed down to mono,
/// to `onMonoBuffer` for transcription.
final class AudioCaptureEngine {
    enum CaptureError: LocalizedError {
        case noInput

        var errorDescription: String? {
            "No microphone is available. Check that another app isn't using it."
        }
    }

    let estimator = DirectionEstimator()
    /// Called on the audio thread.
    var onMonoBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var engine: AVAudioEngine?
    private(set) var isRunning = false
    private(set) var isStereo = false

    /// Picks the built-in mic and asks for its stereo polar pattern.
    /// Stereo is supported on iPhone XS and later; older devices fall back to mono.
    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])

        if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(mic)
            let sources = mic.dataSources ?? []
            let stereoSource = sources.first { $0.orientation == .front && Self.supportsStereo($0) }
                ?? sources.first(where: Self.supportsStereo)
            if let stereoSource {
                try stereoSource.setPreferredPolarPattern(.stereo)
                try mic.setPreferredDataSource(stereoSource)
                // The app is locked to portrait, so the stereo image is always
                // relative to the phone's left and right edges.
                try session.setPreferredInputOrientation(.portrait)
            }
        }
        try session.setActive(true)
    }

    private static func supportsStereo(_ source: AVAudioSessionDataSourceDescription) -> Bool {
        source.supportedPolarPatterns?.contains(.stereo) ?? false
    }

    func start() throws {
        guard !isRunning else { return }
        // A fresh engine picks up the session's current (possibly stereo) input format.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw CaptureError.noInput }

        isStereo = format.channelCount >= 2
        estimator.reset()

        let estimator = self.estimator
        let onMonoBuffer = self.onMonoBuffer
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            estimator.process(buffer)
            if let mono = buffer.downmixedToMono() {
                onMonoBuffer?(mono)
            }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        isRunning = true
    }

    func stop() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
