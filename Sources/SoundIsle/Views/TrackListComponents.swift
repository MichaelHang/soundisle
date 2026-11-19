import AppKit
import SoundIsleCore
import SwiftUI
import UniformTypeIdentifiers

/// One source of truth for the list's five columns. Header buttons and every
/// row use the same widths, so labels stay over their data at any window
/// width. The compact target is 900pt: 190 sidebar + 36 outer padding leaves
/// room for title to flex next to these fixed columns.
enum TrackColumns {
    static let leading: CGFloat = 24
    static let spacing: CGFloat = 10
    static let rowPadding: CGFloat = 8
    static let artist: CGFloat = 110
    static let album: CGFloat = 130
    static let duration: CGFloat = 50
    static let added: CGFloat = 82
    static let rowHeight: CGFloat = 34
}

/// One row of the track list, shared by the flat list and the album/artist
/// browser so the two never drift apart.
///
/// `showsArtistColumn` / `showsAlbumColumn` / `showsAddedColumn` drop the
/// columns the surrounding page already states: an album detail page names the
/// album in its header, and the 修改时间 column only matters in flat lists.
struct TrackRow: View {
    @Environment(\.theme) private var theme
    let track: Track
    let index: Int
    let isCurrent: Bool
    let isSelected: Bool
    let isPlaying: Bool
    let rowStyle: String
    let artworkURL: URL?
    var titleDetail: String? = nil
    var showsArtistColumn: Bool = true
    var showsAlbumColumn: Bool = true
    var showsAddedColumn: Bool = true
    let onTap: () -> Void
    let onContextMenu: () -> Void

    @State private var isHovering = false

    private static let addedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        // A plain row instead of a `Button`: a Button swallows the drag
        // gesture, and dragging rows into playlists is required.
        HStack(spacing: TrackColumns.spacing) {
            leading
                .frame(width: TrackColumns.leading)

            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if track.isMissing {
                    Text(L("文件缺失"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(theme.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.warning.opacity(0.14), in: Capsule())
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsArtistColumn {
                Text(track.artist)
                    .font(.system(size: 10.5))
                    .foregroundColor(theme.mutedText(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: TrackColumns.artist, alignment: .leading)
            }

            if showsAlbumColumn {
                Text(track.album)
                    .font(.system(size: 10.5))
                    .foregroundColor(theme.mutedText(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: TrackColumns.album, alignment: .leading)
            }

            Text(TimeText.string(track.duration))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundColor(theme.mutedText(0.45))
                .frame(width: TrackColumns.duration, alignment: .trailing)

            if showsAddedColumn {
                Text(Self.addedFormatter.string(from: track.modifiedAt))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(theme.mutedText(0.4))
                    .frame(width: TrackColumns.added, alignment: .trailing)
            }
        }
        .padding(.horizontal, TrackColumns.rowPadding)
        .frame(height: TrackColumns.rowHeight)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
        // Overlay rather than background: the catcher claims only right-click
        // events, so left-click play, drag and multi-select keep working.
        .overlay {
            RightClickCatcher(onRightClick: onContextMenu)
        }
    }

    private var title: String {
        if let titleDetail { return titleDetail }
        return track.title
    }

    @ViewBuilder
    private var leading: some View {
        if isCurrent {
            PlayingIndicator(isPlaying: isPlaying)
        } else if rowStyle == "cover" {
            ArtworkThumbnail(url: artworkURL)
        } else {
            Text("\(index + 1)")
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundColor(theme.mutedText(0.4))
        }
    }

    private var titleColor: Color {
        if track.isMissing { return theme.mutedText(0.45) }
        return isCurrent ? theme.accentLight : theme.text
    }

    private var rowBackground: Color {
        if isCurrent { return theme.accent.opacity(0.13) }
        if isSelected { return theme.accent.opacity(0.09) }
        if isHovering { return theme.raisedFill }
        return .clear
    }
}

// MARK: - Status banner

/// Warning banner with the FFmpeg install prompt, shared by both list views
/// so the prompt stays identical.
struct TrackListStatusBanner: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Icons.warning
                    .foregroundColor(theme.warning)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundColor(theme.text.opacity(0.82))
                    .lineLimit(2)
                Spacer(minLength: 6)
                Button {
                    model.dismissStatus()
                } label: {
                    Icons.close
                        .foregroundColor(theme.mutedText(0.5))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("关闭"))
            }
            if model.showsFFmpegInstallPrompt {
                HStack(spacing: 12) {
                    Button(L("复制 brew install ffmpeg")) {
                        model.copyFFmpegInstallCommand()
                    }
                    Button(L("重新检测")) {
                        model.redetectFFmpeg()
                    }
                    Button(L("选择 FFmpeg…")) {
                        model.chooseFFmpegPath()
                    }
                    Text(L("原生格式仍可正常播放"))
                        .foregroundColor(theme.mutedText(0.45))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10.5))
                .buttonStyle(.plain)
                .foregroundColor(theme.accentLight)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            theme.warning.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.warning.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }
}

// MARK: - Right-click catcher

/// Claims right-clicks without stealing anything else. AppKit asks `hitTest`
/// while dispatching an event, so returning nil for every non-right-mouse
/// event leaves SwiftUI's tap and drag gestures untouched.
struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onRightClick = onRightClick
    }

    private final class CatcherView: NSView {
        var onRightClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }
    }
}

// MARK: - Track context menu

/// Themed replacement for the system context menu, shared by both list views.
/// The popover owns dismissal (click-away and Esc); `onClose` also lets each
/// action close it before opening a sheet or mutating the queue.
struct TrackContextMenu: View {
    @ObservedObject var model: AppModel
    let trackID: UUID
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @State private var hoveredID: String?

    private var targetIDs: [UUID] { model.contextTrackIDs(for: trackID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            action("trash", L("从音乐库移除")) {
                model.removeTracksFromLibrary(targetIDs)
            }

            separator

            if case .playlist(let playlistID) = model.selection {
                action("minus.circle", L("从播放列表移除")) {
                    for id in targetIDs {
                        model.removeFromPlaylist(playlistID, trackID: id)
                    }
                }
                separator
            }

            playlistSection
        }
        .padding(5)
        .frame(width: 240)
        .glassPanel(cornerRadius: 10)
        .shadow(
            color: .black.opacity(theme.isDark ? 0.5 : 0.18),
            radius: 16,
            y: 6
        )
        .onExitCommand(perform: onClose)
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L("添加到播放列表"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(theme.mutedText(0.42))
                .padding(.horizontal, 8)
                .padding(.top, 3)
                .padding(.bottom, 3)

            if model.playlists.playlists.isEmpty {
                Text(L("暂无播放列表"))
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedText(0.35))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
            } else {
                ScrollView(showsIndicators: true) {
                    VStack(spacing: 1) {
                        ForEach(model.playlists.playlists) { playlist in
                            action("music.note.list", playlist.name) {
                                model.addToPlaylist(playlist.id, trackIDs: targetIDs)
                            }
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(model.playlists.playlists.count) * 28, 168))
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
    }

    private func action(
        _ symbol: String,
        _ title: String,
        run: @escaping () -> Void
    ) -> some View {
        let key = "\(symbol)-\(title)"
        return Button {
            onClose()
            run()
        } label: {
            HStack(spacing: 8) {
                Icons.symbol(symbol, size: 11)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(theme.text.opacity(0.9))
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(
                hoveredID == key ? theme.accent.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = key
            } else if hoveredID == key {
                hoveredID = nil
            }
        }
    }
}

// MARK: - Cover thumbnail

struct ArtworkThumbnail: View {
    @Environment(\.theme) private var theme
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.coverGradient)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Icons.coverNote
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onAppear(perform: load)
        .onChange(of: url) { _ in load() }
    }

    private func load() {
        image = url.flatMap { NSImage(contentsOf: $0) }
    }
}

// MARK: - Playing indicator

/// Three little bars marking the current track. Kept static: an animated
/// equalizer drove SwiftUI commits continuously and dominated idle playback
/// CPU on older Macs, while a static glyph already communicates "playing".
struct PlayingIndicator: View {
    @Environment(\.theme) private var theme
    let isPlaying: Bool

    private let heights: [CGFloat] = [5, 11, 8]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { bar in
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 2.5, height: isPlaying ? heights[bar] : 3)
            }
        }
        .frame(width: 14, height: 12, alignment: .bottom)
    }
}
