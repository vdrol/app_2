import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CaptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var room = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Captions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Text size")
                        Slider(value: $store.fontSize, in: 16...56, step: 1) {
                            Text("Text size")
                        } minimumValueLabel: {
                            Image(systemName: "textformat.size.smaller")
                        } maximumValueLabel: {
                            Image(systemName: "textformat.size.larger")
                        }
                        Text("This is how captions look.")
                            .font(.system(size: store.fontSize, weight: .medium))
                    }
                    Toggle("Vibrate when a new person speaks", isOn: $store.hapticsEnabled)
                    LabeledContent("Language", value: languageName)
                    if let engine = store.engineName {
                        LabeledContent("Speech engine", value: engine)
                    }
                }

                Section {
                    Toggle("Swap left and right", isOn: $store.flipDirection)
                    VStack(alignment: .leading) {
                        Text("Direction sensitivity")
                        Slider(value: $store.sensitivity, in: 1...6) {
                            Text("Direction sensitivity")
                        } minimumValueLabel: {
                            Text("Low").font(.caption)
                        } maximumValueLabel: {
                            Text("High").font(.caption)
                        }
                    }
                } header: {
                    Text("Direction")
                } footer: {
                    Text("Lay the phone flat in the middle of the table with the top pointing away from you. Turn sensitivity up if everyone shows as \"\(store.zoneName(.center))\", or down if the needle jumps around. Direction needs an iPhone XS or later.")
                }

                Section {
                    ForEach(SpeakerZone.allCases) { zone in
                        HStack {
                            Circle()
                                .fill(zone.color)
                                .frame(width: 12, height: 12)
                            TextField(zone.defaultName, text: $store.zoneNames[zone.rawValue])
                                .textInputAutocapitalization(.words)
                        }
                    }
                    Button("Reset names") {
                        store.zoneNames = SpeakerZone.allCases.map(\.defaultName)
                    }
                } header: {
                    Text("Who sits where")
                } footer: {
                    Text("Name the seats, for example \"Mom\" on the left, so captions show who is talking.")
                }

                Section {
                    Toggle("Share with nearby phones", isOn: $store.sharingEnabled)
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                    HStack {
                        Text("Room code")
                        TextField(CaptionStore.defaultRoomCode, text: $room)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                } header: {
                    Text("Nearby sharing")
                } footer: {
                    Text("Phones with the same room code share captions over Wi‑Fi and Bluetooth, without the internet. Use your own code so other tables don't join.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                name = store.deviceName
                room = store.roomCode
            }
            .onDisappear {
                store.updateIdentity(name: name, room: room)
            }
        }
    }

    private var languageName: String {
        Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier
    }
}
