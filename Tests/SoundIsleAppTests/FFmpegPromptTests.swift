import XCTest
@testable import SoundIsle

final class FFmpegPromptTests: XCTestCase {
    func testStartsHidden() {
        XCTAssertFalse(FFmpegPrompt().isShown)
        XCTAssertNil(FFmpegPrompt().message)
    }

    func testShowingCarriesTheTrackMessage() {
        var prompt = FFmpegPrompt()
        prompt.show("需要 FFmpeg 才能播放此格式（《a.ape》）。")
        XCTAssertTrue(prompt.isShown)
        XCTAssertEqual(prompt.message, "需要 FFmpeg 才能播放此格式（《a.ape》）。")
    }

    /// The transition playback runs on every native track. It has to return,
    /// not recurse.
    func testClearingRemovesThePrompt() {
        var prompt = FFmpegPrompt()
        prompt.show("x")
        prompt.clear()
        XCTAssertFalse(prompt.isShown)
        XCTAssertNil(prompt.message)
    }

    func testClearingAHiddenPromptIsHarmless() {
        var prompt = FFmpegPrompt()
        prompt.clear()
        XCTAssertFalse(prompt.isShown)
    }
}
