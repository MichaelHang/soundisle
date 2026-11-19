import AppKit
import Foundation
import SoundIsleCore
import SwiftUI
import UniformTypeIdentifiers

struct TrackListView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    @State private var contextMenuTrackID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            columnHeader

            if let message = model.statusMessage {
                TrackListStatusBanner(model: model, message: message)
            }

            if model.visibleTracks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.visibleTracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                index: index,
                                isCurrent: model.currentTrack?.id == track.id,
                                isSelected: model.selectedTrackIDs.contains(track.id),
                                isPlaying: model.isPlaying,
                                rowStyle: model.library.settings.rowStyle,
                                artworkURL: model.library.artworkURL(for: track),
                                onTap: { model.handleTrackClick(track.id) },
                                onContextMenu: { contextMenuTrackID = track.id }
                            )
                            .onDrag {
                                NSItemProvider(object: track.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { providers in
                                handleReorder(providers, onto: track)
                            }
                            .popover(
                                isPresented: Binding(
                                    get: { contextMenuTrackID == track.id },
                                    set: { presented in
                                        if !presented, contextMenuTrackID == track.id {
                                            contextMenuTrackID = nil
                                        }
                                    }
                                ),
                                arrowEdge: .bottom
                            ) {
                                TrackContextMenu(
                                    model: model,
                                    trackID: track.id
                                ) {
                                    contextMenuTrackID = nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
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
        .padding(.bottom, 8)
    }

    private var columnHeader: some View {
        HStack(spacing: TrackColumns.spacing) {
            Color.clear
                .frame(width: TrackColumns.leading, height: 1)
            sortButton(L("标题"), .title, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortButton(L("歌手"), .artist, alignment: .leading)
                .frame(width: TrackColumns.artist, alignment: .leading)
            sortButton(L("专辑"), .album, alignment: .leading)
                .frame(width: TrackColumns.album, alignment: .leading)
            sortButton(L("时长"), .duration, alignment: .trailing)
                .frame(width: TrackColumns.duration, alignment: .trailing)
            sortButton(L("添加时间"), .dateAdded, alignment: .trailing)
                .frame(width: TrackColumns.added, alignment: .trailing)
        }
        .padding(.horizontal, TrackColumns.rowPadding)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    private func sortButton(
        _ title: String,
        _ candidate: TrackSort,
        alignment: Alignment
    ) -> some View {
        let active = model.sortsColumns && model.sort == candidate
        return Button {
            model.toggleSort(candidate)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if active {
                    Icons.sortArrow(ascending: model.sortAscending)
                }
            }
            .font(.system(size: 10.5, weight: active ? .semibold : .regular))
            .foregroundColor(active ? theme.accentLight : theme.mutedText(0.45))
            .frame(height: 22)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.accent.opacity(0.14))
                        .padding(.horizontal, -6)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Lf("按%@排序", title))
    }

    private var title: String {
        switch model.selection {
        case .allMusic:
            return L("全部音乐")
        case .recentlyAdded:
            return L("最近添加")
        case .albums:
            return L("专辑")
        case .artists:
            return L("歌手")
        case .folder(let folder):
            return folder.lastPathComponent
        case .playlist(let id):
            return model.playlists.playlists.first(where: { $0.id == id })?.name ?? L("播放列表")
        }
    }

    private var meta: String {
        let tracks = model.visibleTracks
        let seconds = Int(tracks.reduce(0) { $0 + $1.duration })
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let duration = hours > 0
            ? Lf("%d 小时 %d 分", hours, minutes)
            : Lf("%d 分钟", minutes)
        return Lf("%d 首 · %@", tracks.count, duration)
    }

    private func handleReorder(_ providers: [NSItemProvider], onto target: Track) -> Bool {
        guard model.canReorderPlaylist else { return false }
        Task { @MainActor in
            for provider in providers {
                guard let text = await provider.textValue(),
                      let id = UUID(uuidString: text) else { continue }
                model.moveTrack(id, onto: target.id)
            }
        }
        return true
    }

    private var emptyState: some View {
        let searching = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let playlistEmpty = model.isPlaylistSelection

        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            Icons.emptyLibrary
                .foregroundColor(theme.mutedText(0.28))
            Text(emptyTitle(searching: searching, playlistEmpty: playlistEmpty))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.text.opacity(0.85))
            Text(emptyHint(searching: searching, playlistEmpty: playlistEmpty))
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

    private func emptyTitle(searching: Bool, playlistEmpty: Bool) -> String {
        if searching { return L("没有匹配的歌曲") }
        if model.tracks.isEmpty { return L("音乐库是空的") }
        if playlistEmpty { return L("这个播放列表还是空的") }
        return L("这个文件夹里没有歌曲")
    }

    private func emptyHint(searching: Bool, playlistEmpty: Bool) -> String {
        if searching { return L("换个关键词，或清空搜索框。") }
        if model.tracks.isEmpty { return L("把音乐文件或文件夹拖到这里，或者选择一个文件夹。") }
        if playlistEmpty { return L("回到「全部音乐」，把歌曲拖进侧栏的播放列表。") }
        return L("换一个文件夹，或回到「全部音乐」。")
    }
}
