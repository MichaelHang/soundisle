import AppKit
import SoundIsleCore
import SwiftUI
import UniformTypeIdentifiers

/// One source of truth for the list's four columns. Header buttons and every
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
    static let rowHeight: CGFloat = 34
}

/// One row of the track list, shared by the flat list and the album/artist
/// browser so the two never drift apart.
///
/// `showsArtistColumn` / `showsAlbumColumn` drop the columns the surrounding
/// page already states: an album detail page names the album in its header,
/// an artist page names the artist.
struct TrackRow: View {
    @Environment(\.theme) private var theme
    let track: Track
    let isCurrent: Bool
    let isSelected: Bool
    let isPlaying: Bool
    let artworkURL: URL?
    var titleDetail: String? = nil
    var showsArtistColumn: Bool = true
    var showsAlbumColumn: Bool = true
    /// Single click selects; double click plays. Declared count:2 first so
    /// the double-click gesture wins over the plain one.
    let onTap: () -> Void
    var onDoubleClick: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        // A plain row instead of a `Button`: a Button swallows the drag
        // gesture, and dragging rows into playlists is required.
        HStack(spacing: TrackColumns.spacing) {
            leading
                .frame(width: TrackColumns.leading)

            HStack(spacing: 6) {
                Text(title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if track.isMissing {
                    Text(L("文件缺失"))
                        .font(.caption2.weight(.medium))
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
                    .font(.subheadline)
                    .foregroundColor(theme.mutedText(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: TrackColumns.artist, alignment: .leading)
            }

            if showsAlbumColumn {
                Text(track.album)
                    .font(.subheadline)
                    .foregroundColor(theme.mutedText(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: TrackColumns.album, alignment: .leading)
            }

            Text(TimeText.string(track.duration))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(theme.mutedText(0.45))
                .frame(width: TrackColumns.duration, alignment: .trailing)
        }
        .padding(.horizontal, TrackColumns.rowPadding)
        .frame(height: TrackColumns.rowHeight)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
        // One VoiceOver element per row: title, artist, album, duration and
        // state in the label; the column Texts are hidden as children.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint(L("连按播放"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = [title]
        if showsArtistColumn, !track.artist.isEmpty { parts.append(track.artist) }
        if showsAlbumColumn, !track.album.isEmpty { parts.append(track.album) }
        parts.append(TimeText.string(track.duration))
        if track.isMissing { parts.append(L("文件缺失")) }
        if isCurrent { parts.append(isPlaying ? L("正在播放") : L("已暂停")) }
        return parts.joined(separator: "，")
    }

    private var title: String {
        if let titleDetail { return titleDetail }
        return track.title
    }

    @ViewBuilder
    private var leading: some View {
        if isCurrent {
            PlayingIndicator(isPlaying: isPlaying)
        } else {
            // Row style is fixed to cover thumbnails; the old 序号 option and
            // its picker were removed.
            ArtworkThumbnail(url: artworkURL)
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
                    .font(.callout)
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
            .font(.subheadline)
            .buttonStyle(.plain)
            .foregroundColor(theme.accentLight)
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

// MARK: - Track context menu

/// The songs' right-click menu, rendered by the system as an NSMenu through
/// `.contextMenu`: anchored at the pointer, keyboard-navigable, and following
/// the window appearance. Actions apply to the whole selection when the
/// clicked row belongs to it, otherwise to the clicked row alone.
struct TrackMenuItems: View {
    @ObservedObject var model: AppModel
    let trackID: UUID

    var body: some View {
        let targets = model.contextTracks(for: trackID)

        Button(L("播放")) {
            if let first = targets.first {
                model.play(trackID: first.id, source: targets)
            }
        }
        .disabled(targets.isEmpty)

        Divider()

        Menu(L("添加到播放列表")) {
            Button(L("新建播放列表…")) {
                model.createPlaylistFromPrompt(adding: targets.map(\.id))
            }
            if !model.playlists.playlists.isEmpty {
                Divider()
                ForEach(model.playlists.playlists) { playlist in
                    Button(playlist.name) {
                        model.addToPlaylist(playlist.id, trackIDs: targets.map(\.id))
                    }
                }
            }
        }

        if case .playlist(let playlistID) = model.selection {
            Button(L("从播放列表移除")) {
                for id in targets.map(\.id) {
                    model.removeFromPlaylist(playlistID, trackID: id)
                }
            }
        }

        Divider()

        Button(L("在访达中显示")) {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
        }

        Divider()

        Button(L("从音乐库移除"), role: .destructive) {
            model.removeTracksFromLibrary(targets.map(\.id))
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
        .accessibilityHidden(true)
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
        .accessibilityHidden(true)
    }
}
