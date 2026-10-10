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
                    Toggle(Self.feedbackLabel, isOn: $store.hapticsEnabled)
                    LabeledContent("Language", value: languageName)
                    if let engine = store.engineName {
                        LabeledContent("Speech engine", value: engine)
                    }
                }

                Section {
                    Picker("Input", selection: inputSelection) {
                        Text("Automatic").tag(AudioInputOption.automaticID)
                        ForEach(store.inputOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    if store.isListening {
                        LabeledContent("Now using", value: activeInputDescription)
                    }
                    if store.selectedInputChannelCount > 2 {
                        Picker("Left channel", selection: $store.leftChannel) {
                            ForEach(0..<store.selectedInputChannelCount, id: \.self) { channel in
                                Text("Input \(channel + 1)").tag(channel)
                            }
                        }
                        Picker("Right channel", selection: $store.rightChannel) {
                            ForEach(0..<store.selectedInputChannelCount, id: \.self) { channel in
                                Text("Input \(channel + 1)").tag(channel)
                            }
                        }
                    }
                } header: {
                    Text("Microphone")
                } footer: {
                    Text(Self.microphoneFooter)
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
                    Text("Put the device or microphone in the middle of the table, with its left side on your left. Turn sensitivity up if everyone shows as \"\(store.zoneName(.center))\", or down if the needle jumps around.")
                }

                Section {
                    ForEach(SpeakerZone.allCases) { zone in
                        HStack {
                            Circle()
                                .fill(zone.color)
                                .frame(width: 12, height: 12)
                            TextField(zone.defaultName, text: $store.zoneNames[zone.rawValue])
                                .capitalizesWords()
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
                    Toggle("Share with nearby devices", isOn: $store.sharingEnabled)
                    TextField("Your name", text: $name)
                        .capitalizesWords()
                        .submitLabel(.done)
                    HStack {
                        Text("Room code")
                        TextField(CaptionStore.defaultRoomCode, text: $room)
                            .multilineTextAlignment(.trailing)
                            .capitalizesCharacters()
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                } header: {
                    Text("Nearby sharing")
                } footer: {
                    Text("iPhones, iPads and Macs with the same room code share captions over Wi‑Fi and Bluetooth, without the internet. Use your own code so other tables don't join.")
                }
            }
            .navigationTitle("Settings")
            .formStyle(.grouped)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                store.refreshInputs()
                name = store.deviceName
                room = store.roomCode
            }
            .onDisappear {
                store.updateIdentity(name: name, room: room)
            }
        }
    }

    private var inputSelection: Binding<String> {
        Binding(get: { store.selectedInputID }, set: { store.selectInput($0) })
    }

    private var activeInputDescription: String {
        let name = store.activeInputName ?? "Microphone"
        let channels = store.activeChannelCount
        return channels >= 2 ? "\(name), \(channels) channels" : "\(name), mono"
    }

    #if os(macOS)
    private static let feedbackLabel = "Tap the trackpad when a new person speaks"
    private static let microphoneFooter = "Direction needs two or more channels. Most MacBook built-in mics are mono. A stereo USB microphone or an audio interface with two mics gives direction on any Mac."
    #else
    private static let feedbackLabel = "Vibrate when a new person speaks"
    private static let microphoneFooter = "Direction needs two or more channels. Automatic uses the built-in mics in stereo (iPhone XS and later, some iPads). A stereo USB microphone works on any iPhone or iPad."
    #endif

    private var languageName: String {
        Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier
    }
}
