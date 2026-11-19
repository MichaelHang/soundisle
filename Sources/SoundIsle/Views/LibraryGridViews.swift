import AppKit
import SoundIsleCore
import SwiftUI

// The 专辑/歌手 browser: a card grid per selection, and a detail page per
// card. The grid keeps the browsing light; the detail page reuses the flat
// list's TrackRow so hover, selection, right-click actions and dragging into a
// playlist behave exactly as they do in 全部音乐.

// MARK: - Shared chrome

/// The browsing page's title row: view name, totals, scanning state, rescan.
private struct LibraryGridHeader: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    let title: String
    let meta: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(theme.text)
                .lineLimit(1)
            Text(meta)
                .font(.system(size: 11.5))
                .foregroundColor(theme.mutedText(0.5))
                .lineLimit(1)

            Spacer(minLength: 12)

            if model.isScanning {
                HStack(spacing: 3) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                    Text(L("扫描中…"))
                        .font(.system(size: 10.5))
                        .foregroundColor(theme.mutedText(0.5))
                }
            }

            Button {
                Task { await model.rescan() }
            } label: {
                Icons.refresh
                    .foregroundColor(theme.text.opacity(model.folders.isEmpty ? 0.25 : 0.6))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isScanning || model.folders.isEmpty)
            .help(L("重新扫描音乐文件夹"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

/// Empty library / no search hits, shared by both card grids.
private struct LibraryGridEmptyState: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let searching = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            Icons.emptyLibrary
                .foregroundColor(theme.mutedText(0.28))
            Text(searching ? L("没有匹配的歌曲") : L("音乐库是空的"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.text.opacity(0.85))
            Text(searching ? L("换个关键词，或清空搜索框。") : L("把音乐文件或文件夹拖到这里，或者选择一个文件夹。"))
                .font(.system(size: 12))
                .foregroundColor(theme.mutedText(0.5))
                .multilineTextAlignment(.center)

            Button {
                if searching {
                    model.searchText = ""
                } else if model.tracks.isEmpty {
                    model.importFolders(model.openFolders())
                } else {
                    model.select(.allMusic)
                }
            } label: {
                Text(searching ? L("清空搜索") : (model.tracks.isEmpty ? L("选择文件夹") : L("查看全部音乐")))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.accentLight)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(
                        theme.accent.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.accent.opacity(0.35), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isScanning)
            .opacity(model.isScanning ? 0.45 : 1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

/// 一小时三分 / 四十二分钟, used by the page totals and the detail headers.
private func gridDurationText(_ tracks: [Track]) -> String {
    let seconds = Int(tracks.reduce(0) { $0 + $1.duration })
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return hours > 0 ? Lf("%d 小时 %d 分", hours, minutes) : Lf("%d 分钟", minutes)
}

/// Capsule 播放全部 button shared by both detail pages.
private struct PlayAllButton: View {
    @Environment(\.theme) private var theme
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 5) {
                Icons.symbol("play.fill", size: 9, weight: .bold)
                Text(L("播放全部"))
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(theme.accentLight)
            .padding(.horizontal, 13)
            .frame(height: 26)
            .background(
                theme.accent.opacity(0.15),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(theme.accent.opacity(0.32), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Album grid

/// The 专辑 page. The grid is the browsing surface; picking a card slides in
/// the album detail page. Detail state lives here so switching between 专辑
/// and 歌手 (separate view identities in MainWindowView) always lands on the
/// grid, and the sidebar selection doubles as "back".
struct AlbumGridView: View {
    @ObservedObject var model: AppModel
    @State private var detail: TrackGroup?

    var body: some View {
        if let detail {
            AlbumDetailView(model: model, group: detail, onBack: { self.detail = nil })
        } else {
            AlbumCardGrid(model: model, onOpen: { detail = $0 })
        }
    }
}

private struct AlbumCardGrid: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    let onOpen: (TrackGroup) -> Void

    var body: some View {
        VStack(spacing: 0) {
            LibraryGridHeader(model: model, title: L("专辑"), meta: meta)

            if let message = model.ffmpegPrompt.message {
                TrackListStatusBanner(model: model, message: message)
            }

            if model.libraryGroups.isEmpty {
                LibraryGridEmptyState(model: model)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 148, maximum: 200), spacing: 14)],
                        spacing: 20
                    ) {
                        ForEach(model.libraryGroups) { group in
                            AlbumCard(
                                group: group,
                                artworkURL: coverURL(for: group),
                                onOpen: { onOpen(group) }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meta: String {
        let groups = model.libraryGroups
        let tracks = groups.flatMap { $0.tracks }
        return Lf("%d 张专辑 · %d 首 · %@", groups.count, tracks.count, gridDurationText(tracks))
    }

    /// The first track with a cached cover, so a leading track without
    /// embedded art does not blank the whole card.
    private func coverURL(for group: TrackGroup) -> URL? {
        group.tracks.lazy.compactMap { model.library.artworkURL(for: $0) }.first
    }
}

/// One album card: cover, album name, artist (群星 for compilations) · year.
private struct AlbumCard: View {
    @Environment(\.theme) private var theme
    @State private var isHovering = false
    let group: TrackGroup
    let artworkURL: URL?
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ArtworkImage(url: artworkURL, size: 200, cornerRadius: 8)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 7, y: 3)
            Text(group.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundColor(theme.mutedText(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(7)
        .background(
            isHovering ? theme.raisedFill : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
    }

    private var subtitle: String {
        var parts: [String] = [group.artist]
        if let year = group.year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }
}

/// One album's page: header with the big cover, then its tracks without the
/// artist column unless the album is a compilation (群星 needs per-track
/// artists visible).
private struct AlbumDetailView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    let group: TrackGroup
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            backButton
            if let message = model.ffmpegPrompt.message {
                TrackListStatusBanner(model: model, message: message)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(Array(group.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track: track,
                            index: index,
                            isCurrent: model.currentTrack?.id == track.id,
                            isSelected: model.selectedTrackIDs.contains(track.id),
                            isPlaying: model.isPlaying,
                            rowStyle: model.library.settings.rowStyle,
                            artworkURL: model.library.artworkURL(for: track),
                            showsArtistColumn: group.isCompilation,
                            showsAlbumColumn: false,
                            showsAddedColumn: false,
                            onTap: { model.handleTrackClick(track.id, source: group.tracks) }
                        )
                        .padding(.horizontal, 18)
                        .themedContextMenu {
                            TrackContextMenu(model: model, trackID: track.id)
                        }
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backButton: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Icons.symbol("chevron.left", size: 10, weight: .semibold)
                    Text(L("返回专辑列表"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(theme.accentLight)
                .padding(.horizontal, 9)
                .frame(height: 23)
                .background(theme.accent.opacity(0.13), in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ArtworkImage(url: coverURL, size: 120, cornerRadius: 10)
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(L("专辑"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(theme.mutedText(0.45))
                Text(group.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(2)
                Text(group.artist)
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedText(0.7))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 10.5))
                    .foregroundColor(theme.mutedText(0.5))
                    .lineLimit(1)
                PlayAllButton {
                    if let first = group.tracks.first {
                        model.play(trackID: first.id, source: group.tracks)
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var meta: String {
        var parts: [String] = []
        if let year = group.year { parts.append(String(year)) }
        parts.append(Lf("%d 首", group.tracks.count))
        parts.append(gridDurationText(group.tracks))
        return parts.joined(separator: " · ")
    }

    private var coverURL: URL? {
        group.tracks.first.map { model.library.artworkURL(for: $0) } ?? nil
    }
}

// MARK: - Artist grid

/// The 歌手 page, mirroring the album grid with collage cards.
struct ArtistGridView: View {
    @ObservedObject var model: AppModel
    @State private var detail: TrackGroup?

    var body: some View {
        if let detail {
            ArtistDetailView(model: model, group: detail, onBack: { self.detail = nil })
        } else {
            ArtistCardGrid(model: model, onOpen: { detail = $0 })
        }
    }
}

private struct ArtistCardGrid: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    let onOpen: (TrackGroup) -> Void

    var body: some View {
        VStack(spacing: 0) {
            LibraryGridHeader(model: model, title: L("歌手"), meta: meta)

            if let message = model.ffmpegPrompt.message {
                TrackListStatusBanner(model: model, message: message)
            }

            if model.libraryGroups.isEmpty {
                LibraryGridEmptyState(model: model)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 148, maximum: 200), spacing: 14)],
                        spacing: 20
                    ) {
                        ForEach(model.libraryGroups) { group in
                            ArtistCard(
                                group: group,
                                artworkURLs: collageURLs(for: group),
                                onOpen: { onOpen(group) }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meta: String {
        let groups = model.libraryGroups
        let tracks = groups.flatMap { $0.tracks }
        return Lf("%d 位歌手 · %d 首 · %@", groups.count, tracks.count, gridDurationText(tracks))
    }

    /// Covers of the artist's first four distinct albums for the collage.
    private func collageURLs(for group: TrackGroup) -> [URL?] {
        var seen = Set<String>()
        var urls: [URL?] = []
        for track in group.tracks {
            guard !track.album.isEmpty, seen.insert(track.album).inserted else { continue }
            urls.append(model.library.artworkURL(for: track))
            if urls.count == 4 { break }
        }
        return urls
    }
}

/// One artist card: a 2×2 collage of album covers (one cover fills the square
/// when the artist has a single album), name, album/track counts.
private struct ArtistCard: View {
    @Environment(\.theme) private var theme
    @State private var isHovering = false
    let group: TrackGroup
    let artworkURLs: [URL?]
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ArtistCollage(urls: artworkURLs, size: 400, cornerRadius: 8)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 7, y: 3)
            Text(group.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(group.detail)
                .font(.system(size: 10.5))
                .foregroundColor(theme.mutedText(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(7)
        .background(
            isHovering ? theme.raisedFill : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
    }
}

/// A square collage of up to four covers. A single cover fills the whole
/// square; missing covers fall back to the gradient-and-note placeholder.
struct ArtistCollage: View {
    let urls: [URL?]
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 6

    private let gap: CGFloat = 1.5

    var body: some View {
        Group {
            if urls.count > 1 {
                VStack(spacing: gap) {
                    HStack(spacing: gap) { cell(0); cell(1) }
                    HStack(spacing: gap) { cell(2); cell(3) }
                }
            } else {
                ArtworkImage(url: urls.first ?? nil, size: size, cornerRadius: 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func cell(_ index: Int) -> some View {
        ArtworkImage(url: index < urls.count ? urls[index] : nil, size: size / 2, cornerRadius: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One artist's page: header with the collage, then the artist's tracks
/// sectioned by album so each record stays legible.
private struct ArtistDetailView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    let group: TrackGroup
    let onBack: () -> Void

    private struct AlbumSection: Identifiable {
        let name: String
        let tracks: [Track]
        var id: String { name }
    }

    var body: some View {
        VStack(spacing: 0) {
            backButton
            if let message = model.ffmpegPrompt.message {
                TrackListStatusBanner(model: model, message: message)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(sections) { section in
                        sectionHeader(section)
                        ForEach(Array(section.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                index: index,
                                isCurrent: model.currentTrack?.id == track.id,
                                isSelected: model.selectedTrackIDs.contains(track.id),
                                isPlaying: model.isPlaying,
                                rowStyle: model.library.settings.rowStyle,
                                artworkURL: model.library.artworkURL(for: track),
                                showsArtistColumn: false,
                                showsAlbumColumn: false,
                                showsAddedColumn: false,
                                // Tapping a track queues that album; 播放全部
                                // queues the artist's whole catalogue.
                                onTap: { model.handleTrackClick(track.id, source: section.tracks) }
                            )
                            .padding(.horizontal, 18)
                            .themedContextMenu {
                                TrackContextMenu(model: model, trackID: track.id)
                            }
                        }
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sections: [AlbumSection] {
        var byAlbum: [String: [Track]] = [:]
        var order: [String] = []
        for track in group.tracks {
            let key = track.album.isEmpty ? L("未知专辑") : track.album
            if byAlbum[key] == nil { order.append(key) }
            byAlbum[key, default: []].append(track)
        }
        return order.map { AlbumSection(name: $0, tracks: byAlbum[$0] ?? []) }
    }

    private func sectionHeader(_ section: AlbumSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(Lf("%d 首", section.tracks.count))
                .font(.system(size: 10.5))
                .foregroundColor(theme.mutedText(0.5))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var backButton: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Icons.symbol("chevron.left", size: 10, weight: .semibold)
                    Text(L("返回歌手列表"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(theme.accentLight)
                .padding(.horizontal, 9)
                .frame(height: 23)
                .background(theme.accent.opacity(0.13), in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ArtistCollage(urls: collageURLs, size: 240, cornerRadius: 10)
                .frame(width: 100, height: 100)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(L("歌手"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(theme.mutedText(0.45))
                Text(group.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(2)
                Text(group.detail)
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedText(0.6))
                    .lineLimit(1)
                PlayAllButton {
                    if let first = group.tracks.first {
                        model.play(trackID: first.id, source: group.tracks)
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var collageURLs: [URL?] {
        var seen = Set<String>()
        var urls: [URL?] = []
        for track in group.tracks {
            guard !track.album.isEmpty, seen.insert(track.album).inserted else { continue }
            urls.append(model.library.artworkURL(for: track))
            if urls.count == 4 { break }
        }
        return urls
    }
}
