import Foundation

public struct LibraryIndex: Codable {
    public var tracks: [Track]
    public var folders: [URL]
    /// Files the user removed from the library (从音乐库移除). A rescan never
    /// re-adds these, even when the file is still on disk; Settings lists them
    /// and re-adds only on explicit user action. Entries whose file no longer
    /// exists on disk are pruned by every scan.
    public var removedTracks: [Track]

    public init(tracks: [Track] = [], folders: [URL] = [], removedTracks: [Track] = []) {
        self.tracks = tracks
        self.folders = folders
        self.removedTracks = removedTracks
    }

    private enum CodingKeys: String, CodingKey {
        case tracks
        case folders
        case removedTracks
    }

    /// `removedTracks` is new; an index written by an older version loads with
    /// an empty list, so its scans behave exactly as before until the user
    /// removes something.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decode([Track].self, forKey: .tracks)
        folders = try container.decode([URL].self, forKey: .folders)
        removedTracks = try container.decodeIfPresent([Track].self, forKey: .removedTracks) ?? []
    }
}
