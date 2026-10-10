import AVFoundation
#if os(macOS)
import CoreAudio
#endif

/// Records from the chosen microphone using every channel it offers. Each buffer goes to
/// the direction estimator (which needs two or more channels) and, mixed down to mono,
/// to `onMonoBuffer` for transcription.
///
/// Where direction comes from:
/// - iPhone XS and later, and some iPads: the built-in mics in stereo mode.
/// - Any device: a stereo or multichannel USB microphone or audio interface.
/// - Mac: built-in mics are usually mono, so direction needs an external stereo mic.
final class AudioCaptureEngine {
    enum CaptureError: LocalizedError {
        case noInput

        var errorDescription: String? {
            "No microphone is available. Check that one is connected and that another app isn't using it."
        }
    }

    let estimator = DirectionEstimator()
    /// Called on the audio thread. Set it before `start(preferredInputID:)`.
    var onMonoBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var engine: AVAudioEngine?
    private(set) var isRunning = false
    private(set) var channelCount = 0
    private(set) var inputName: String?

    var isStereo: Bool { channelCount >= 2 }

    func availableInputs() -> [AudioInputOption] {
        #if os(macOS)
        return MacAudioDevices.inputDevices()
        #else
        let session = AVAudioSession.sharedInstance()
        if session.category != .record {
            try? session.setCategory(.record, mode: .default, options: [])
        }
        return (session.availableInputs ?? []).map {
            AudioInputOption(id: $0.uid, name: $0.portName, channelCount: nil)
        }
        #endif
    }

    func start(preferredInputID: String) throws {
        guard !isRunning else { return }
        // A fresh engine picks up the current input device and its channel layout.
        let engine = AVAudioEngine()

        #if os(macOS)
        let device = MacAudioDevices.deviceID(forUID: preferredInputID) ?? MacAudioDevices.defaultInputDeviceID()
        if let device {
            try MacAudioDevices.setInputDevice(device, on: engine)
            inputName = MacAudioDevices.name(of: device)
        }
        #else
        try configureSession(preferredInputID: preferredInputID)
        inputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw CaptureError.noInput }

        channelCount = Int(format.channelCount)
        estimator.reset()

        let estimator = self.estimator
        let onMonoBuffer = self.onMonoBuffer
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            estimator.process(buffer)
            let pair = estimator.channelPair(channelCount: Int(buffer.format.channelCount))
            if let mono = buffer.downmixedToMono(channels: pair.map { [$0.left, $0.right] }) {
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
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if !os(macOS)
    /// Selects the input and asks for as many channels as it has. For the built-in mic,
    /// that means switching it to its stereo polar pattern (iPhone XS and later).
    private func configureSession(preferredInputID: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])

        let inputs = session.availableInputs ?? []
        let chosen = inputs.first { $0.uid == preferredInputID }
            ?? inputs.first { $0.portType == .builtInMic }

        if let chosen {
            try session.setPreferredInput(chosen)
            if chosen.portType == .builtInMic {
                let sources = chosen.dataSources ?? []
                let stereoSource = sources.first { $0.orientation == .front && Self.supportsStereo($0) }
                    ?? sources.first(where: Self.supportsStereo)
                if let stereoSource {
                    try stereoSource.setPreferredPolarPattern(.stereo)
                    try chosen.setPreferredDataSource(stereoSource)
                    // The iPhone UI is locked to portrait, so the stereo image always runs
                    // across the device's left and right edges.
                    try session.setPreferredInputOrientation(.portrait)
                }
            }
        }

        try session.setActive(true)

        // External USB mics and interfaces: use all their channels so stereo works.
        let maximum = session.maximumInputNumberOfChannels
        if maximum >= 2 {
            try? session.setPreferredInputNumberOfChannels(min(maximum, 8))
        }
    }

    private static func supportsStereo(_ source: AVAudioSessionDataSourceDescription) -> Bool {
        source.supportedPolarPatterns?.contains(.stereo) ?? false
    }
    #endif
}
