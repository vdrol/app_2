import AVFoundation
import Accelerate

/// Estimates where a voice is coming from by comparing the loudness of the
/// left and right channels of the iPhone's built-in stereo microphone.
///
/// `process(_:)` is called on the real-time audio thread; everything else is
/// called from the main thread, so all state is guarded by a lock.
final class DirectionEstimator: @unchecked Sendable {
    struct Snapshot: Equatable {
        /// Smoothed live direction (-1 left … +1 right), or `nil` when nobody is speaking.
        var direction: Double?
        /// RMS input level, 0…1.
        var level: Float
    }

    private let lock = NSLock()
    private var gain: Double = 3
    private var flipped = false

    private var hasStereo = false
    private var level: Float = 0
    private var noiseFloor: Float = 0.002
    private var smoothed: Double = 0
    private var lastSpeechAt: TimeInterval = 0
    private var utteranceSum: Double = 0
    private var utteranceWeight: Double = 0

    /// - Parameters:
    ///   - gain: Stretches small level differences so that people a little to the side still read as "left"/"right".
    ///   - flipped: Swaps left and right, for when the phone lies the other way round.
    func configure(gain: Double, flipped: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.gain = gain
        self.flipped = flipped
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        hasStereo = false
        level = 0
        noiseFloor = 0.002
        smoothed = 0
        lastSpeechAt = 0
        utteranceSum = 0
        utteranceWeight = 0
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0, buffer.format.commonFormat == .pcmFormatFloat32,
              let data = buffer.floatChannelData else { return }

        let channels = Int(buffer.format.channelCount)
        var left: Float = 0
        var right: Float = 0
        if channels >= 2 {
            if buffer.format.isInterleaved {
                let stride = vDSP_Stride(channels)
                vDSP_rmsqv(data[0], stride, &left, vDSP_Length(frames))
                vDSP_rmsqv(data[0] + 1, stride, &right, vDSP_Length(frames))
            } else {
                vDSP_rmsqv(data[0], 1, &left, vDSP_Length(frames))
                vDSP_rmsqv(data[1], 1, &right, vDSP_Length(frames))
            }
            ingest(level: (left + right) / 2, pan: Self.pan(left: left, right: right), stereo: true)
        } else {
            vDSP_rmsqv(data[0], 1, &left, vDSP_Length(frames))
            ingest(level: left, pan: nil, stereo: false)
        }
    }

    /// Normalised level difference: -1 when all energy is on the left, +1 when it is all on the right.
    static func pan(left: Float, right: Float) -> Double {
        let sum = Double(left) + Double(right)
        guard sum > 1e-9 else { return 0 }
        return (Double(right) - Double(left)) / sum
    }

    private func ingest(level newLevel: Float, pan: Double?, stereo: Bool) {
        lock.lock(); defer { lock.unlock() }
        hasStereo = stereo
        level = newLevel

        // Adaptive noise floor: drops quickly to quiet moments and creeps up slowly,
        // so a noisy restaurant doesn't count as constant speech.
        if newLevel < noiseFloor {
            noiseFloor = noiseFloor * 0.8 + newLevel * 0.2
        } else {
            noiseFloor *= 1.002
        }
        noiseFloor = max(noiseFloor, 0.0003)

        let isSpeech = newLevel > max(noiseFloor * 2, 0.002)
        guard isSpeech, let pan else { return }

        let scaled = min(max(pan * gain * (flipped ? -1 : 1), -1), 1)
        smoothed = smoothed * 0.7 + scaled * 0.3
        lastSpeechAt = ProcessInfo.processInfo.systemUptime

        // Louder buffers say more about where the speaker is, so they count for more.
        let weight = Double(newLevel - noiseFloor)
        utteranceSum += scaled * weight
        utteranceWeight += weight
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let recent = ProcessInfo.processInfo.systemUptime - lastSpeechAt < 1.2
        return Snapshot(direction: hasStereo && recent ? smoothed : nil, level: level)
    }

    /// Average direction of speech since the last call to `takeUtteranceDirection()`.
    func peekUtteranceDirection() -> Double? {
        lock.lock(); defer { lock.unlock() }
        return utteranceWeight > 0 ? utteranceSum / utteranceWeight : nil
    }

    /// Returns the average direction of the utterance that just ended and starts a new one.
    func takeUtteranceDirection() -> Double? {
        lock.lock(); defer { lock.unlock() }
        let result = utteranceWeight > 0 ? utteranceSum / utteranceWeight : nil
        utteranceSum = 0
        utteranceWeight = 0
        return result
    }
}
