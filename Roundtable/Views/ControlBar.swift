import SwiftUI

struct ControlBar: View {
    @EnvironmentObject private var store: CaptionStore
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if let status = store.statusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(status)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ShareLink(item: store.transcriptText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .disabled(store.entries.isEmpty)
                .accessibilityLabel("Share transcript")

                Button {
                    store.toggleListening()
                } label: {
                    Label(store.isListening ? "Stop" : "Start captions",
                          systemImage: store.isListening ? "stop.fill" : "mic.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(store.isListening ? Color.red : Color.accentColor)
                .disabled(store.isStarting)

                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                }
                .disabled(store.entries.isEmpty)
                .accessibilityLabel("Clear transcript")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .confirmationDialog("Clear the transcript?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { store.clear() }
        }
    }
}
