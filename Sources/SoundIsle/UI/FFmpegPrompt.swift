import Foundation

/// The one banner the track list still owns.
///
/// It is not a message: it is a persistent state with three ways out, and it
/// decides whether whole formats can play at all. Kept as a value type so the
/// transitions are exercised by a test rather than only through playback —
/// a helper that called itself here once took the app down on every track.
struct FFmpegPrompt: Equatable {
    private(set) var message: String?

    var isShown: Bool { message != nil }

    mutating func show(_ text: String) {
        message = text
    }

    mutating func clear() {
        message = nil
    }
}
