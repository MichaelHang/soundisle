import XCTest
@testable import SoundIsleCore

final class LibraryGroupingTests: XCTestCase {
    private let alpha = Track(
        url: URL(fileURLWithPath: "/tmp/01a.mp3"),
        title: "Alpha",
        artist: "阎维文",
        album: "Red",
        year: 1995,
        trackNumber: 1
    )
    private let beta = Track(
        url: URL(fileURLWithPath: "/tmp/02b.mp3"),
        title: "Beta",
        artist: "阎维文",
        album: "Red",
        year: 1995,
        trackNumber: 2
    )
    private let english = Track(
        url: URL(fileURLWithPath: "/tmp/Mother.mp3"),
        title: "Mother",
        artist: "John",
        album: "English"
    )

    func testAlbumGroupsTracksByAlbumName() {
        let groups = LibraryGrouping.groups([english, alpha, beta], by: .album)
        XCTAssertEqual(groups.map(\.name), ["English", "Red"])
        XCTAssertEqual(groups.first?.tracks.map(\.title), ["Mother"])
        XCTAssertEqual(groups.last?.tracks.map(\.title), ["Alpha", "Beta"])
    }

    func testAlbumGroupDetailCarriesArtistYearAndCount() {
        let groups = LibraryGrouping.groups([alpha, beta], by: .album)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.detail, "阎维文 · 1995 · 2 首")
    }

    func testAlbumGroupCarriesCardFields() {
        let groups = LibraryGrouping.groups([alpha, beta], by: .album)
        XCTAssertEqual(groups.first?.artist, "阎维文")
        XCTAssertEqual(groups.first?.year, 1995)
        XCTAssertFalse(groups.first?.isCompilation ?? true)
    }

    func testCompilationAlbumReportsVariousArtists() {
        let guest = Track(
            url: URL(fileURLWithPath: "/tmp/03c.mp3"),
            title: "Gamma",
            artist: "王菲",
            album: "Red",
            year: 1995,
            trackNumber: 3
        )
        let groups = LibraryGrouping.groups([alpha, beta, guest], by: .album)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.artist, L("群星"))
        XCTAssertTrue(groups.first?.isCompilation ?? false)
        XCTAssertEqual(groups.first?.detail, "\(L("群星")) · 1995 · \(Lf("%d 首", 3))")
    }

    func testAlbumWithoutArtistsReportsUnknownArtist() {
        let orphan = Track(url: URL(fileURLWithPath: "/tmp/01x.mp3"), title: "X", album: "Red")
        let groups = LibraryGrouping.groups([orphan], by: .album)
        XCTAssertEqual(groups.first?.artist, L("未知艺人"))
    }

    func testConsistentAlbumArtistTagNamesAMultiArtistAlbum() {
        let one = Track(
            url: URL(fileURLWithPath: "/tmp/01c.mp3"),
            title: "One",
            artist: "王菲",
            album: "Red",
            albumArtist: "群星",
            year: 1995,
            trackNumber: 1
        )
        let two = Track(
            url: URL(fileURLWithPath: "/tmp/02d.mp3"),
            title: "Two",
            artist: "孙燕姿",
            album: "Red",
            albumArtist: "群星",
            year: 1995,
            trackNumber: 2
        )
        let groups = LibraryGrouping.groups([one, two], by: .album)
        XCTAssertEqual(groups.first?.artist, "群星")
        XCTAssertTrue(groups.first?.isCompilation ?? false)
    }

    func testSingleTrackArtistOverridesALazyVariousArtistsTag() {
        let one = Track(
            url: URL(fileURLWithPath: "/tmp/01c.mp3"),
            title: "One",
            artist: "王菲",
            album: "Red",
            albumArtist: "群星",
            trackNumber: 1
        )
        let two = Track(
            url: URL(fileURLWithPath: "/tmp/02d.mp3"),
            title: "Two",
            artist: "王菲",
            album: "Red",
            albumArtist: "群星",
            trackNumber: 2
        )
        let groups = LibraryGrouping.groups([one, two], by: .album)
        XCTAssertEqual(groups.first?.artist, "王菲")
        XCTAssertFalse(groups.first?.isCompilation ?? true)
    }

    func testAlbumArtistTagRescuesTracksWithoutArtists() {
        let orphan = Track(
            url: URL(fileURLWithPath: "/tmp/01x.mp3"),
            title: "X",
            album: "Red",
            albumArtist: "周杰伦"
        )
        let groups = LibraryGrouping.groups([orphan], by: .album)
        XCTAssertEqual(groups.first?.artist, "周杰伦")
    }

    func testInconsistentAlbumArtistTagsFallBackToTrackArtists() {
        let one = Track(
            url: URL(fileURLWithPath: "/tmp/01c.mp3"),
            title: "One",
            artist: "王菲",
            album: "Red",
            albumArtist: "群星",
            trackNumber: 1
        )
        let two = Track(
            url: URL(fileURLWithPath: "/tmp/02d.mp3"),
            title: "Two",
            artist: "孙燕姿",
            album: "Red",
            albumArtist: "S.H.E",
            trackNumber: 2
        )
        let groups = LibraryGrouping.groups([one, two], by: .album)
        XCTAssertEqual(groups.first?.artist, L("群星"))
        XCTAssertTrue(groups.first?.isCompilation ?? false)
    }

    func testArtistGroupCarriesOwnNameWithoutYear() {
        let groups = LibraryGrouping.groups([alpha, beta], by: .artist)
        XCTAssertEqual(groups.first?.artist, "阎维文")
        XCTAssertNil(groups.first?.year)
        XCTAssertFalse(groups.first?.isCompilation ?? true)
    }

    func testAlbumGroupTracksBreakTrackNumberTiesByTitle() {
        let tied = Track(
            url: URL(fileURLWithPath: "/tmp/01c.mp3"),
            title: "Gamma",
            artist: "阎维文",
            album: "Red",
            trackNumber: 1
        )
        let groups = LibraryGrouping.groups([beta, tied, alpha], by: .album)
        XCTAssertEqual(groups.first?.tracks.map(\.title), ["Alpha", "Gamma", "Beta"])
    }

    func testAlbumGroupTracksWithoutNumbersSortByTitle() {
        let untitled = Track(
            url: URL(fileURLWithPath: "/tmp/no.mp3"),
            title: "Delta",
            artist: "阎维文",
            album: "Red"
        )
        let groups = LibraryGrouping.groups([alpha, untitled], by: .album)
        XCTAssertEqual(groups.first?.tracks.map(\.title), ["Alpha", "Delta"])
    }

    func testUnknownAlbumSinksToTheBottom() {
        let unknown = Track(url: URL(fileURLWithPath: "/tmp/loose.mp3"), title: "Loose")
        let groups = LibraryGrouping.groups([unknown, english], by: .album)
        XCTAssertEqual(groups.last?.name, "未知专辑")
        XCTAssertEqual(groups.first?.name, "English")
    }

    func testArtistGroupsListAlbumsAndTracks() {
        let groups = LibraryGrouping.groups([alpha, beta, english], by: .artist)
        XCTAssertEqual(groups.map(\.name), ["阎维文", "John"])
        XCTAssertEqual(groups.first?.detail, "1 张专辑 · 2 首")
    }

    func testArtistGroupsOrderTracksByAlbumThenTrackNumber() {
        let followUp = Track(
            url: URL(fileURLWithPath: "/tmp/01z.mp3"),
            title: "Zeta",
            artist: "阎维文",
            album: "Blue"
        )
        let groups = LibraryGrouping.groups([followUp, beta, alpha], by: .artist)
        XCTAssertEqual(groups.first?.tracks.map(\.title), ["Zeta", "Alpha", "Beta"])
    }

    func testUnknownArtistSinksToTheBottom() {
        let unknown = Track(url: URL(fileURLWithPath: "/tmp/loose.mp3"), title: "Loose")
        let groups = LibraryGrouping.groups([unknown, english], by: .artist)
        XCTAssertEqual(groups.last?.name, "未知艺人")
        XCTAssertEqual(groups.first?.name, "John")
    }
}

    func testAlbumArtistGroupsByAlbumArtistTag() {
        // 专辑艺术家标签优先：钢琴曲没有歌手，归到演奏家名下。
        var piano = Track(
            url: URL(fileURLWithPath: "/tmp/piano.flac"),
            title: "Merry-Go-Round",
            artist: "久石让",
            album: "Piano Stories"
        )
        piano.albumArtist = "Joe Hisaishi"

        let groups = LibraryGrouping.groups([piano], by: .albumArtist)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "Joe Hisaishi")
        XCTAssertEqual(groups.first?.detail, Lf("%d 张专辑", 1) + " · " + Lf("%d 首", 1))
    }

    func testAlbumArtistFallsBackToTrackArtist() {
        let track = Track(
            url: URL(fileURLWithPath: "/tmp/01.mp3"),
            title: "晴天",
            artist: "周杰伦",
            album: "叶惠美"
        )

        let groups = LibraryGrouping.groups([track], by: .albumArtist)
        XCTAssertEqual(groups.first?.name, "周杰伦")
    }

    func testAlbumArtistAndArtistViewsGroupTheSameTrackDifferently() {
        var byAlbumArtist = Track(
            url: URL(fileURLWithPath: "/tmp/01.mp3"),
            title: "One",
            artist: "群星",
            album: "Red",
            albumArtist: "王菲"
        )
        byAlbumArtist.albumArtist = "王菲"

        let albumArtistGroups = LibraryGrouping.groups([byAlbumArtist], by: .albumArtist)
        let artistGroups = LibraryGrouping.groups([byAlbumArtist], by: .artist)
        XCTAssertEqual(albumArtistGroups.first?.name, "王菲")
        XCTAssertEqual(artistGroups.first?.name, "群星")
    }
