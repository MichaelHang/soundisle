import XCTest
@testable import SoundIsleCore

final class AppInfoTests: XCTestCase {
    func testDisplayNameAndBundleID() {
        XCTAssertEqual(AppInfo.displayName, "空山")
        XCTAssertEqual(AppInfo.bundleIdentifier, "com.local.soundisle")
        XCTAssertEqual(AppInfo.minimumMacOS, "12.0")
    }
}
