import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CaptionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showPeers = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DirectionHeader(meter: store.meter)
                Divider()
                TranscriptView()
                ControlBar()
            }
            .navigationTitle("Roundtable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showPeers = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.wave.2")
                            Text("\(store.connectedPeers.count)")
                                .monospacedDigit()
                        }
                    }
                    .accessibilityLabel("Nearby phones: \(store.connectedPeers.count)")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(store)
            }
            .sheet(isPresented: $showPeers) {
                PeersView().environmentObject(store)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Without a background audio mode iOS suspends the microphone, so stop cleanly.
            if phase == .background {
                Task { await store.stopListening() }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CaptionStore())
}
