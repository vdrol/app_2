import AVFoundation

extension AVAudioPCMBuffer {
    /// Averages all channels into a new mono Float32 buffer at the same sample rate.
    /// Speech recognizers want mono; the stereo original is only needed for direction.
    func downmixedToMono() -> AVAudioPCMBuffer? {
        let channels = Int(format.channelCount)
        if channels == 1 { return self }
        guard channels > 1,
              format.commonFormat == .pcmFormatFloat32,
              let source = floatChannelData,
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: format.sampleRate,
                                             channels: 1,
                                             interleaved: false),
              let output = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameLength),
              let destination = output.floatChannelData?[0]
        else { return nil }

        let frames = Int(frameLength)
        let interleaved = format.isInterleaved
        let scale = 1 / Float(channels)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += interleaved ? source[0][frame * channels + channel] : source[channel][frame]
            }
            destination[frame] = sum * scale
        }
        output.frameLength = frameLength
        return output
    }
}
