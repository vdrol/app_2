import SwiftUI

/// A half-circle seen from above the table, with this device at the bottom center.
/// The five colored arcs are the speaker zones; the needle points at the current speaker.
struct DirectionDial: View {
    var direction: Double?
    var active: Bool = true
    var lineWidth: CGFloat = 4
    /// Zone labels to draw around the arc; `nil` for the compact version used in caption rows.
    var zoneLabels: [String]? = nil

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, lineWidth: lineWidth)
            ZStack {
                Canvas { context, _ in
                    let highlighted = active ? direction.map { SpeakerZone(direction: $0) } : nil
                    for zone in SpeakerZone.allCases {
                        let path = layout.arc(from: zone.range.lowerBound, to: zone.range.upperBound)
                        let opacity = zone == highlighted ? 1 : 0.25
                        context.stroke(path,
                                       with: .color(zone.color.opacity(opacity)),
                                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    }
                    if active, let direction {
                        let tip = layout.point(direction: direction, radius: layout.radius)
                        var needle = Path()
                        needle.move(to: layout.center)
                        needle.addLine(to: tip)
                        context.stroke(needle, with: .color(.primary.opacity(0.6)),
                                       style: StrokeStyle(lineWidth: max(1.5, lineWidth / 3), lineCap: .round))
                        let dotSize = lineWidth * 1.8
                        let dot = Path(ellipseIn: CGRect(x: tip.x - dotSize / 2, y: tip.y - dotSize / 2,
                                                         width: dotSize, height: dotSize))
                        context.fill(dot, with: .color(.primary))
                    }
                }

                if let zoneLabels {
                    ForEach(SpeakerZone.allCases) { zone in
                        let middle = (zone.range.lowerBound + zone.range.upperBound) / 2
                        Text(zoneLabels[zone.rawValue])
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(zone.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 70)
                            .position(layout.point(direction: middle, radius: layout.radius - lineWidth - 16))
                    }
                    Image(systemName: Platform.deviceSymbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .position(x: layout.center.x, y: layout.center.y - 10)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard active, let direction else { return "No one speaking" }
        let zone = SpeakerZone(direction: direction)
        return "Speaker \(zoneLabels?[zone.rawValue] ?? zone.defaultName)"
    }

    /// Maps a direction (-1 left … +1 right) to a point on the half-circle.
    private struct Layout {
        let center: CGPoint
        let radius: CGFloat

        init(size: CGSize, lineWidth: CGFloat) {
            let padding = lineWidth / 2 + 2
            center = CGPoint(x: size.width / 2, y: size.height - padding)
            radius = max(4, min(size.width / 2, size.height) - padding)
        }

        func point(direction: Double, radius: CGFloat) -> CGPoint {
            // -1 → 180° (left), 0 → 90° (straight ahead), +1 → 0° (right).
            let angle = Double.pi / 2 - direction * Double.pi / 2
            return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                           y: center.y - radius * CGFloat(sin(angle)))
        }

        func arc(from start: Double, to end: Double) -> Path {
            var path = Path()
            let steps = 24
            for step in 0...steps {
                let value = start + (end - start) * Double(step) / Double(steps)
                let p = point(direction: value, radius: radius)
                if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            return path
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        DirectionDial(direction: -0.5, lineWidth: 14,
                      zoneLabels: SpeakerZone.allCases.map(\.defaultName))
            .frame(height: 140)
        DirectionDial(direction: 0.7, lineWidth: 3)
            .frame(width: 34, height: 18)
    }
    .padding()
}
