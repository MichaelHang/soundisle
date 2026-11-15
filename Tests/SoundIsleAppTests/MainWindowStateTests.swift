import XCTest
@testable import SoundIsle

/// The main window, the mini player and the desktop lyrics each show a button
/// for "the main window". They can only agree if one rule decides it: the main
/// window is on screen when it is not hidden *and* the mini player has not
/// taken its place.
@MainActor
final class MainWindowStateTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("main-window-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testTheMiniPlayerTakesTheMainWindowOffScreen() {
        let model = AppModel(directory: directory)
        XCTAssertTrue(model.isMainWindowOnScreen)

        // What the player bar's compress button does.
        model.setMiniPlayerVisible(true)
        XCTAssertFalse(model.isMainWindowOnScreen)
        XCTAssertTrue(model.isMiniPlayerVisible)

        // Closing the mini player does not bring the main window back by
        // itself, so the surfaces must still say it is away.
        model.setMiniPlayerVisible(false)
        XCTAssertFalse(model.isMainWindowVisible)
        XCTAssertFalse(model.isMainWindowOnScreen)
    }

    func testShowingTheMainWindowAgainClearsTheMiniPlayer() {
        let model = AppModel(directory: directory)
        model.setMiniPlayerVisible(true)
        model.setMainWindowVisible(true)

        // The delegate hides the mini player when it brings the window up.
        model.setMiniPlayerVisible(false)

        XCTAssertTrue(model.isMainWindowOnScreen)
    }

    func testTheButtonReflectsTheMiniPlayerEvenIfAWindowFlagWasMissed() {
        let model = AppModel(directory: directory)
        model.setMainWindowVisible(true)
        model.setMiniPlayerVisible(true)

        // Whichever writer ran last, the mini player wins: its window covers
        // the same space, and a lit button for a window that is not there is
        // exactly the two-click bug.
        XCTAssertFalse(model.isMainWindowOnScreen)
    }
}
