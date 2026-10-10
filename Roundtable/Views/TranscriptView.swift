import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var store: CaptionStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.entries.isEmpty {
                        EmptyTranscriptView()
                    }
                    ForEach(store.entries) { entry in
                        CaptionRow(entry: entry)
                            .id(entry.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.entries) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
        }
    }

    private static let bottomID = "transcript-bottom"
}

private struct EmptyTranscriptView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How to use Roundtable")
                .font(.title3.weight(.semibold))
            tip("iphone.gen3", "Lay your phone flat in the middle of the table, with the top pointing away from you.")
            tip("mic.fill", "Tap Start. Captions appear as people speak, colored by where they sit.")
            tip("person.2.wave.2", "Friends can open Roundtable on their phones too. Phones with the same room code share captions, without needing the internet.")
            tip("arrow.left.arrow.right", "If left and right look swapped, flip them in Settings.")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
        }
        .font(.body)
    }
}
