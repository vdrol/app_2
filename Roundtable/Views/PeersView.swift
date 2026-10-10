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
                    LabeledContent("This phone", value: store.deviceName)
                } footer: {
                    Text("Ask others at the table to open Roundtable and enter the same room code in Settings.")
                }

                Section("Connected phones") {
                    if !store.sharingEnabled {
                        Label("Sharing is off. Turn it on in Settings.", systemImage: "wifi.slash")
                            .foregroundStyle(.secondary)
                    } else if store.connectedPeers.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for phones nearby…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(store.connectedPeers, id: \.self) { name in
                            Label(name, systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }
                }

                Section("Why use several phones?") {
                    Text("Each phone captions the people nearest to it best. Put one at each end of a long table and everyone gets every word, labeled with the phone that heard it.")
                        .font(.callout)
                }
            }
            .navigationTitle("Nearby phones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
