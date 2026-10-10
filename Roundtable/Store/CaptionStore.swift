import AVFoundation
import Speech
import SwiftUI

/// App state: the transcript, listening state, nearby phones, and settings.
@MainActor
final class CaptionStore: ObservableObject {
    struct SpeakerStyle {
        var label: String
        var color: Color
        var isLocal: Bool
    }

    private enum Keys {
        static let deviceID = "deviceID"
        static let deviceName = "deviceName"
        static let roomCode = "roomCode"
        static let sharingEnabled = "sharingEnabled"
        static let fontSize = "fontSize"
        static let flipDirection = "flipDirection"
        static let sensitivity = "sensitivity"
        static let hapticsEnabled = "hapticsEnabled"
        static let zoneNames = "zoneNames"
        static let inputID = "inputID"
        static let leftChannel = "leftChannel"
        static let rightChannel = "rightChannel"
    }

    static let maxEntries = 600
    static let defaultRoomCode = "TABLE"

    // MARK: Published state

    @Published private(set) var entries: [CaptionEntry] = []
    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var directionAvailable = false
    @Published private(set) var connectedPeers: [String] = []
    @Published private(set) var engineName: String?
    @Published private(set) var inputOptions: [AudioInputOption] = []
    @Published private(set) var selectedInputID: String
    /// Channel count of the active input, or 0 before the first start.
    @Published private(set) var activeChannelCount = 0
    @Published private(set) var activeInputName: String?
    let meter: LiveMeter

    // MARK: Settings

    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }
    @Published var flipDirection: Bool {
        didSet {
            defaults.set(flipDirection, forKey: Keys.flipDirection)
            applyDirectionSettings()
        }
    }
    @Published var sensitivity: Double {
        didSet {
            defaults.set(sensitivity, forKey: Keys.sensitivity)
            applyDirectionSettings()
        }
    }
    /// For inputs with more than two channels: which ones are left and right (0-based).
    @Published var leftChannel: Int {
        didSet {
            defaults.set(leftChannel, forKey: Keys.leftChannel)
            applyDirectionSettings()
        }
    }
    @Published var rightChannel: Int {
        didSet {
            defaults.set(rightChannel, forKey: Keys.rightChannel)
            applyDirectionSettings()
        }
    }
    @Published var zoneNames: [String] {
        didSet { defaults.set(zoneNames, forKey: Keys.zoneNames) }
    }
    @Published var sharingEnabled: Bool {
        didSet {
            defaults.set(sharingEnabled, forKey: Keys.sharingEnabled)
            updateSharing()
        }
    }
    @Published private(set) var deviceName: String
    @Published private(set) var roomCode: String

    // MARK: Private

    let deviceID: String
    private let defaults = UserDefaults.standard
    private let audio = AudioCaptureEngine()
    private let peers: PeerSession
    private var transcriber: CaptionTranscriber?
    private var meterTimer: Timer?
    private var currentLocalID: UUID?
    private var lastLocalZone: SpeakerZone?
    private var lastBroadcast = Date.distantPast
    private let feedback: SpeakerChangeFeedback
    private var interruptionObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: Keys.deviceID) ?? UUID().uuidString
        defaults.set(id, forKey: Keys.deviceID)
        deviceID = id
        meter = LiveMeter()
        feedback = SpeakerChangeFeedback()

        let name = defaults.string(forKey: Keys.deviceName) ?? Platform.deviceName
        deviceName = name
        roomCode = defaults.string(forKey: Keys.roomCode) ?? Self.defaultRoomCode
        sharingEnabled = defaults.object(forKey: Keys.sharingEnabled) as? Bool ?? true
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 26
        hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        flipDirection = defaults.bool(forKey: Keys.flipDirection)
        sensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? 3
        selectedInputID = defaults.string(forKey: Keys.inputID) ?? AudioInputOption.automaticID
        leftChannel = defaults.object(forKey: Keys.leftChannel) as? Int ?? 0
        rightChannel = defaults.object(forKey: Keys.rightChannel) as? Int ?? 1
        let savedNames = defaults.stringArray(forKey: Keys.zoneNames) ?? []
        zoneNames = SpeakerZone.allCases.map { zone in
            zone.rawValue < savedNames.count ? savedNames[zone.rawValue] : zone.defaultName
        }

        peers = PeerSession(deviceID: id, displayName: name)
        // PeerSession calls these on the main thread.
        peers.onCaption = { [weak self] entry in
            guard let self else { return }
            MainActor.assumeIsolated { self.receive(entry) }
        }
        peers.onPeersChanged = { [weak self] names in
            guard let self else { return }
            MainActor.assumeIsolated { self.connectedPeers = names }
        }
        peers.onError = { [weak self] error in
            guard let self else { return }
            let message = "Couldn't look for nearby phones: \(error.localizedDescription)"
            MainActor.assumeIsolated { self.errorMessage = message }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated {
                // A phone call or Siri took the microphone.
                Task { await self.stopListening() }
            }
        }

        applyDirectionSettings()
        updateSharing()
    }

    // MARK: - Listening

    func toggleListening() {
        Task {
            if isListening {
                await stopListening()
            } else {
                await startListening()
            }
        }
    }

    func startListening() async {
        guard !isListening, !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer {
            isStarting = false
            statusMessage = nil
        }

        do {
            try await requestPermissions()

            if transcriber == nil {
                statusMessage = "Preparing the on-device speech model…"
                transcriber = try await TranscriberFactory.makeTranscriber(locale: Locale.current)
            }
            guard let transcriber else { return }
            engineName = transcriber.engineName

            transcriber.onResult = { [weak self] text, isFinal in
                guard let self else { return }
                // `DispatchQueue.main` keeps results in order, unlike separate Tasks.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.handleLocal(text: text, isFinal: isFinal) }
                }
            }
            transcriber.onError = { [weak self] error in
                guard let self else { return }
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.errorMessage = message }
                }
            }
            audio.onMonoBuffer = { [weak transcriber] buffer in
                transcriber?.append(buffer)
            }

            statusMessage = "Starting microphone…"
            applyDirectionSettings()
            try await transcriber.start()
            try audio.start(preferredInputID: selectedInputID)

            activeChannelCount = audio.channelCount
            activeInputName = audio.inputName
            directionAvailable = audio.isStereo
            isListening = true
            Platform.setKeepAwake(true)
            startMeter()
        } catch {
            audio.stop()
            await transcriber?.stop()
            errorMessage = error.localizedDescription
        }
    }

    func stopListening() async {
        guard isListening else { return }
        isListening = false
        audio.stop()
        stopMeter()
        await transcriber?.stop()
        Platform.setKeepAwake(false)
    }

    // MARK: - Microphone choice

    func refreshInputs() {
        inputOptions = audio.availableInputs()
    }

    /// Switches microphone, restarting capture if it's running.
    func selectInput(_ id: String) {
        guard id != selectedInputID else { return }
        selectedInputID = id
        defaults.set(id, forKey: Keys.inputID)
        guard isListening else { return }
        Task {
            await stopListening()
            await startListening()
        }
    }

    /// Channels of the selected input: measured once it's running, otherwise as reported
    /// by the device (Mac) or unknown (0).
    var selectedInputChannelCount: Int {
        if isListening { return activeChannelCount }
        if let option = inputOptions.first(where: { $0.id == selectedInputID }), let count = option.channelCount {
            return count
        }
        return activeChannelCount
    }

    private func requestPermissions() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw TranscriptionError.microphonePermissionDenied
        }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriptionError.speechPermissionDenied }
    }

    private func applyDirectionSettings() {
        audio.estimator.configure(gain: sensitivity, flipped: flipDirection,
                                  leftChannel: leftChannel, rightChannel: rightChannel)
    }

    // MARK: - Meter

    private func startMeter() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.pollMeter() }
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        meter.direction = nil
        meter.level = 0
    }

    private func pollMeter() {
        let snapshot = audio.estimator.snapshot()
        if meter.direction != snapshot.direction { meter.direction = snapshot.direction }
        if meter.level != snapshot.level { meter.level = snapshot.level }
    }

    // MARK: - Captions

    private func handleLocal(text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            // The segment ended without any words, so drop its placeholder.
            guard isFinal else { return }
            _ = audio.estimator.takeUtteranceDirection()
            if let id = currentLocalID, let index = entries.lastIndex(where: { $0.id == id }) {
                var removed = entries.remove(at: index)
                removed.isFinal = true
                removed.text = ""
                broadcast(removed, force: true)
            }
            currentLocalID = nil
            return
        }

        let now = Date()
        let direction = isFinal
            ? audio.estimator.takeUtteranceDirection()
            : audio.estimator.peekUtteranceDirection()

        var entry: CaptionEntry
        if let id = currentLocalID, let index = entries.lastIndex(where: { $0.id == id }) {
            entry = entries[index]
            entry.text = trimmed
            entry.isFinal = isFinal
            entry.updatedAt = now
            if let direction { entry.direction = direction }
            entries[index] = entry
        } else {
            entry = CaptionEntry(id: UUID(), deviceID: deviceID, deviceName: deviceName,
                                 text: trimmed, isFinal: isFinal, direction: direction,
                                 startedAt: now, updatedAt: now)
            append(entry)
            signalSpeakerChangeIfNeeded(direction: direction)
        }

        currentLocalID = isFinal ? nil : entry.id
        if isFinal, let finalDirection = entry.direction {
            lastLocalZone = SpeakerZone(direction: finalDirection)
        }
        broadcast(entry, force: isFinal)
    }

    /// One short vibration when someone in a different part of the table starts talking.
    /// If you can't hear well, this tells you to look up.
    private func signalSpeakerChangeIfNeeded(direction: Double?) {
        guard hapticsEnabled, let direction else { return }
        let zone = SpeakerZone(direction: direction)
        if let lastLocalZone, lastLocalZone != zone {
            feedback.signal()
        }
        lastLocalZone = zone
    }

    private func receive(_ entry: CaptionEntry) {
        guard entry.deviceID != deviceID else { return }
        if let index = entries.lastIndex(where: { $0.id == entry.id }) {
            // Unreliable in-progress updates can arrive after the final version.
            if entries[index].isFinal && !entry.isFinal { return }
            if entry.isFinal && entry.text.isEmpty {
                entries.remove(at: index)
            } else {
                entries[index] = entry
            }
        } else if !entry.text.isEmpty {
            append(entry)
        }
    }

    private func append(_ entry: CaptionEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    private func broadcast(_ entry: CaptionEntry, force: Bool) {
        guard sharingEnabled, !connectedPeers.isEmpty else { return }
        let now = Date()
        // At most four in-progress updates a second; final captions always go out.
        guard force || now.timeIntervalSince(lastBroadcast) >= 0.25 else { return }
        lastBroadcast = now
        peers.send(entry)
    }

    func clear() {
        entries.removeAll()
        currentLocalID = nil
        lastLocalZone = nil
    }

    // MARK: - Presentation

    func style(for entry: CaptionEntry) -> SpeakerStyle {
        guard entry.deviceID == deviceID else {
            return SpeakerStyle(label: entry.deviceName, color: Self.remoteColor(for: entry.deviceID), isLocal: false)
        }
        guard let direction = entry.direction else {
            return SpeakerStyle(label: "Speaker", color: .gray, isLocal: true)
        }
        let zone = SpeakerZone(direction: direction)
        return SpeakerStyle(label: zoneName(zone), color: zone.color, isLocal: true)
    }

    func zoneName(_ zone: SpeakerZone) -> String {
        let name = zoneNames[zone.rawValue].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? zone.defaultName : name
    }

    private static func remoteColor(for deviceID: String) -> Color {
        let palette: [Color] = [.teal, .indigo, .mint, .brown, .cyan, .red]
        let hash = deviceID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    var transcriptText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return entries
            .filter { $0.isFinal }
            .map { "[\(formatter.string(from: $0.startedAt))] \(style(for: $0).label): \($0.text)" }
            .joined(separator: "\n")
    }

    // MARK: - Sharing

    func updateIdentity(name: String, room: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRoom = String(room.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(12))
        let newName = cleanName.isEmpty ? Platform.deviceName : cleanName
        let newRoom = cleanRoom.isEmpty ? Self.defaultRoomCode : cleanRoom
        guard newName != deviceName || newRoom != roomCode else { return }

        deviceName = newName
        roomCode = newRoom
        defaults.set(newName, forKey: Keys.deviceName)
        defaults.set(newRoom, forKey: Keys.roomCode)
        updateSharing()
    }

    private func updateSharing() {
        if sharingEnabled {
            peers.start(room: roomCode, displayName: deviceName)
        } else {
            peers.stop()
            connectedPeers = []
        }
    }
}
