import Foundation

/// Live direction and level, updated about ten times a second. It is separate from
/// `CaptionStore` so that the frequent updates only redraw the dial, not the whole transcript.
@MainActor
final class LiveMeter: ObservableObject {
    @Published var direction: Double?
    @Published var level: Float = 0

    /// Input level mapped from -60…0 dBFS to 0…1, for drawing.
    var normalizedLevel: Double {
        let decibels = 20 * log10(Double(max(level, 0.00001)))
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
