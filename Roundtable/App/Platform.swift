import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The few things that differ between iPhone/iPad and Mac, kept in one place.
enum Platform {
    @MainActor static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    /// "iPhone", "iPad" or "Mac", for instructions on screen.
    @MainActor static var deviceKind: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    @MainActor static var deviceSymbol: String {
        #if os(macOS)
        return "laptopcomputer"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone.gen3"
        #endif
    }

    #if os(macOS)
    @MainActor private static var awakeActivity: NSObjectProtocol?
    #endif

    /// Keeps the screen on while captioning so the captions stay visible.
    @MainActor static func setKeepAwake(_ keepAwake: Bool) {
        #if os(macOS)
        if keepAwake, awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "Showing live captions")
        } else if !keepAwake, let activity = awakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            awakeActivity = nil
        }
        #else
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        #endif
    }
}

/// Lets the user know that someone in a different seat started talking: a vibration on
/// iPhone, or a tap on a Force Touch trackpad on Mac.
@MainActor
final class SpeakerChangeFeedback {
    #if os(macOS)
    func signal() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    #else
    private let generator: UIImpactFeedbackGenerator

    init() {
        generator = UIImpactFeedbackGenerator(style: .medium)
    }

    func signal() {
        generator.impactOccurred()
    }
    #endif
}

extension Color {
    /// Background for caption cards. Works in light and dark mode on every platform.
    static let cardBackground = Color.primary.opacity(0.07)
}

extension View {
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func capitalizesWords() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.words)
        #endif
    }

    func capitalizesCharacters() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.characters)
        #endif
    }

    /// Sheets on Mac open at their minimum size, so give them room.
    func macSheetFrame() -> some View {
        #if os(macOS)
        frame(minWidth: 460, minHeight: 620)
        #else
        self
        #endif
    }
}
