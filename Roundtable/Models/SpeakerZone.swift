import SwiftUI

/// The table is split into five zones around the phone. Each zone gets its own
/// color and a name the user can change (for example "Mom" or "Sam").
enum SpeakerZone: Int, CaseIterable, Identifiable {
    case farLeft, left, center, right, farRight

    /// Zone edges on the -1…+1 direction scale.
    static let boundaries: [Double] = [-1, -0.6, -0.2, 0.2, 0.6, 1]

    var id: Int { rawValue }

    init(direction: Double) {
        switch direction {
        case ..<(-0.6): self = .farLeft
        case ..<(-0.2): self = .left
        case ...0.2: self = .center
        case ...0.6: self = .right
        default: self = .farRight
        }
    }

    var defaultName: String {
        switch self {
        case .farLeft: return "Far left"
        case .left: return "Left"
        case .center: return "Across"
        case .right: return "Right"
        case .farRight: return "Far right"
        }
    }

    var color: Color {
        switch self {
        case .farLeft: return .purple
        case .left: return .blue
        case .center: return .green
        case .right: return .orange
        case .farRight: return .pink
        }
    }

    var range: ClosedRange<Double> {
        Self.boundaries[rawValue]...Self.boundaries[rawValue + 1]
    }
}
