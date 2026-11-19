import AppKit
import Combine
import Foundation
import SoundIsleCore
import SwiftUI
import UniformTypeIdentifiers

/// What the sidebar has selected. One value instead of a pile of booleans so
/// the list, the title and playback all agree on the current source.
enum LibrarySelection: Hashable {
    case allMusic
    case recentlyAdded
    case albums
    case artists
    case folder(URL)
    case playlist(UUID)
}

/// App-wide state: the library on disk, the audio engine, the playback queue
/// and the UI selections that tie them together.
///
/// Everything runs on the main actor. Scanning and metadata reads suspend off
/// the main actor inside `LibraryStore`, so the window stays responsive.
@MainActor
final class AppModel: ObservableObject {
    let library: LibraryStore
    let engine: PlayerEngine
    /// In-memory playlist operations; every change is persisted through
    /// `library.savePlaylists()`, the only writer of `playlists.json`.
    let playlists: PlaylistStore
    /// Serial background transcoder for formats AVFoundation cannot read.
    let transcode: TranscodeQueue
    /// Update checks and, in automatic mode, downloading the new build.
    let updates: UpdateController
    private var updateStateObserver: AnyCancellable?
    /// Window-level notice: update results and anything else the app, rather
    /// than the list, needs to say. Shown on every page.
    @Published var appNotice: AppNotice?
    private var appNoticeTask: Task<Void, Never>?

    @Published private(set) var queue = PlaybackQueue(trackIDs: [])
    @Published private(set) var currentTrack: Track?
    /// Position remembered from the last session until the engine loads the
    /// track on first play.
    @Published private(set) var restoredPosition: TimeInterval = 0
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var isScanning = false
    @Published var selection: LibrarySelection = .allMusic
    /// Multi-selection: ⌘-click toggles, Shift-click extends from the anchor.
    /// A plain click still plays and collapses the selection to one row.
    @Published private(set) var selectedTrackIDs: Set<UUID> = []
    @Published var searchText = ""
    @Published private(set) var sort: TrackSort = .title
    @Published private(set) var sortAscending = true
    /// Playlists keep their manual order until the user clicks a column header.
    @Published private(set) var playlistSorting = false
    /// What the library just did — scan results, saves, removals, playback
    /// errors. All of it surfaces in the window notice now; the list keeps a
    /// banner only for the FFmpeg prompt, which is a persistent, multi-action
    /// state rather than a message. Kept as a property so the call sites read
    /// the same as before.
    var statusMessage: String? {
        get { appNotice?.text }
        set {
            guard let newValue, !newValue.isEmpty else {
                dismissNotice()
                return
            }
            showNotice(AppNotice(kind: .info, text: newValue))
        }
    }
    /// The missing-ffmpeg banner adds install/retry/choose-path actions.
    @Published private(set) var ffmpegPrompt = FFmpegPrompt()
    @Published private(set) var transcodeCacheBytes: Int64 = 0
    @Published var isSettingsPresented = false
    /// Main content area: track list or the full-window lyrics page. UI state
    /// only; the desktop overlay and playback are unaffected.
    @Published var showsLyricsPage = false
    /// Set when leaving the lyrics detail; the list scrolls to this track if
    /// it exists in the section the user lands on.
    @Published var listScrollTarget: UUID?
    /// Lyrics overlay state. Task 8 renders the overlay; the menu bar already
    /// drives these through the hooks below.
    @Published private(set) var isLyricsVisible = false
    @Published private(set) var isLyricsLocked = false
    /// True while the locked overlay's pill is showing. The lyrics window is
    /// click-through then, so it cannot know about hover by itself; the
    /// controller publishes it so the text can make room for the pill.
    @Published private(set) var isLyricsLockedBarVisible = false
    /// Lyrics display state for the current track. Starting a lookup for a
    /// different track clears the old lyrics synchronously, so a slow network
    /// response never leaves the previous song's lines on screen.
    @Published private(set) var lyricsState = LyricsDisplayState()
    @Published private(set) var currentLyricLineIndex: Int?

    var lyrics: Lyrics? { lyricsState.lyrics }
    var lyricsOrigin: LyricsOrigin { lyricsState.origin }
    var isResolvingLyrics: Bool { lyricsState.isResolving }
    /// The overlay controller is created by `AppDelegate`; the menu bar and
    /// main window both go through the hooks below.
    weak var lyricsOverlay: LyricsOverlayWindowController?
    /// Set by `AppDelegate` so preference changes reach the mini panel.
    weak var miniPlayer: MiniPlayerWindowController?
    /// Bringing the main window forward belongs to the app delegate, which
    /// owns the window; the lyrics overlay and the menu bar reach it here.
    var onShowMainWindow: (() -> Void)?
    var onHideMainWindow: (() -> Void)?
    /// Whether the main window is on screen (not in the Dock, not hidden by
    /// mini mode). The desktop lyrics show it as the state of their button.
    @Published private(set) var isMainWindowVisible = true
    /// Mirrors the mini panel's visibility so any control can show the right
    /// open/close affordance.
    @Published private(set) var isMiniPlayerVisible = false
    @Published var searchFocusRequest = UUID()
    @Published var endSearchFocusRequest = UUID()
    /// Mirrors the SwiftUI focus state of the search field so the local key
    /// monitor knows when space belongs to text entry instead of playback.
    @Published var isSearchFocused = false
    @Published var volume: Double = 0.8 {
        didSet { engine.setVolume(Float(volume)) }
    }

    private var cancellables = Set<AnyCancellable>()
    private var saveTimer: Timer?
    private var customAccentSaveTask: Task<Void, Never>?
    private var lyricsOpacitySaveTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var searchFocusMonitor: Any?
    private var didStart = false
    /// Anchor row for Shift-click range selection.
    private var selectionAnchorID: UUID?
    /// Lyrics resolution is fully async; switching tracks cancels the previous
    /// lookup and ignores its late result.
    private let lyricsCache: LyricsCache
    private let lyricsService: LyricsService
    private var lyricsTask: Task<Void, Never>?
    /// Set after a successful override removal so the resolve outcome can
    /// replace the status message.
    private var pendingRestoreTrackID: UUID?
    private let transcodeRoot: URL
    /// The non-native track waiting for ffmpeg, retried once it is found.
    private var pendingTranscodeTrack: Track?
    private var preparingTrackID: UUID?

    // MARK: - Lifecycle

    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let library = LibraryStore(directory: directory)
        library.load()

        self.library = library
        self.engine = PlayerEngine()
        let transcodeRoot = directory.appendingPathComponent("transcode", isDirectory: true)
        try? FileManager.default.createDirectory(at: transcodeRoot, withIntermediateDirectories: true)
        self.transcodeRoot = transcodeRoot
        self.transcode = TranscodeQueue(
            cacheRoot: transcodeRoot,
            ffmpeg: FFmpegLocator.find(customPath: library.settings.ffmpegPath)
        )
        self.playlists = PlaylistStore(playlists: library.playlists) { [weak library] playlists in
            guard let library else { return }
            library.playlists = playlists
            library.savePlaylists()
        }
        let lyricsCache = LyricsCache(
            directory: directory.appendingPathComponent("lyrics", isDirectory: true)
        )
        self.lyricsCache = lyricsCache
        self.lyricsService = LyricsService(
            cache: lyricsCache,
            client: LRCLIBClient(
                endpoint: LRCLIBClient.endpointURL(from: library.settings.lyricsEndpoint)
            )
        )

        self.updates = UpdateController(
            currentVersion: UpdateController.installedVersion,
            supportDirectory: directory,
            modeProvider: { [weak library] in library?.settings.updateMode ?? "notify" },
            skippedVersion: { [weak library] in library?.settings.skippedUpdateVersion },
            setSkippedVersion: { [weak library] version in
                library?.settings.skippedUpdateVersion = version
                library?.saveSettings()
            }
        )
        // The update state lives in its own object; the settings sheet and the
        // menu bar watch the model, so its changes are relayed.
        self.updateStateObserver = updates.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        self.updates.notify = { [weak self] notice in
            self?.showNotice(notice)
        }

        restorePlaybackState()
        isLyricsLocked = library.settings.lyricsLocked
        engine.setVolume(Float(volume))
        observeEngine()
        loadLyrics(for: currentTrack)
        installKeyMonitor()
        installSearchFocusMonitor()
        refreshTranscodeCacheSize()
        applyAppearance()

        // Recovery is never silent: index/settings/playlist fallbacks surface
        // in the existing status banner.
        let startupNotices = [library.recoveryNotice].compactMap { $0 }
        if !startupNotices.isEmpty {
            showWarning(startupNotices.joined(separator: " "))
        }
    }

    deinit {
        appNoticeTask?.cancel()
        lyricsTask?.cancel()
        customAccentSaveTask?.cancel()
        lyricsOpacitySaveTask?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let searchFocusMonitor { NSEvent.removeMonitor(searchFocusMonitor) }
        saveTimer?.invalidate()
    }

    /// Production wiring: `~/Library/Application Support/SoundIsle/`.
    static func production() -> AppModel {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("SoundIsle", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppModel(directory: directory)
    }

    /// Called once the window appears: loads were read in `init`, then the
    /// library refreshes incrementally without blocking the first frame.
    func start() {
        guard !didStart else { return }
        didStart = true
        updates.start()
        guard !library.index.folders.isEmpty else { return }
        Task { await rescan() }
    }

    // MARK: - Updates

    func showNotice(_ notice: AppNotice) {
        appNotice = notice
        appNoticeTask?.cancel()
        guard notice.duration > 0 else { return }
        appNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(notice.duration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.appNotice?.id == notice.id else { return }
            self.appNotice = nil
        }
    }

    func dismissNotice() {
        appNoticeTask?.cancel()
        appNotice = nil
    }

    func setUpdateMode(_ mode: String) {
        guard library.settings.updateMode != mode else { return }
        library.settings.updateMode = mode
        library.saveSettings()
    }

    /// Check on demand (settings button, app menu) and say what happened in
    /// the same status banner everything else uses.
    /// Check on demand (settings button, app menu). The result is reported by
    /// the controller's window notice — `statusMessage` is the list's own
    /// banner, for library work, and writing the update result there too put
    /// the same message in two places at once.
    func checkForUpdates() async {
        await updates.check(manual: true)
    }

    // MARK: - Derived library state

    var folders: [URL] { library.index.folders }

    /// What the player bar should show: live engine state once a track is
    /// loaded, otherwise the position remembered from the last session.
    var displayPosition: TimeInterval {
        engine.duration > 0 ? engine.position : restoredPosition
    }

    var displayDuration: TimeInterval {
        engine.duration > 0 ? engine.duration : (currentTrack?.duration ?? 0)
    }

    var isPlaylistSelection: Bool {
        if case .playlist = selection { return true }
        return false
    }

    /// Column sorting has no visible effect on a manually ordered playlist.
    var sortsColumns: Bool {
        !isPlaylistSelection || playlistSorting
    }

    /// Reordering is only meaningful against the playlist's own order.
    var canReorderPlaylist: Bool {
        guard isPlaylistSelection, !playlistSorting else { return false }
        return searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 专辑/歌手 keep the grouping, so the list view cannot reorder or sort them.
    var isGroupedSelection: Bool {
        switch selection {
        case .albums, .artists: return true
        default: return false
        }
    }

    var visibleTracks: [Track] {
        let source: [Track]
        switch selection {
        case .allMusic, .recentlyAdded, .albums, .artists:
            source = tracks
        case .folder(let folder):
            let prefix = folder.standardizedFileURL.path + "/"
            source = tracks.filter { $0.url.standardizedFileURL.path.hasPrefix(prefix) }
        case .playlist(let id):
            guard let playlist = playlists.playlists.first(where: { $0.id == id }) else { return [] }
            var byID: [UUID: Track] = [:]
            for track in tracks { byID[track.id] = track }
            source = playlist.trackIDs.compactMap { byID[$0] }
            if !playlistSorting {
                return TrackQuery.filter(source, query: searchText)
            }
        }
        return TrackQuery.apply(source, query: searchText, sort: sort, ascending: sortAscending)
    }

    /// The album/artist browser's groups, built from the same filtered source
    /// `visibleTracks` uses so search and playback all agree. `select` points
    /// the sort at the grouping column, so grouping is stable and deterministic.
    var libraryGroups: [TrackGroup] {
        guard isGroupedSelection else { return [] }
        return LibraryGrouping.groups(
            visibleTracks,
            by: selection == .artists ? .artist : .album
        )
    }

    /// Distinct album names, for the sidebar's 专辑 row.
    var albumCount: Int { Set(tracks.map(\.album)).count }

    /// Distinct artist names, for the sidebar's 歌手 row.
    var artistCount: Int { Set(tracks.map(\.artist)).count }

    func select(_ newSelection: LibrarySelection) {
        selection = newSelection
        selectedTrackIDs = []
        selectionAnchorID = nil
        // The lyrics page is a detail view of the current track. Choosing a
        // library section from the sidebar is navigation, so return to the
        // list instead of leaving the sidebar and the page out of sync.
        if showsLyricsPage {
            listScrollTarget = currentTrack?.id
            withAnimation(.easeOut(duration: 0.18)) {
                showsLyricsPage = false
            }
        }
        switch newSelection {
        case .recentlyAdded:
            sort = .dateAdded
            sortAscending = false
        case .albums:
            sort = .album
            sortAscending = true
        case .artists:
            sort = .artist
            sortAscending = true
        case .playlist:
            playlistSorting = false
        case .allMusic, .folder:
            break
        }
    }

    func toggleSort(_ newSort: TrackSort) {
        if sort == newSort {
            sortAscending.toggle()
        } else {
            sort = newSort
            sortAscending = newSort != .dateAdded
        }
        if isPlaylistSelection {
            playlistSorting = true
        }
    }

    // MARK: - Track selection

    /// A row click. ⌘ toggles one row, Shift extends from the last clicked
    /// row, and a plain click keeps the usual single-click playback while
    /// collapsing the selection. `source` scopes the queue to a subset (the
    /// detail pages play within one album or artist instead of the whole
    /// browser).
    func handleTrackClick(
        _ trackID: UUID,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags,
        source: [Track]? = nil
    ) {
        if modifiers.contains(.command) {
            if selectedTrackIDs.contains(trackID) {
                selectedTrackIDs.remove(trackID)
            } else {
                selectedTrackIDs.insert(trackID)
            }
            selectionAnchorID = trackID
            return
        }
        if modifiers.contains(.shift), let anchor = selectionAnchorID,
           let from = visibleTracks.firstIndex(where: { $0.id == anchor }),
           let to = visibleTracks.firstIndex(where: { $0.id == trackID }) {
            let range = from <= to ? from...to : to...from
            selectedTrackIDs = Set(visibleTracks[range].map(\.id))
            return
        }
        selectedTrackIDs = [trackID]
        selectionAnchorID = trackID
        play(trackID: trackID, source: source)
    }

    /// Rows a context-menu action applies to: the whole selection when the
    /// clicked row belongs to it, otherwise only the clicked row.
    func contextTrackIDs(for trackID: UUID) -> [UUID] {
        guard selectedTrackIDs.contains(trackID) else { return [trackID] }
        let ordered = visibleTracks.map(\.id).filter { selectedTrackIDs.contains($0) }
        return ordered.isEmpty ? [trackID] : ordered
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(named name: String) -> Playlist {
        let playlist = playlists.create(name: name)
        objectWillChange.send()
        surfacePersistenceError()
        return playlist
    }

    func renamePlaylist(id: UUID, to name: String) {
        playlists.rename(id: id, to: name)
        objectWillChange.send()
        surfacePersistenceError()
    }

    func deletePlaylist(id: UUID) {
        playlists.delete(id: id)
        surfacePersistenceError()
        if selection == .playlist(id) {
            select(.allMusic)
        }
        objectWillChange.send()
    }

    func addToPlaylist(_ playlistID: UUID, trackIDs: [UUID]) {
        guard !trackIDs.isEmpty else { return }
        playlists.add(trackIDs: trackIDs, to: playlistID)
        objectWillChange.send()
        surfacePersistenceError()
        if let playlist = playlists.playlists.first(where: { $0.id == playlistID }) {
            statusMessage = Lf("已添加到「%@」", playlist.name)
        }
    }

    func removeFromPlaylist(_ playlistID: UUID, trackID: UUID) {
        playlists.remove(trackID: trackID, from: playlistID)
        objectWillChange.send()
        surfacePersistenceError()
    }

    /// Drag-to-reorder inside a playlist: the dragged track takes the target's
    /// slot in the playlist's own order.
    func moveTrack(_ draggedID: UUID, onto targetID: UUID) {
        guard case .playlist(let playlistID) = selection,
              let playlist = playlists.playlists.first(where: { $0.id == playlistID }),
              draggedID != targetID,
              let from = playlist.trackIDs.firstIndex(of: draggedID),
              let to = playlist.trackIDs.firstIndex(of: targetID) else { return }
        playlists.move(from: from, to: to, in: playlistID)
        objectWillChange.send()
        surfacePersistenceError()
    }

    /// AppKit saves us from macOS 13-only SwiftUI alert text fields.
    func promptCreatePlaylist() {
        guard let name = promptForPlaylistName(
            title: L("新建播放列表"),
            message: L("输入播放列表名称。"),
            value: ""
        ) else { return }
        let playlist = createPlaylist(named: name)
        select(.playlist(playlist.id))
    }

    func promptRenamePlaylist(id: UUID) {
        guard let existing = playlists.playlists.first(where: { $0.id == id }),
              let name = promptForPlaylistName(
                  title: L("重命名播放列表"),
                  message: L("输入新的名称。"),
                  value: existing.name
              ) else { return }
        renamePlaylist(id: id, to: name)
    }

    func confirmDeletePlaylist(id: UUID) {
        guard let existing = playlists.playlists.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = Lf("删除播放列表「%@」？", existing.name)
        alert.informativeText = L("只会删除播放列表，歌曲文件不受影响。")
        alert.addButton(withTitle: L("删除"))
        alert.addButton(withTitle: L("取消"))
        let response = alert.runModal()
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard response == .alertFirstButtonReturn else { return }
        deletePlaylist(id: id)
    }

    private func promptForPlaylistName(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("确定"))
        alert.addButton(withTitle: L("取消"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    func trackCount(in folder: URL) -> Int {
        let prefix = folder.standardizedFileURL.path + "/"
        return tracks.filter { $0.url.standardizedFileURL.path.hasPrefix(prefix) }.count
    }

    /// Playlist rows can keep IDs for tracks that were later removed; the
    /// sidebar count should match what the playlist can actually show.
    func resolvableTrackCount(in playlist: Playlist) -> Int {
        let ids = Set(tracks.map(\.id))
        return playlist.trackIDs.filter { ids.contains($0) }.count
    }

    // MARK: - Import

    /// Opens the system folder picker. The caller hands the URLs back to
    /// `importFolders(_:)`.
    func openFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = L("导入")
        panel.message = L("选择包含音乐的文件夹")
        let response = panel.runModal()
        // The search field is the only text field in the window and AppKit may
        // hand it focus when the panel closes, which would swallow space/arrow
        // playback shortcuts. Leave focus on the window itself.
        NSApp.keyWindow?.makeFirstResponder(nil)
        return response == .OK ? panel.urls : []
    }

    /// Accepts folders, or files dropped from Finder (whose containing folder
    /// is imported because the library is folder-based).
    func importFolders(_ urls: [URL]) {
        let manager = FileManager.default
        let folders = urls.map { url -> URL in
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
            return url.deletingLastPathComponent()
        }
        let unique = Array(Set(folders.map(\.standardizedFileURL)))
        guard !unique.isEmpty else { return }
        guard !isScanning else {
            statusMessage = L("正在扫描音乐库，请稍后再导入。")
            return
        }
        Task { await importFoldersAndScan(unique) }
    }

    private func importFoldersAndScan(_ urls: [URL]) async {
        isScanning = true
        var report = ScanReport.empty
        for url in urls {
            let scan = await library.addFolder(url)
            report = ScanReport(added: report.added + scan.added, removed: report.removed + scan.removed)
        }
        isScanning = false
        refreshFromLibrary()
        prepareLibraryFormats()
        showScanReport(report)
    }

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        let report = await library.rescan()
        isScanning = false
        refreshFromLibrary()
        prepareLibraryFormats()
        showScanReport(report)
    }

    /// Sidebar refresh on a single folder row. Uses the folder-scoped core
    /// rescan so other imported folders are never touched.
    func rescanFolder(_ folder: URL) async {
        guard !isScanning else { return }
        isScanning = true
        let report = await library.rescan(folder: folder)
        isScanning = false
        refreshFromLibrary()
        prepareLibraryFormats()
        showScanReport(report)
    }

    /// Summarizes a scan so the user always sees what changed, even when a
    /// scan adds or removes nothing. It goes through the window notice, which
    /// dismisses itself after a few seconds, so no scan report lingers.
    private func showScanReport(_ report: ScanReport) {
        statusMessage = "\(Lf("新增 %d 首", report.added))，\(Lf("移除 %d 首", report.removed))"
    }

    private func refreshFromLibrary() {
        tracks = library.index.tracks
        // Folder removal prunes playlist entries inside `LibraryStore`; mirror
        // that so the in-memory store never resurrects deleted track IDs.
        playlists.reload(library.playlists)
        let validIDs = Set(tracks.map(\.id))
        let pruned = selectedTrackIDs.intersection(validIDs)
        if pruned != selectedTrackIDs {
            selectedTrackIDs = pruned
        }
        guard let id = currentTrack?.id else { return }
        if let updated = tracks.first(where: { $0.id == id }) {
            currentTrack = updated
        } else {
            // Vanished files are removed by the scan itself; if the current
            // track dropped out, stop playback instead of pointing at a stub.
            currentTrack = nil
            restoredPosition = 0
            engine.pause()
        }
    }

    // MARK: - Playback

    /// What a row tap or a group's play button turns into the queue. On the
    /// album/artist browser that is the grouped order, so 下一首 walks album by
    /// album instead of the flat sort.
    private var playbackSource: [Track] {
        isGroupedSelection ? libraryGroups.flatMap(\.tracks) : visibleTracks
    }

    func play(trackID: UUID, source: [Track]? = nil) {
        let queueSource = source ?? playbackSource
        guard let index = queueSource.firstIndex(where: { $0.id == trackID }) else { return }
        let track = queueSource[index]

        if currentTrack?.id == track.id {
            togglePlayPause()
            return
        }
        if track.isMissing {
            showWarning(Lf("《%@》文件缺失，无法播放。", track.title))
            return
        }

        var updated = queue
        updated.replace(with: queueSource.map(\.id), startAt: index)
        queue = updated
        _ = playFromQueue(track.id)
        savePlaybackState()
    }

    func togglePlayPause() {
        if engine.isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Explicit play, for the media-key "play" command (as opposed to the
    /// toggle command that F8 sends).
    func play() {
        if let current = currentTrack {
            if engine.duration > 0 {
                engine.play()
                if engine.isPlaying {
                    dismissNotice()
                } else {
                    statusMessage = startFailureStatus
                }
            } else {
                resumeCurrent(current)
            }
            return
        }

        if let first = playbackSource.first {
            play(trackID: first.id)
        } else {
            statusMessage = L("音乐库是空的，先导入一个文件夹。")
        }
    }

    func pause() {
        engine.pause()
    }

    private var startFailureStatus: String {
        Lf("无法开始播放：%@", engine.lastError ?? L("未知错误"))
    }

    /// First play after a restore: the engine was deliberately left unloaded
    /// at launch, so load now and jump to the remembered position. Non-native
    /// tracks that are already cached take the same path; uncached ones are
    /// prepared first.
    private func resumeCurrent(_ track: Track) {
        guard !track.isMissing else {
            showWarning(Lf("《%@》文件缺失，无法播放。", track.title))
            return
        }
        let position = restoredPosition
        let url: URL?
        if AudioFormatSupport.isNative(track.url) {
            url = track.url
        } else {
            url = transcode.cachedURL(for: track)
        }
        guard let url else {
            _ = startTrack(track, startAt: position)
            return
        }
        guard loadAndPlay(track, url: url, startAt: position) else { return }
        restoredPosition = 0
    }

    func next() {
        var updated = queue
        var attempts = 0
        while attempts < max(updated.trackIDs.count, 1) {
            guard let id = updated.next() else { break }
            attempts += 1
            if playFromQueue(id) { break }
        }
        queue = updated
        savePlaybackState()
    }

    func previous() {
        var updated = queue
        var attempts = 0
        while attempts < max(updated.trackIDs.count, 1) {
            guard let id = updated.previous() else { break }
            attempts += 1
            if playFromQueue(id) { break }
        }
        queue = updated
        savePlaybackState()
    }

    func seek(to time: TimeInterval) {
        guard let current = currentTrack else { return }
        if engine.duration > 0 {
            engine.seek(to: time)
            if let error = engine.lastError {
                showWarning(Lf("无法跳转播放位置：%@", error))
            }
        } else {
            let upper = current.duration > 0 ? current.duration : time
            restoredPosition = min(max(time, 0), upper)
        }
        savePlaybackState()
    }

    func seek(by delta: TimeInterval) {
        seek(to: displayPosition + delta)
    }

    private func playFromQueue(_ id: UUID) -> Bool {
        guard let track = tracks.first(where: { $0.id == id }) else {
            showWarning(L("曲目不在音乐库中。"))
            return false
        }
        return startTrack(track)
    }

    /// Starts a track, routing fallback formats through the transcode cache.
    /// Returns true when the track was accepted, including the asynchronous
    /// "preparing" case, so `next()`/`previous()` do not skip past it.
    /// `startAt` carries a restored position through the async preparation.
    @discardableResult
    private func startTrack(_ track: Track, startAt: TimeInterval = 0) -> Bool {
        guard !track.isMissing else {
            showWarning(Lf("《%@》文件缺失，已跳过。", track.title))
            return false
        }

        if AudioFormatSupport.isNative(track.url) {
            ffmpegPrompt.clear()
            pendingTranscodeTrack = nil
            return loadAndPlay(track, url: track.url, startAt: startAt)
        }
        if let cached = transcode.cachedURL(for: track) {
            ffmpegPrompt.clear()
            pendingTranscodeTrack = nil
            return loadAndPlay(track, url: cached, startAt: startAt)
        }
        guard let ffmpeg = FFmpegLocator.find(customPath: library.settings.ffmpegPath) else {
            // Leave the current song alone: a missing dependency must never
            // freeze the UI or block formats AVFoundation can play.
            pendingTranscodeTrack = track
            ffmpegPrompt.show(Lf("需要 FFmpeg 才能播放此格式（《%@》）。", track.title))
            return true
        }

        transcode.updateFFmpeg(ffmpeg)
        engine.unload()
        currentTrack = track
        restoredPosition = startAt
        ffmpegPrompt.clear()
        statusMessage = Lf("正在准备《%@》…", track.title)
        preparingTrackID = track.id

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.transcode.ensureCached(track)
                guard self.preparingTrackID == track.id,
                      self.currentTrack?.id == track.id else { return }
                self.preparingTrackID = nil
                _ = self.loadAndPlay(track, url: url, startAt: startAt)
            } catch {
                guard self.preparingTrackID == track.id else { return }
                self.preparingTrackID = nil
                if case TranscodeError.ffmpegMissing = error {
                    self.pendingTranscodeTrack = track
                    self.ffmpegPrompt.show(Lf("需要 FFmpeg 才能播放此格式（《%@》）。", track.title))
                } else {
                    self.showWarning(Lf("无法准备《%@》：%@", track.title, error.localizedDescription))
                }
            }
        }
        return true
    }

    /// Loads `url`, optionally seeks while paused, then starts playback so a
    /// restored position never plays a fragment from the start of the song.
    private func loadAndPlay(
        _ track: Track,
        url: URL,
        startAt: TimeInterval = 0
    ) -> Bool {
        preparingTrackID = nil
        do {
            try engine.load(url: url)
        } catch {
            showWarning(Lf("无法播放《%@》：%@", track.title, engine.lastError ?? L("未知错误")))
            return false
        }
        if startAt > 0 {
            engine.seek(to: startAt)
        }
        currentTrack = track
        restoredPosition = 0
        engine.play()
        if engine.isPlaying {
            dismissNotice()
        } else {
            statusMessage = startFailureStatus
        }
        // The file loaded, so keep the queue on this track even if the audio
        // engine could not start; skipping ahead would hide the failure.
        return true
    }

    // MARK: - Playback modes

    func setPlaybackMode(_ mode: PlaybackMode) {
        guard queue.mode != mode else { return }
        var updated = queue
        updated.setMode(mode)
        queue = updated
        savePlaybackState()
    }

    // MARK: - Transcode cache & FFmpeg

    var ffmpegPathText: String {
        FFmpegLocator.find(customPath: library.settings.ffmpegPath)?.path ?? L("未找到")
    }

    var transcodeCacheSizeText: String {
        transcodeCacheBytes > 0
            ? ByteCountFormatter.string(fromByteCount: transcodeCacheBytes, countStyle: .file)
            : "0 MB"
    }

    func refreshTranscodeCacheSize() {
        transcodeCacheBytes = TranscodeCache.directorySize(transcodeRoot)
    }

    @discardableResult
    func clearTranscodeCache() -> String {
        let message: String
        do {
            let freed = TranscodeCache.directorySize(transcodeRoot)
            try transcode.clearCache()
            refreshTranscodeCacheSize()
            let size = freed > 0
                ? ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                : "0 MB"
            message = Lf("已清理转码缓存（%@）。", size)
        } catch let transcodeError as TranscodeError {
            message = transcodeError.localizedDescription
        } catch {
            message = Lf("清理转码缓存失败：%@", error.localizedDescription)
        }
        statusMessage = message
        return message
    }

    /// 「重新检测」: users normally run `brew install ffmpeg` and come back.
    @discardableResult
    func redetectFFmpeg() -> String {
        guard let found = FFmpegLocator.find(customPath: library.settings.ffmpegPath) else {
            let message = L("仍未找到 FFmpeg，请先运行 brew install ffmpeg。")
            ffmpegPrompt.show(message)
            return message
        }
        transcode.updateFFmpeg(found)
        ffmpegPrompt.clear()
        let message = Lf("已找到 FFmpeg：%@", found.path)
        statusMessage = message
        prepareLibraryFormats()
        retryPendingTranscode()
        objectWillChange.send()
        return message
    }

    /// Returns nil when the picker was cancelled.
    @discardableResult
    func chooseFFmpegPath() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("选择")
        panel.message = L("选择 ffmpeg 可执行文件")
        let response = panel.runModal()
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard response == .OK, let url = panel.url else { return nil }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            let message = L("所选文件不可执行，请选择 ffmpeg 可执行文件。")
            statusMessage = message
            return message
        }
        library.settings.ffmpegPath = url.path
        library.saveSettings()
        transcode.updateFFmpeg(url)
        ffmpegPrompt.clear()
        let message = Lf("已使用 FFmpeg：%@", url.path)
        statusMessage = message
        prepareLibraryFormats()
        retryPendingTranscode()
        objectWillChange.send()
        return message
    }

    func copyFFmpegInstallCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("brew install ffmpeg", forType: .string)
        statusMessage = L("已复制安装命令：brew install ffmpeg")
    }

    private func retryPendingTranscode() {
        guard let track = pendingTranscodeTrack else { return }
        pendingTranscodeTrack = nil
        _ = startTrack(track, startAt: restoredPosition)
    }

    /// After a scan: fill durations for fallback formats and transcode them in
    /// the background. Without ffmpeg the tracks stay indexed with a duration
    /// of 0 and playback of native formats is unaffected.
    private func prepareLibraryFormats() {
        guard let ffmpeg = FFmpegLocator.find(customPath: library.settings.ffmpegPath) else {
            return
        }
        transcode.updateFFmpeg(ffmpeg)
        for track in tracks
        where !track.isMissing && !AudioFormatSupport.isNative(track.url) {
            transcode.enqueue(track, priority: false)
        }
        fillDurations(using: ffmpeg)
        refreshTranscodeCacheSize()
    }

    private func fillDurations(using ffmpeg: URL) {
        let pending = tracks.filter {
            !$0.isMissing && $0.duration <= 0 && !AudioFormatSupport.isNative($0.url)
        }
        guard !pending.isEmpty else { return }

        Task { [weak self] in
            let durations = await Task.detached(priority: .utility) { () -> [UUID: TimeInterval] in
                var result: [UUID: TimeInterval] = [:]
                for track in pending {
                    if let duration = FFprobeReader.duration(of: track.url, ffmpeg: ffmpeg) {
                        result[track.id] = duration
                    }
                }
                return result
            }.value
            guard let self, !durations.isEmpty else { return }
            self.library.updateDurations(durations)
            self.refreshFromLibrary()
        }
    }

    // MARK: - Lyrics

    /// Clicks the player-bar cover: spring slide/fade between the list and the
    /// now-playing lyrics page. The transition itself lives on the views.
    func toggleLyricsPage() {
        if showsLyricsPage {
            listScrollTarget = currentTrack?.id
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showsLyricsPage.toggle()
        }
    }

    /// Switches to the mini player from anywhere in the UI. Every main
    /// window (not the floating lyrics/mini panels) is ordered out; returning
    /// still goes through the menu bar or the mini player's expand button.
    /// The main window and the mini player take turns; whichever shows, the
    /// other is gone. Both flags are written here so no caller can leave them
    /// disagreeing about what is on screen.
    func showMiniPlayer() {
        for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain {
            window.orderOut(nil)
        }
        miniPlayer?.show()
        setMainWindowVisible(false)
    }

    func showMainWindow() {
        onShowMainWindow?()
    }

    /// Same thing ⌘W does while `keepRunningOnClose` is on: the window goes
    /// away, the app keeps playing.
    func hideMainWindow() {
        onHideMainWindow?()
    }

    /// What the three surfaces should all agree on: the main window is on
    /// screen only when it is not hidden and the mini player has not taken
    /// its place. Derived rather than stored, so a single missed transition
    /// cannot leave a button lit for a window that is not there.
    var isMainWindowOnScreen: Bool {
        isMainWindowVisible && !isMiniPlayerVisible
    }

    func setMainWindowVisible(_ visible: Bool) {
        guard isMainWindowVisible != visible else { return }
        isMainWindowVisible = visible
    }

    /// Closes the mini player without forcing the main window back; the menu
    /// bar and desktop lyrics remain available.
    func toggleMiniPlayer() {
        if isMiniPlayerVisible {
            miniPlayer?.hide()
        } else {
            showMiniPlayer()
        }
    }

    func setMiniPlayerVisible(_ visible: Bool) {
        guard isMiniPlayerVisible != visible else { return }
        isMiniPlayerVisible = visible
        if visible { setMainWindowVisible(false) }
    }

    func toggleLyricsVisibility() {
        setLyricsVisible(!isLyricsVisible)
    }

    func setLyricsVisible(_ visible: Bool) {
        guard isLyricsVisible != visible else { return }
        isLyricsVisible = visible
        lyricsOverlay?.setVisible(visible)
    }

    func toggleLyricsLock() {
        setLyricsLocked(!isLyricsLocked)
    }

    func setLyricsLockedBarVisible(_ visible: Bool) {
        guard isLyricsLockedBarVisible != visible else { return }
        isLyricsLockedBarVisible = visible
    }

    func setLyricsLocked(_ locked: Bool) {
        guard isLyricsLocked != locked else { return }
        isLyricsLocked = locked
        library.settings.lyricsLocked = locked
        library.saveSettings()
        surfacePersistenceError()
        lyricsOverlay?.setLocked(locked)
    }

    /// The overlay and settings sliders emit continuously while dragging, so
    /// the JSON write trails 0.3s behind the last change like the custom accent.
    func setLyricsOpacity(_ opacity: Double) {
        let clamped = min(max(opacity, 0.05), 0.9)
        guard library.settings.lyricsOpacity != clamped else { return }
        library.settings.lyricsOpacity = clamped
        objectWillChange.send()
        lyricsOpacitySaveTask?.cancel()
        lyricsOpacitySaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.library.saveSettings()
            self.surfacePersistenceError()
        }
    }

    func setLyricsOutline(_ outline: Bool) {
        guard library.settings.lyricsOutline != outline else { return }
        library.settings.lyricsOutline = outline
        library.saveSettings()
        objectWillChange.send()
    }

    func setLyricsLineMode(_ mode: String) {
        guard mode == "one" || mode == "two", library.settings.lyricsLineMode != mode else { return }
        library.settings.lyricsLineMode = mode
        library.saveSettings()
        objectWillChange.send()
    }

    /// Current synced line, or the first line before playback reaches it.
    var currentLyricText: String? {
        guard let lyrics, !lyrics.lines.isEmpty else { return nil }
        guard lyrics.isSynced else { return lyrics.lines.first?.text }
        let index = currentLyricLineIndex ?? 0
        guard lyrics.lines.indices.contains(index) else { return nil }
        return lyrics.lines[index].text
    }

    var nextLyricText: String? {
        guard let lyrics, lyrics.isSynced, !lyrics.lines.isEmpty else { return nil }
        let currentIndex = currentLyricLineIndex ?? 0
        guard lyrics.lines.indices.contains(currentIndex) else { return nil }
        let current = lyrics.lines[currentIndex].text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Some LRCs repeat a phrase on adjacent timestamps (e.g. 说句心里话
        // repeats “梦中的她” and “既然来当兵”). Showing the same words again
        // in the smaller preview line reads like a duplicate/overlap, so skip
        // identical or empty lines and preview the next distinct one.
        var index = currentIndex + 1
        while lyrics.lines.indices.contains(index) {
            let candidate = lyrics.lines[index].text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty, candidate != current {
                return lyrics.lines[index].text
            }
            index += 1
        }
        return nil
    }

    var hasLyricsOverride: Bool {
        lyricsOrigin == .override
    }

    /// A silent online miss leaves `lyrics == nil`; the overlay and menus then
    /// offer this retry entry.
    var canRetryLyrics: Bool {
        currentTrack != nil && lyrics == nil && !isResolvingLyrics
    }

    /// 「更换歌词…」: import `.lrc` or plain `.txt`, store it as the track's
    /// manual override and show it immediately.
    func promptImportLyrics() {
        guard let track = currentTrack else {
            statusMessage = L("先播放一首歌曲，再导入歌词。")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("导入")
        panel.message = L("选择 .lrc 或 .txt 歌词文件")
        var types: [UTType] = [.plainText]
        if let lrc = UTType(filenameExtension: "lrc") {
            types.insert(lrc, at: 0)
        }
        panel.allowedContentTypes = types
        let response = panel.runModal()
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard response == .OK, let url = panel.url else { return }
        guard let text = LyricsService.readText(at: url) else {
            statusMessage = L("无法读取歌词文件。")
            return
        }

        let parsed = Self.parseImportedLyrics(
            text,
            forcePlain: url.pathExtension.lowercased() != "lrc"
        )
        guard !parsed.lines.isEmpty else {
            statusMessage = L("歌词文件没有可用内容。")
            return
        }

        do {
            try lyricsCache.saveOverride(parsed, for: track.id)
        } catch {
            statusMessage = Lf("无法保存歌词：%@", error.localizedDescription)
            return
        }
        // The open panel is modal, but a media key can still change tracks.
        guard currentTrack?.id == track.id else {
            loadLyrics(for: currentTrack)
            return
        }
        lyricsTask?.cancel()
        apply(ResolvedLyrics(lyrics: parsed, origin: .override, sourceURL: url), for: track.id)
        statusMessage = L("已导入歌词")
    }

    /// 「恢复自动匹配」: drop the override and resolve the normal priority
    /// chain again (sidecar, cache, then online). Success is reported only
    /// after the override file was actually removed; the resolve outcome then
    /// updates the message.
    func restoreAutomaticLyrics() {
        guard let track = currentTrack else { return }
        do {
            try lyricsCache.removeOverride(for: track.id)
        } catch {
            statusMessage = Lf("无法清除歌词覆盖：%@", error.localizedDescription)
            return
        }
        pendingRestoreTrackID = track.id
        loadLyrics(for: track)
    }

    /// User-initiated retry after a silent online miss.
    func retryLyrics() {
        guard let track = currentTrack else { return }
        loadLyrics(for: track)
    }

    /// Loads lyrics off the main actor. A previous track's lookup is cancelled
    /// so a slow network response can never overwrite the current track's
    /// lyrics.
    private func loadLyrics(for track: Track?) {
        lyricsTask?.cancel()
        lyricsTask = nil
        if let pending = pendingRestoreTrackID, pending != track?.id {
            pendingRestoreTrackID = nil
        }
        guard let track, !track.isMissing else {
            lyricsState.beginLoading(trackID: nil)
            currentLyricLineIndex = nil
            return
        }

        let trackChanged = lyricsState.trackID != track.id
        lyricsState.beginLoading(trackID: track.id)
        if trackChanged {
            currentLyricLineIndex = nil
        }

        lyricsService.isOnlineEnabled = library.settings.onlineLyricsEnabled
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await self.lyricsService.resolve(for: track)
            guard !Task.isCancelled else { return }
            guard self.currentTrack?.id == track.id else { return }
            self.apply(resolved, for: track.id)
            if self.pendingRestoreTrackID == track.id {
                self.pendingRestoreTrackID = nil
                self.statusMessage = resolved == nil
                    ? L("已恢复自动匹配，但未找到歌词")
                    : L("已恢复自动匹配")
            }
        }
    }

    private func apply(_ resolved: ResolvedLyrics?, for trackID: UUID) {
        lyricsState.apply(resolved, for: trackID)
        currentLyricLineIndex = nil
        updateCurrentLyricLine(at: engine.position)
    }

    /// `.lrc` keeps its timestamps; plain text is shown line-by-line even if
    /// the file happens to contain bracket-looking text.
    private static func parseImportedLyrics(_ text: String, forcePlain: Bool) -> Lyrics {
        forcePlain ? LRCParser.parsePlainText(text) : LRCParser.parse(text)
    }

    private func updateCurrentLyricLine(at time: TimeInterval) {
        let index = lyrics?.index(at: time)
        guard currentLyricLineIndex != index else { return }
        currentLyricLineIndex = index
    }

    // MARK: - Appearance & preferences

    /// Explicit light/dark modes also recolour native menus and traffic-light
    /// chrome; system mode follows macOS.
    func applyAppearance() {
        let appearance: NSAppearance?
        switch library.settings.mode {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        NSApplication.shared.appearance = appearance
    }

    func setThemePreset(_ preset: ThemePreset) {
        guard library.settings.themePreset != preset.rawValue else { return }
        library.settings.themePreset = preset.rawValue
        saveSettingsAndNotify()
    }

    func setThemeMode(_ mode: ThemeMode) {
        guard library.settings.themeMode != mode.rawValue else { return }
        library.settings.themeMode = mode.rawValue
        applyAppearance()
        saveSettingsAndNotify()
    }

    /// Applied live for immediate preview, but the JSON write is debounced:
    /// `ColorPicker` emits continuously while the user drags the colour wheel.
    func setCustomAccent(hex: String?) {
        guard library.settings.customAccentHex != hex else { return }
        library.settings.customAccentHex = hex
        objectWillChange.send()
        customAccentSaveTask?.cancel()
        customAccentSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.library.saveSettings()
        }
    }

    func setRowStyle(cover: Bool) {
        let style = cover ? "cover" : "index"
        guard library.settings.rowStyle != style else { return }
        library.settings.rowStyle = style
        saveSettingsAndNotify()
    }

    func setShowMainSpectrum(_ enabled: Bool) {
        guard library.settings.showMainSpectrum != enabled else { return }
        library.settings.showMainSpectrum = enabled
        library.saveSettings()
        surfacePersistenceError()
        refreshSpectrumConsumers()
        objectWillChange.send()
    }

    func setHideFromScreenCapture(_ hidden: Bool) {
        guard library.settings.hideFromScreenCapture != hidden else { return }
        library.settings.hideFromScreenCapture = hidden
        miniPlayer?.applySettings()
        lyricsOverlay?.applySettings()
        saveSettingsAndNotify()
    }

    func setMiniAlwaysOnTop(_ onTop: Bool) {
        guard library.settings.miniAlwaysOnTop != onTop else { return }
        library.settings.miniAlwaysOnTop = onTop
        miniPlayer?.applySettings()
        saveSettingsAndNotify()
    }

    func setKeepRunningOnClose(_ keepRunning: Bool) {
        guard library.settings.keepRunningOnClose != keepRunning else { return }
        library.settings.keepRunningOnClose = keepRunning
        saveSettingsAndNotify()
    }

    /// Persists the language override and writes it where LaunchServices reads
    /// it (`AppleLanguages` in the app's defaults domain). The running process
    /// keeps its current localization, so a restart is required and announced.
    func setAppLanguage(_ language: String) {
        guard ["system", "zh", "en"].contains(language),
              library.settings.appLanguage != language else { return }
        library.settings.appLanguage = language
        let defaults = UserDefaults.standard
        switch language {
        case "zh":
            defaults.set(["zh-Hans"], forKey: "AppleLanguages")
        case "en":
            defaults.set(["en"], forKey: "AppleLanguages")
        default:
            defaults.removeObject(forKey: "AppleLanguages")
        }
        saveSettingsAndNotify()
        showLanguageRestartNotice()
    }

    private func showLanguageRestartNotice() {
        let alert = NSAlert()
        alert.messageText = L("语言已更改")
        alert.informativeText = "重启声屿后生效。\nTakes effect after restarting SoundIsle."
        alert.addButton(withTitle: L("确定"))
        alert.runModal()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func setOnlineLyricsEnabled(_ enabled: Bool) {
        guard library.settings.onlineLyricsEnabled != enabled else { return }
        library.settings.onlineLyricsEnabled = enabled
        lyricsService.isOnlineEnabled = enabled
        saveSettingsAndNotify()
        if enabled {
            loadLyrics(for: currentTrack)
        }
    }

    /// Returns a user-facing error when `raw` is not a usable http(s) URL;
    /// `nil` means the endpoint was saved (or cleared to the default).
    @discardableResult
    func setLyricsEndpoint(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if let normalized, LRCLIBClient.endpointURL(from: normalized) == nil {
            return L("歌词源地址无效，请输入 http 或 https 链接。")
        }
        guard library.settings.lyricsEndpoint != normalized else { return nil }
        library.settings.lyricsEndpoint = normalized
        lyricsService.client = LRCLIBClient(
            endpoint: LRCLIBClient.endpointURL(from: normalized)
        )
        saveSettingsAndNotify()
        return nil
    }

    /// The spectrum tap runs only while someone draws it: the mini window is
    /// visible, or the main player bar spectrum is enabled.
    func refreshSpectrumConsumers() {
        engine.isSpectrumEnabled = (miniPlayer?.isVisible ?? false)
            || library.settings.showMainSpectrum
    }

    @discardableResult
    func removeMissingTracks() -> String {
        library.removeMissingTracks()
        refreshFromLibrary()
        objectWillChange.send()
        surfacePersistenceError()
        let message = L("已移除缺失文件条目。")
        statusMessage = message
        return message
    }

    /// 「移除」 in Settings → 音乐文件夹. Only the index and playlist entries
    /// change; the files on disk are deliberately untouched.
    @discardableResult
    func removeFolder(_ url: URL) -> String {
        library.removeFolder(url)
        if case .folder(let selected) = selection,
           selected.standardizedFileURL == url.standardizedFileURL {
            select(.allMusic)
        }
        refreshFromLibrary()
        objectWillChange.send()
        surfacePersistenceError()
        let message = Lf("已移除文件夹：%@。", url.lastPathComponent)
        statusMessage = message
        return message
    }

    /// 「重命名文件夹…」 in the sidebar. Moves the directory, rewrites the
    /// index and playlists, then reloads the current track from its new URL.
    @discardableResult
    func renameFolder(_ folder: URL, to name: String) -> String {
        let prefix = folder.standardizedFileURL.path + "/"
        let playingTrack = currentTrack.flatMap { track in
            track.url.standardizedFileURL.path.hasPrefix(prefix) ? track : nil
        }
        let wasPlaying = engine.isPlaying
        let position = displayPosition

        do {
            let newURL = try library.renameFolder(at: folder, toName: name)
            if case .folder(let selected) = selection,
               selected.standardizedFileURL == folder.standardizedFileURL {
                select(.folder(newURL))
            }
            refreshFromLibrary()
            objectWillChange.send()
            let message = Lf("已将文件夹重命名为「%@」。", newURL.lastPathComponent)
            statusMessage = message
            // A reload failure is allowed to replace the success message.
            if playingTrack != nil, let track = currentTrack {
                reloadAfterFolderRename(track, wasPlaying: wasPlaying, position: position)
            }
            surfacePersistenceError()
            return message
        } catch {
            let message = Lf("重命名失败：%@", error.localizedDescription)
            statusMessage = message
            return message
        }
    }

    /// The engine still holds the old path after the folder moved; reload the
    /// same file from its new URL and put the playhead back. Best effort.
    private func reloadAfterFolderRename(
        _ track: Track,
        wasPlaying: Bool,
        position: TimeInterval
    ) {
        do {
            try engine.load(url: track.url)
            if position > 0 {
                engine.seek(to: position)
            }
            if wasPlaying {
                engine.play()
            }
        } catch {
            statusMessage = Lf("文件夹已重命名，但无法重新加载《%@》：%@", track.title, engine.lastError ?? L("未知错误"))
        }
    }

    /// Points a missing row at a new file. `updateTrackURLs` keeps the track
    /// ID, so playlist membership and undo history survive the relocation.
    @discardableResult
    func relocateTrack(_ track: Track, to url: URL) -> String {
        library.updateTrackURLs([track.url: url])
        // A relocated file often lives outside the imported folders. Cover it
        // now, or the rescan at the next launch would mark it missing again.
        library.ensureFoldersCovering([url.deletingLastPathComponent()])
        refreshFromLibrary()
        objectWillChange.send()
        surfacePersistenceError()
        let message = Lf("已重新定位《%@》：%@", track.title, url.lastPathComponent)
        statusMessage = message
        return message
    }

    /// 「从音乐库移除」 for any row. Only the index and playlist references
    /// change; the audio files stay on disk.
    @discardableResult
    func removeTracksFromLibrary(_ trackIDs: [UUID]) -> String {
        let ids = Set(trackIDs)
        guard !ids.isEmpty else { return "" }
        let title = ids.count == 1
            ? ids.first.flatMap { id in tracks.first { $0.id == id }?.title }
            : nil
        library.removeTracks(ids: ids)
        refreshFromLibrary()
        objectWillChange.send()
        surfacePersistenceError()
        let message = title.map { Lf("已从音乐库移除《%@》，文件仍保留在磁盘上。", $0) }
            ?? Lf("已从音乐库移除 %d 首歌曲，文件仍保留在磁盘上。", ids.count)
        statusMessage = message
        return message
    }

    /// Settings → missing-file 「移除」 reuses the same core path.
    @discardableResult
    func removeMissingTrack(_ track: Track) -> String {
        removeTracksFromLibrary([track.id])
    }

    /// Settings → removed file 「重新添加」: forget the removal and scan the
    /// file back in. Only the index changes; the file on disk is untouched.
    func reAddRemovedTrack(_ track: Track) async {
        guard !isScanning else {
            statusMessage = L("正在扫描音乐库，请稍后再导入。")
            return
        }
        isScanning = true
        await library.reAddRemovedTrack(track)
        isScanning = false
        refreshFromLibrary()
        prepareLibraryFormats()
    }

    private func saveSettingsAndNotify() {
        library.saveSettings()
        surfacePersistenceError()
        objectWillChange.send()
    }

    /// A persistence failure must not live only in `LibraryStore.lastError`.
    /// Called after user-triggered writes; automatic playback-state saves stay
    /// silent so a full disk cannot spam the banner every five seconds.
    private func surfacePersistenceError() {
        guard let error = library.lastError else { return }
        statusMessage = Lf("保存失败：%@", error.localizedDescription)
    }

    // MARK: - Persistence

    /// Writes queue, current track and position into `AppSettings` so the next
    /// launch restores the session without autoplaying.
    func savePlaybackState() {
        var settings = library.settings
        settings.lastQueue = queue.trackIDs
        settings.lastTrackID = currentTrack?.id
        settings.lastPosition = max(0, displayPosition)
        settings.playbackMode = queue.mode.rawValue
        library.settings = settings
        library.saveSettings()
    }

    private func restorePlaybackState() {
        tracks = library.index.tracks
        let settings = library.settings

        var ids = settings.lastQueue.filter { id in tracks.contains { $0.id == id } }
        if let id = settings.lastTrackID,
           tracks.contains(where: { $0.id == id }),
           !ids.contains(id) {
            ids.insert(id, at: 0)
        }
        let mode = PlaybackMode(rawValue: settings.playbackMode) ?? .repeatAll
        let currentIndex = settings.lastTrackID.flatMap { ids.firstIndex(of: $0) } ?? 0
        queue = PlaybackQueue(trackIDs: ids, currentIndex: currentIndex, mode: mode)

        guard let id = settings.lastTrackID,
              let track = tracks.first(where: { $0.id == id }) else { return }
        currentTrack = track
        // Deliberately do not load the file yet: the audio engine is created on
        // first play, so launch stays fast and never autoplays.
        restoredPosition = max(0, settings.lastPosition)
    }

    // MARK: - Engine observation

    private func observeEngine() {
        engine.$isPlaying
            .sink { [weak self] playing in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isPlaying = playing
                    if playing {
                        self.startSaveTimer()
                    } else {
                        self.stopSaveTimer()
                        self.savePlaybackState()
                    }
                }
            }
            .store(in: &cancellables)

        engine.onFinish = { [weak self] in
            Task { @MainActor [weak self] in
                self?.next()
            }
        }

        $currentTrack
            .sink { [weak self] track in
                Task { @MainActor [weak self] in
                    self?.loadLyrics(for: track)
                }
            }
            .store(in: &cancellables)

        // The engine publishes at ~10 Hz: a 2 Hz timer made lyric lines lag up
        // to half a second, so at a boundary the previous line stayed on top
        // while the next line was already being sung below it.
        engine.$position
            .sink { [weak self] position in
                Task { @MainActor [weak self] in
                    self?.updateCurrentLyricLine(at: position)
                }
            }
            .store(in: &cancellables)
    }

    private func startSaveTimer() {
        guard saveTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.savePlaybackState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }

    private func stopSaveTimer() {
        saveTimer?.invalidate()
        saveTimer = nil
    }

    // MARK: - Keyboard shortcuts

    func requestSearchFocus() {
        searchFocusRequest = UUID()
    }

    private func endSearchFocus() {
        endSearchFocusRequest = UUID()
    }

    /// Used when returning from mini mode: the main window must not hand the
    /// search field the keyboard focus, or space/⌘←/⌘→ stop working.
    func clearSearchFocus() {
        isSearchFocused = false
        endSearchFocus()
    }

    /// Closes the FFmpeg banner: it stays until the user fixes the dependency
    /// or dismisses it.
    func dismissStatus() {
        ffmpegPrompt.clear()
        pendingTranscodeTrack = nil
    }

    /// An error the user should read: it stays until closed.
    func showWarning(_ text: String) {
        showNotice(AppNotice(kind: .warning, text: text))
    }

    /// Clicking anywhere outside a text field resigns the search field, so
    /// playback shortcuts work again after the user has searched something.
    private func installSearchFocusMonitor() {
        searchFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  self.isSearchFocused,
                  let window = event.window,
                  Self.isMainContentWindow(window) else { return event }
            let hit = window.contentView?.hitTest(event.locationInWindow)
            if !Self.isTextInput(hit) {
                self.endSearchFocus()
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private static func isMainContentWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && !window.isSheet && window.canBecomeMain
    }

    private static func isTextInput(_ view: NSView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is NSTextField || candidate is NSTextView {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if NSApp.modalWindow == nil, event.keyCode == 53, isSearchFocused {
            endSearchFocus()
            return true
        }
        // Space/arrows belong to the main window only. Any presented sheet
        // (settings, lyrics import) owns the keyboard, and panels such as the
        // lyrics overlay must not receive playback shortcuts.
        guard NSApp.modalWindow == nil,
              !isSettingsPresented,
              isMainWindowKey,
              !isSearchFocused,
              !isEditingText else { return false }

        // ⌘←/⌘→ skip tracks. Checked before the plain-arrow modifier guard
        // below, which deliberately rejects every Command chord.
        let commandChord = event.modifierFlags
            .intersection([.command, .option, .control, .shift])
        if commandChord == .command, !event.isARepeat {
            switch event.keyCode {
            case 3: // ⌘F
                requestSearchFocus()
                return true
            case 123: // ⌘←
                previous()
                return true
            case 124: // ⌘→
                next()
                return true
            default:
                break
            }
        }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }

        switch event.keyCode {
        case 49: // space
            guard !event.isARepeat else { return true }
            togglePlayPause()
            return true
        case 123: // left arrow
            seek(by: -5)
            return true
        case 124: // right arrow
            seek(by: 5)
            return true
        default:
            return false
        }
    }

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private var isMainWindowKey: Bool {
        guard let window = NSApp.keyWindow else { return false }
        return !(window is NSPanel) && !window.isSheet && window.canBecomeMain
    }
}
