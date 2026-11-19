import Foundation
import XCTest
@testable import SoundIsleCore

final class LyricsServiceTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("SoundIsleLyricsServiceTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? fm.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    private func makeCache() -> LyricsCache {
        LyricsCache(directory: tempDir.appendingPathComponent("lyrics", isDirectory: true))
    }

    @discardableResult
    private func makeTrack(
        _ name: String = "track",
        title: String = "母亲",
        artist: String = "阎维文",
        duration: TimeInterval = 215.4
    ) throws -> Track {
        let url = tempDir.appendingPathComponent("\(name).mp3")
        try Data("x".utf8).write(to: url)
        return Track(url: url, title: title, artist: artist, duration: duration)
    }

    private var overrideLyrics: Lyrics {
        Lyrics(lines: [LyricLine(time: 2, text: "覆盖歌词")], isSynced: true)
    }

    func testOverrideWinsOverSidecar() async throws {
        let track = try makeTrack()
        try Data("[00:03.00]侧载歌词\n".utf8)
            .write(to: tempDir.appendingPathComponent("track.lrc"))

        let cache = makeCache()
        try cache.saveOverride(overrideLyrics, for: track.id)
        let service = LyricsService(cache: cache)

        let resolved = await service.resolve(for: track)

        XCTAssertEqual(resolved?.origin, .override)
        XCTAssertEqual(resolved?.lyrics, overrideLyrics)
    }

    func testSidecarIsFoundAndParsed() async throws {
        let track = try makeTrack()
        let sidecar = tempDir.appendingPathComponent("track.lrc")
        try Data("[00:03.00]侧载第一句\n[00:04.00]侧载第二句\n".utf8).write(to: sidecar)

        let service = LyricsService(cache: makeCache())

        let resolved = await service.resolve(for: track)

        XCTAssertEqual(resolved?.origin, .sidecar)
        XCTAssertEqual(resolved?.sourceURL?.standardizedFileURL, sidecar.standardizedFileURL)
        XCTAssertEqual(resolved?.lyrics.isSynced, true)
        XCTAssertEqual(resolved?.lyrics.lines.map(\.text), ["侧载第一句", "侧载第二句"])
    }

    func testNoLyricsSourcesReturnsNil() async throws {
        let track = try makeTrack()

        let service = LyricsService(cache: makeCache())

        let resolved = await service.resolve(for: track)

        XCTAssertNil(resolved)
    }
}

final class LyricsDisplayStateTests: XCTestCase {
    private let trackA = UUID()
    private let trackB = UUID()
    private let lyricsA = Lyrics(lines: [LyricLine(time: 1, text: "A")], isSynced: true)
    private let lyricsB = Lyrics(lines: [LyricLine(time: 2, text: "B")], isSynced: true)

    func testTrackChangeClearsDisplayedLyricsSynchronously() {
        var state = LyricsDisplayState()
        state.beginLoading(trackID: trackA)
        state.finish(ResolvedLyrics(lyrics: lyricsA, origin: .sidecar), for: trackA)
        XCTAssertEqual(state.lyrics, lyricsA)
        XCTAssertEqual(state.origin, .sidecar)
        XCTAssertFalse(state.isResolving)

        let cleared = state.beginLoading(trackID: trackB)

        // Cleared before any await/resolution for track B.
        XCTAssertTrue(cleared)
        XCTAssertNil(state.lyrics)
        XCTAssertEqual(state.origin, .none)
        XCTAssertTrue(state.isResolving)
        XCTAssertEqual(state.trackID, trackB)
    }

    func testSameTrackRetryKeepsLyricsUntilResult() {
        var state = LyricsDisplayState()
        state.beginLoading(trackID: trackA)
        state.finish(ResolvedLyrics(lyrics: lyricsA, origin: .sidecar), for: trackA)

        let cleared = state.beginLoading(trackID: trackA)

        XCTAssertFalse(cleared)
        XCTAssertEqual(state.lyrics, lyricsA)
        XCTAssertEqual(state.origin, .sidecar)
        XCTAssertTrue(state.isResolving)
    }

    func testLateResultForPreviousTrackIsIgnored() {
        var state = LyricsDisplayState()
        state.beginLoading(trackID: trackA)
        state.beginLoading(trackID: trackB)

        state.finish(ResolvedLyrics(lyrics: lyricsA, origin: .override), for: trackA)

        XCTAssertNil(state.lyrics)
        XCTAssertTrue(state.isResolving)

        state.finish(ResolvedLyrics(lyrics: lyricsB, origin: .override), for: trackB)
        XCTAssertEqual(state.lyrics, lyricsB)
        XCTAssertFalse(state.isResolving)
    }

    func testNilTrackClearsEverything() {
        var state = LyricsDisplayState()
        state.beginLoading(trackID: trackA)
        state.finish(ResolvedLyrics(lyrics: lyricsA, origin: .override), for: trackA)

        let cleared = state.beginLoading(trackID: nil)

        XCTAssertTrue(cleared)
        XCTAssertNil(state.lyrics)
        XCTAssertNil(state.trackID)
        XCTAssertEqual(state.origin, .none)
        XCTAssertFalse(state.isResolving)
    }
}

final class LyricsCacheTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("SoundIsleLyricsCacheTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? fm.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    func testOverrideRoundtripAndRemoval() throws {
        let cache = LyricsCache(directory: tempDir.appendingPathComponent("lyrics", isDirectory: true))
        let trackID = UUID()
        let lyrics = Lyrics(lines: [LyricLine(time: 0, text: "纯文本")], isSynced: false)

        XCTAssertNil(cache.loadOverride(for: trackID))
        try cache.saveOverride(lyrics, for: trackID)
        XCTAssertEqual(cache.loadOverride(for: trackID), lyrics)

        try cache.removeOverride(for: trackID)
        XCTAssertNil(cache.loadOverride(for: trackID))
    }
}
