import AppKit
import SoundIsleCore
import SwiftUI

/// Settings shell: cache/FFmpeg, lyrics, appearance, and missing/unreadable
/// files collected by the scanner. Presented in the app's standalone settings
/// window (SwiftUI `Settings` scene); no Done button — settings apply
/// immediately and the window closes from its own close button, like
/// Music's settings.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var folderNotice: String?
    @State private var cacheNotice: String?
    // The three 文件状态 groups list 5 rows and expand on demand; a library
    // with 1000 missing files must not build 3000 buttons in a 560pt sheet.
    @State private var showAllMissing = false
    @State private var showAllRemoved = false
    @State private var showAllUnreadable = false

    private var settings: AppSettings { model.library.settings }

    private var palette: ThemePalette {
        ThemePalette.resolve(
            mode: settings.mode,
            systemIsDark: colorScheme == .dark
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                missingFilesSection
                cacheSection
                appearanceSection
            }
            .padding(22)
        }
        .frame(width: 580, height: 560)
        .background(AppBackground())
        .background(SettingsWindowConfigurator { model.registerSettingsWindow($0) })
        .soundIsleTheme(palette)
        .onAppear {
            model.refreshTranscodeCacheSize()
            // Don't let the first text field take the initial focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    // MARK: - Missing and unreadable files

    /// Folder management lives in the sidebar; this card only surfaces files
    /// the scanner could not find or read, and hides itself when there are none.
    @ViewBuilder
    private var missingFilesSection: some View {
        let missing = model.library.missingTracks
        let removed = model.library.removedTracks
        let unreadable = model.library.unreadableURLs
        if !missing.isEmpty || !removed.isEmpty || !unreadable.isEmpty || folderNotice != nil {
            sectionCard(icon: Icons.settingsFolders, title: L("文件状态")) {
                if !missing.isEmpty {
                    HStack(spacing: 8) {
                        Text(Lf("缺失文件 %d 首", missing.count))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(palette.warning)
                        Spacer(minLength: 8)
                        Button(L("移除缺失条目")) {
                            folderNotice = model.removeMissingTracks()
                        }
                    }
                    ForEach(missing.prefix(showAllMissing ? missing.count : 5)) { track in
                        HStack(spacing: 8) {
                            Text("\(track.title) — \(track.url.lastPathComponent)")
                                .font(.subheadline)
                                .foregroundColor(palette.mutedText(0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(track.url.path)
                            Spacer(minLength: 6)
                            Button(L("重新定位…")) {
                                relocate(track)
                            }
                            .help(L("选择这个文件的新位置"))
                            if FileManager.default.fileExists(atPath: track.url.path) {
                                Button(L("在 Finder 中显示")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([track.url])
                                }
                            }
                            Button(L("移除")) {
                                folderNotice = model.removeMissingTrack(track)
                            }
                        }
                        .font(.subheadline)
                    }
                    if missing.count > 5 {
                        expandButton(showAllMissing, count: missing.count - 5) {
                            showAllMissing.toggle()
                        }
                    }
                }

                if !removed.isEmpty {
                    Divider().overlay(palette.hairline)
                    Text(Lf("已从音乐库移除 %d 首", removed.count))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.mutedText(0.55))
                    ForEach(removed.prefix(showAllRemoved ? removed.count : 5)) { track in
                        HStack(spacing: 8) {
                            Text("\(track.title) — \(track.url.lastPathComponent)")
                                .font(.subheadline)
                                .foregroundColor(palette.mutedText(0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(track.url.path)
                            Spacer(minLength: 6)
                            Button(L("重新添加")) {
                                folderNotice = nil
                                Task { await model.reAddRemovedTrack(track) }
                            }
                            .help(track.url.path)
                            Button(L("在 Finder 中显示")) {
                                NSWorkspace.shared.activateFileViewerSelecting([track.url])
                            }
                        }
                        .font(.subheadline)
                    }
                    if removed.count > 5 {
                        expandButton(showAllRemoved, count: removed.count - 5) {
                            showAllRemoved.toggle()
                        }
                    }
                }

                if !unreadable.isEmpty {
                    Divider().overlay(palette.hairline)
                    Text(Lf("无法读取 %d 个文件", unreadable.count))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.warning)
                    ForEach(unreadable.prefix(showAllUnreadable ? unreadable.count : 5), id: \.self) { url in
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                            .foregroundColor(palette.mutedText(0.45))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if unreadable.count > 5 {
                        expandButton(showAllUnreadable, count: unreadable.count - 5) {
                            showAllUnreadable.toggle()
                        }
                    }
                }

                if let folderNotice {
                    Text(folderNotice)
                        .font(.subheadline)
                        .foregroundColor(palette.accentLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Cache

    private var cacheSection: some View {
        sectionCard(icon: Icons.settingsCache, title: L("缓存")) {
            Text(L("不支持的格式会转换为 ALAC 后缓存在这里，清理不会删除原始文件。"))
                .font(.subheadline)
                .foregroundColor(palette.mutedText(0.5))
            HStack(spacing: 10) {
                Button(L("清理缓存")) {
                    cacheNotice = model.clearTranscodeCache()
                }
                .disabled(model.transcodeCacheBytes == 0)
                Text(model.transcodeCacheSizeText)
                    .font(.subheadline)
                    .foregroundColor(palette.mutedText(0.4))
            }
            HStack(spacing: 10) {
                Text("FFmpeg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.text.opacity(0.7))
                Text(model.ffmpegPathText)
                    .font(.subheadline)
                    .foregroundColor(
                        model.ffmpegPathText == L("未找到")
                            ? palette.warning
                            : palette.mutedText(0.5)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Button(L("重新检测")) {
                    cacheNotice = model.redetectFFmpeg()
                }
                Button(L("选择文件…")) {
                    model.chooseFFmpegPath { message in
                        if let message {
                            cacheNotice = message
                        }
                    }
                }
            }
            if let cacheNotice {
                Text(cacheNotice)
                    .font(.subheadline)
                    .foregroundColor(palette.accentLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        sectionCard(icon: Icons.settingsAppearance, title: L("外观")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(L("语言"))
                        .font(.callout)
                        .foregroundColor(palette.text.opacity(0.75))
                        .frame(width: 92, alignment: .leading)
                    Picker(
                        "",
                        selection: Binding(
                            get: { settings.appLanguage },
                            set: { model.setAppLanguage($0) }
                        )
                    ) {
                        Text(L("跟随系统")).tag("system")
                        Text(L("中文")).tag("zh")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Spacer(minLength: 0)
                }

                Text(L("更改语言后需要重启空山。"))
                    .font(.subheadline)
                    .foregroundColor(palette.mutedText(0.45))
            }

            HStack(spacing: 10) {
                Text(L("明暗模式"))
                    .font(.callout)
                    .foregroundColor(palette.text.opacity(0.75))
                    .frame(width: 92, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { settings.mode },
                        set: { model.setThemeMode($0) }
                    )
                ) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }


            Divider().overlay(palette.hairline)

            Toggle(
                L("在播放条底部显示频谱"),
                isOn: Binding(
                    get: { settings.showMainSpectrum },
                    set: { model.setShowMainSpectrum($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .foregroundColor(palette.text.opacity(0.82))

            Toggle(
                L("在屏幕录制中隐藏窗口"),
                isOn: Binding(
                    get: { settings.hideFromScreenCapture },
                    set: { model.setHideFromScreenCapture($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .foregroundColor(palette.text.opacity(0.82))

            Toggle(
                L("迷你窗始终置顶"),
                isOn: Binding(
                    get: { settings.miniAlwaysOnTop },
                    set: { model.setMiniAlwaysOnTop($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .foregroundColor(palette.text.opacity(0.82))

            Toggle(
                L("关闭主窗口后继续运行"),
                isOn: Binding(
                    get: { settings.keepRunningOnClose },
                    set: { model.setKeepRunningOnClose($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .foregroundColor(palette.text.opacity(0.82))
        }
    }

    // MARK: - Pieces

    /// 展开其余 N 条 / 收起, shared by the three 文件状态 groups.
    private func expandButton(
        _ expanded: Bool,
        count: Int,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(expanded ? L("收起") : Lf("显示其余 %d 条", count)) {
            toggle()
        }
        .font(.subheadline)
        .foregroundColor(palette.accentLight)
        .buttonStyle(.plain)
    }

    private func sectionCard<Content: View>(
        icon: Image,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            icon
                .foregroundColor(palette.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(palette.text)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassPanel(cornerRadius: 10)
    }

    private func relocate(_ track: Track) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("重新定位")
        panel.message = Lf("选择《%@》的新位置", track.title)
        panel.nameFieldStringValue = track.url.lastPathComponent
        model.presentPanel(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            folderNotice = model.relocateTrack(track, to: url)
        }
    }
}

// MARK: - Settings window

/// Captures the standalone settings window for the model, and keeps the
/// themed glass background instead of an opaque white window.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    var onWindow: ((NSWindow) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            onWindow?(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
