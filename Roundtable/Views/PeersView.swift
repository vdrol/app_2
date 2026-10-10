import SwiftUI

struct PeersView: View {
    @EnvironmentObject private var store: CaptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Room code") {
                        Text(store.roomCode)
                            .font(.title2.monospaced().weight(.bold))
                    }
                    LabeledContent("This device", value: store.deviceName)
                } footer: {
                    Text("Ask others at the table to open Roundtable on their iPhone, iPad or Mac and enter the same room code in Settings.")
                }

                Section("Connected devices") {
                    if !store.sharingEnabled {
                        Label("Sharing is off. Turn it on in Settings.", systemImage: "wifi.slash")
                            .foregroundStyle(.secondary)
                    } else if store.connectedPeers.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for devices nearby…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(store.connectedPeers, id: \.self) { name in
                            Label(name, systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                }

                Section("Why use several devices?") {
                    Text("Each device captions the people nearest to it best. Put one at each end of a long table and everyone gets every word, labeled with the device that heard it.")
                        .font(.callout)
                }
            }
            .navigationTitle("Nearby devices")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
