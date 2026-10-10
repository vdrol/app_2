import Foundation

/// One caption segment: roughly one sentence or phrase from one speaker.
/// It is also the message sent to nearby phones, so it must stay `Codable`.
struct CaptionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    /// Stable identifier of the phone that transcribed this caption.
    let deviceID: String
    var deviceName: String
    var text: String
    /// `false` while the recognizer is still revising the words.
    var isFinal: Bool
    /// Where the speaker was relative to the capturing phone, from -1 (left) to +1 (right).
    /// `nil` when the phone could not record in stereo.
    var direction: Double?
    let startedAt: Date
    var updatedAt: Date
}
