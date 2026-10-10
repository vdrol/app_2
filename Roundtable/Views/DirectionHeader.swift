import SwiftUI

/// The live "who is talking" panel at the top of the screen.
struct DirectionHeader: View {
    @EnvironmentObject private var store: CaptionStore
    @ObservedObject var meter: LiveMeter

    var body: some View {
        VStack(spacing: 6) {
            DirectionDial(direction: meter.direction,
                          active: store.isListening && store.directionAvailable,
                          lineWidth: 14,
                          zoneLabels: SpeakerZone.allCases.map { store.zoneName($0) })
                .frame(height: 130)
                .frame(maxWidth: 380)

            Text(title)
                .font(.headline)
                .foregroundStyle(titleColor)
                .animation(.easeOut(duration: 0.15), value: title)

            if store.isListening {
                LevelBar(level: meter.normalizedLevel)
                    .frame(height: 6)
                    .frame(maxWidth: 220)
            }

            if store.isListening && !store.directionAvailable {
                Label("\(store.activeInputName ?? "This microphone") is mono, so direction is off. Choose a stereo mic in Settings to turn it on. Captions still work.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var currentZone: SpeakerZone? {
        guard store.isListening, store.directionAvailable, let direction = meter.direction else { return nil }
        return SpeakerZone(direction: direction)
    }

    private var title: String {
        if let currentZone { return store.zoneName(currentZone) }
        return store.isListening ? "Listening…" : "Tap Start to caption the table"
    }

    private var titleColor: Color {
        currentZone?.color ?? .secondary
    }
}

struct LevelBar: View {
    var level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * level)
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .accessibilityHidden(true)
    }
}
