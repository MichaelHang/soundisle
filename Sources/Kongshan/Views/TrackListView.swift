import AppKit
import Foundation
import SoundIsleCore
import SwiftUI
import UniformTypeIdentifiers

struct TrackListView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            columnHeader

            // The list keeps one banner: the FFmpeg prompt, which is a
            // persistent, multi-action state. Every other message is the
            // window's notice, wherever the user happens to be.
            if let message = model.ffmpegPrompt.message {
                ffmpegBanner(message)
            }

            if model.visibleTracks.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(model.visibleTracks) { track in
                            TrackRow(
                                track: track,
                                isCurrent: model.currentTrack?.id == track.id,
                                isSelected: model.selectedTrackIDs.contains(track.id),
                                isPlaying: model.isPlaying,
                                artworkURL: model.library.artworkURL(for: track),
                                onTap: { model.handleTrackClick(track.id) },
                                onDoubleClick: { model.handleTrackDoubleClick(track.id) }
                            )
                            .onDrag {
                                NSItemProvider(object: track.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { providers in
                                handleReorder(providers, onto: track)
                            }
                            .contextMenu {
                                TrackMenuItems(model: model, trackID: track.id)
                            }
                            .id(track.id)
                        }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 14)
                    }
                    .onAppear { scrollToTargetIfNeeded(proxy) }
                    .onChange(of: model.listScrollTarget) { _ in
                        scrollToTargetIfNeeded(proxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The lyrics page is a detail view; returning to the list should show the
    /// playing track instead of wherever the list was scrolled before.
    private func scrollToTargetIfNeeded(_ proxy: ScrollViewProxy) {
        guard let target = model.listScrollTarget else { return }
        model.listScrollTarget = nil
        guard model.visibleTracks.contains(where: { $0.id == target }) else { return }
        // Let the freshly-shown list lay out before asking it to scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(NSWorkspace.appReduceMotion ? nil : .easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(theme.text)
                .lineLimit(1)
            Text(meta)
                .font(.callout)
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
                        .font(.subheadline)
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
            sortButton(L("艺人"), .artist, alignment: .leading)
                .frame(width: TrackColumns.artist, alignment: .leading)
            sortButton(L("专辑"), .album, alignment: .leading)
                .frame(width: TrackColumns.album, alignment: .leading)
            sortButton(L("时长"), .duration, alignment: .trailing)
                .frame(width: TrackColumns.duration, alignment: .trailing)
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
            .font(.subheadline.weight(active ? .semibold : .regular))
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
        case .albums:
            return L("专辑")
        case .artists:
            return L("艺人")
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

    /// The one banner the list still owns: ffmpeg is missing and a format
    /// needs it. Persistent, and carries the three ways to fix it.
    private func ffmpegBanner(_ message: String) -> some View {
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

    private var emptyState: some View {
        let searching = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let playlistEmpty = model.isPlaylistSelection

        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            Icons.emptyLibrary
                .accessibilityHidden(true)
                .foregroundColor(theme.mutedText(0.28))
            Text(emptyTitle(searching: searching, playlistEmpty: playlistEmpty))
                .font(.title2.weight(.semibold))
                .foregroundColor(theme.text.opacity(0.85))
            Text(emptyHint(searching: searching, playlistEmpty: playlistEmpty))
                .font(.callout)
                .foregroundColor(theme.mutedText(0.5))
                .multilineTextAlignment(.center)

            Button {
                if searching {
                    model.searchText = ""
                } else if model.tracks.isEmpty {
                    model.promptImportFolders()
                } else {
                    model.select(.allMusic)
                }
            } label: {
                Text(searching ? L("清空搜索") : (model.tracks.isEmpty ? L("选择文件夹") : L("查看全部音乐")))
                    .font(.callout.weight(.medium))
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
