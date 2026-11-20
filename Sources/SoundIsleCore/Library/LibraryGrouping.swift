import Foundation

/// What the sidebar's 专辑/艺人 views group the library by.
public enum TrackGroupKind {
    case album
    case artist
}

/// One group in the album/artist browser. `detail` is fully formatted here so
/// the view layer only lays out `name` and `detail`; the empty-name labels
/// (未知专辑/未知艺人) live in the core so grouping tests share them.
///
/// `artist`, `year` and `isCompilation` feed the card grid: an album whose
/// tracks carry several distinct artists reports 群星 as its artist so a
/// compilation never masquerades as one performer's record.
public struct TrackGroup: Identifiable, Hashable {
    public let name: String
    public let detail: String
    public let tracks: [Track]
    public let artist: String
    public let year: Int?
    public let isCompilation: Bool

    public var id: String { name }

    public init(
        name: String,
        detail: String,
        tracks: [Track],
        artist: String,
        year: Int? = nil,
        isCompilation: Bool = false
    ) {
        self.name = name
        self.detail = detail
        self.tracks = tracks
        self.artist = artist
        self.year = year
        self.isCompilation = isCompilation
    }
}

/// Pure grouping for the album/artist browser. The order of groups and of the
/// tracks inside each group is deterministic, so the view can render without
/// any extra sorting state. Search filtering happens upstream.
public enum LibraryGrouping {
    public static func groups(_ tracks: [Track], by kind: TrackGroupKind) -> [TrackGroup] {
        switch kind {
        case .album: return albumGroups(tracks)
        case .artist: return artistGroups(tracks)
        }
    }

    // MARK: - Albums

    private static func albumGroups(_ tracks: [Track]) -> [TrackGroup] {
        Dictionary(grouping: tracks, by: { $0.album })
            .map { album, tracks in
                let sorted = tracks.sorted(by: albumTrackOrder)
                let trackArtists = Set(sorted.map { $0.artist }.filter { !$0.isEmpty })
                let artist = displayArtist(of: sorted, trackArtists: trackArtists)
                let year = sorted.first(where: { $0.year != nil })?.year
                var parts = [artist]
                if let year { parts.append(String(year)) }
                parts.append(Lf("%d 首", sorted.count))
                return TrackGroup(
                    name: album.isEmpty ? L("未知专辑") : album,
                    detail: parts.joined(separator: " · "),
                    tracks: sorted,
                    artist: artist,
                    year: year,
                    isCompilation: trackArtists.count > 1
                )
            }
            .sorted { lhs, rhs in
                // 未知专辑 stays at the bottom; everything else alphabetical.
                switch (isUnknownAlbum(lhs.name), isUnknownAlbum(rhs.name)) {
                case (true, false): return false
                case (false, true): return true
                default:
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    private static func isUnknownAlbum(_ name: String) -> Bool {
        name == L("未知专辑")
    }

    /// The name an album is presented under. A single track artist wins — it
    /// also overrides a lazy 群星 tag on a one-artist album. Otherwise a
    /// consistent 专辑艺人 (albumArtist) tag names the album; several unlabeled
    /// artists mean a compilation (群星), and nothing at all is 未知艺人.
    private static func displayArtist(of tracks: [Track], trackArtists: Set<String>) -> String {
        if trackArtists.count == 1, let artist = trackArtists.first {
            return artist
        }
        let albumArtists = Set(tracks.compactMap { $0.albumArtist }.filter { !$0.isEmpty })
        if albumArtists.count == 1, let artist = albumArtists.first {
            return artist
        }
        return trackArtists.isEmpty ? L("未知艺人") : L("群星")
    }

    private static func albumTrackOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        let lhsNumber = lhs.trackNumber
        let rhsNumber = rhs.trackNumber
        switch (lhsNumber, rhsNumber) {
        case (nil, nil): break
        case (nil, _?): return false
        case (_?, nil): return true
        case (let l?, let r?):
            if l != r { return l < r }
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    // MARK: - Artists

    private static func artistGroups(_ tracks: [Track]) -> [TrackGroup] {
        Dictionary(grouping: tracks, by: { $0.artist })
            .map { artist, tracks in
                let sorted = tracks.sorted(by: artistTrackOrder)
                let albums = Set(sorted.map { $0.album }.filter { !$0.isEmpty }).count
                let name = artist.isEmpty ? L("未知艺人") : artist
                return TrackGroup(
                    name: name,
                    detail: [Lf("%d 张专辑", albums), Lf("%d 首", sorted.count)]
                        .joined(separator: " · "),
                    tracks: sorted,
                    artist: name
                )
            }
            .sorted { lhs, rhs in
                // 未知艺人 stays at the bottom; everything else alphabetical.
                switch (lhs.name == L("未知艺人"), rhs.name == L("未知艺人")) {
                case (true, false): return false
                case (false, true): return true
                default:
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    private static func artistTrackOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        let albumOrder = lhs.album.localizedStandardCompare(rhs.album)
        if albumOrder != .orderedSame { return albumOrder == .orderedAscending }
        return albumTrackOrder(lhs, rhs)
    }
}
