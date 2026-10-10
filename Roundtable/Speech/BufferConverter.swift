import AVFoundation

/// Converts audio buffers to the format a speech engine asks for (sample rate, sample type).
/// Not thread-safe: use it from one thread only (the audio thread).
final class BufferConverter {
    enum ConversionError: Error {
        case cannotCreateConverter
        case cannotCreateBuffer
        case failed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }

        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            guard let newConverter = AVAudioConverter(from: buffer.format, to: format) else {
                throw ConversionError.cannotCreateConverter
            }
            // Live audio: don't pad the start, which would add a delay to every buffer.
            newConverter.primeMethod = .none
            converter = newConverter
        }
        guard let converter else { throw ConversionError.cannotCreateConverter }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw ConversionError.cannotCreateBuffer
        }

        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw ConversionError.failed(error) }
        return output
    }
}
