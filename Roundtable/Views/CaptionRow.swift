import SwiftUI

struct CaptionRow: View {
    @EnvironmentObject private var store: CaptionStore
    let entry: CaptionEntry

    var body: some View {
        let style = store.style(for: entry)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(style.color)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let direction = entry.direction {
                        DirectionDial(direction: direction, lineWidth: 3)
                            .frame(width: 34, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(style.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style.color)
                    if !style.isLocal {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("from a nearby phone")
                    }
                    Spacer(minLength: 0)
                    Text(entry.startedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(entry.text)
                    .font(.system(size: store.fontSize, weight: .medium))
                    .foregroundStyle(entry.isFinal ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
