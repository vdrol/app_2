import AVFoundation

extension AVAudioPCMBuffer {
    /// Averages the given channels (all of them when `nil`) into a new mono Float32 buffer at
    /// the same sample rate. Speech recognizers want mono; the original multichannel buffer
    /// is only needed for direction.
    func downmixedToMono(channels selected: [Int]? = nil) -> AVAudioPCMBuffer? {
        let channelCount = Int(format.channelCount)
        if channelCount == 1 { return self }
        guard channelCount > 1,
              format.commonFormat == .pcmFormatFloat32,
              let source = floatChannelData,
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: format.sampleRate,
                                             channels: 1,
                                             interleaved: false),
              let output = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameLength),
              let destination = output.floatChannelData?[0]
        else { return nil }

        var channels = (selected ?? []).filter { $0 >= 0 && $0 < channelCount }
        if channels.isEmpty { channels = Array(0..<channelCount) }

        let frames = Int(frameLength)
        let interleaved = format.isInterleaved
        let scale = 1 / Float(channels.count)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in channels {
                sum += interleaved ? source[0][frame * channelCount + channel] : source[channel][frame]
            }
            destination[frame] = sum * scale
        }
        output.frameLength = frameLength
        return output
    }
}
