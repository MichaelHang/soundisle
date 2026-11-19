import Foundation

public struct AppSettings: Codable, Equatable {
    public var themeMode: String = "system"
    public var lyricsOpacity: Double = 0.26
    public var lyricsOutline: Bool = false
    public var lyricsLineMode: String = "two"
    public var lyricsLocked: Bool = false
    public var showMainSpectrum: Bool = false
    public var hideFromScreenCapture: Bool = true
    public var keepRunningOnClose: Bool = true
    public var miniAlwaysOnTop: Bool = true
    public var playbackMode: String = "repeatAll"
    public var lastQueue: [UUID] = []
    public var lastTrackID: UUID?
    public var lastPosition: TimeInterval = 0
    public var ffmpegPath: String?
    /// UI language: "system", "zh" or "en". Applied at launch through
    /// `AppleLanguages`; changing it needs a restart.
    public var appLanguage: String = "system"
    /// "automatic" downloads and installs new releases, "notify" only says so,
    /// "off" never checks.
    public var updateMode: String = "notify"
    /// A version the user asked not to be reminded about again. Only that
    /// exact version is suppressed; the next release is announced as usual.
    public var skippedUpdateVersion: String?

    public init() {}

    /// Missing keys fall back to the default so a settings file written by an
    /// older version never resets every preference at once.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try container.decodeIfPresent(String.self, forKey: .themeMode) ?? "system"
        lyricsOpacity = try container.decodeIfPresent(Double.self, forKey: .lyricsOpacity) ?? 0.26
        lyricsOutline = try container.decodeIfPresent(Bool.self, forKey: .lyricsOutline) ?? false
        lyricsLineMode = try container.decodeIfPresent(String.self, forKey: .lyricsLineMode) ?? "two"
        lyricsLocked = try container.decodeIfPresent(Bool.self, forKey: .lyricsLocked) ?? false
        showMainSpectrum = try container.decodeIfPresent(Bool.self, forKey: .showMainSpectrum) ?? false
        hideFromScreenCapture = try container.decodeIfPresent(Bool.self, forKey: .hideFromScreenCapture) ?? true
        keepRunningOnClose = try container.decodeIfPresent(Bool.self, forKey: .keepRunningOnClose) ?? true
        miniAlwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .miniAlwaysOnTop) ?? true
        // Sequential playback was removed from the UI; a settings file written
        // by an older version migrates to repeat-all on load.
        let storedMode = try container.decodeIfPresent(String.self, forKey: .playbackMode) ?? "repeatAll"
        playbackMode = storedMode == "sequential" ? "repeatAll" : storedMode
        lastQueue = try container.decodeIfPresent([UUID].self, forKey: .lastQueue) ?? []
        lastTrackID = try container.decodeIfPresent(UUID.self, forKey: .lastTrackID)
        lastPosition = try container.decodeIfPresent(TimeInterval.self, forKey: .lastPosition) ?? 0
        ffmpegPath = try container.decodeIfPresent(String.self, forKey: .ffmpegPath)
        appLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? "system"
        updateMode = try container.decodeIfPresent(String.self, forKey: .updateMode) ?? "notify"
        skippedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .skippedUpdateVersion)
    }
}
