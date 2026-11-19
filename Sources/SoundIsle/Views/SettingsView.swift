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
    @State private var lyricsEndpointText = ""
    @State private var lyricsEndpointNotice: String?

    private var settings: AppSettings { model.library.settings }

    private var palette: ThemePalette {
        ThemePalette.resolve(
            preset: settings.preset,
            mode: settings.mode,
            customAccentHex: settings.customAccentHex,
            systemIsDark: colorScheme == .dark
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                missingFilesSection
                cacheSection
                lyricsSection
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
            lyricsEndpointText = settings.lyricsEndpoint ?? ""
            // Don't let the endpoint field take the initial focus just because
            // it is the first text field in the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onDisappear {
            saveLyricsEndpoint()
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.warning)
                        Spacer(minLength: 8)
                        Button(L("移除缺失条目")) {
                            folderNotice = model.removeMissingTracks()
                        }
                    }
                    ForEach(missing) { track in
                        HStack(spacing: 8) {
                            Text("\(track.title) — \(track.url.lastPathComponent)")
                                .font(.system(size: 10.5))
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
                        .font(.system(size: 10.5))
                    }
                }

                if !removed.isEmpty {
                    Divider().overlay(palette.hairline)
                    Text(Lf("已从音乐库移除 %d 首", removed.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.mutedText(0.55))
                    ForEach(removed) { track in
                        HStack(spacing: 8) {
                            Text("\(track.title) — \(track.url.lastPathComponent)")
                                .font(.system(size: 10.5))
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
                        .font(.system(size: 10.5))
                    }
                }

                if !unreadable.isEmpty {
                    Divider().overlay(palette.hairline)
                    Text(Lf("无法读取 %d 个文件", unreadable.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.warning)
                    ForEach(unreadable.prefix(3), id: \.self) { url in
                        Text(url.lastPathComponent)
                            .font(.system(size: 10.5))
                            .foregroundColor(palette.mutedText(0.45))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if unreadable.count > 3 {
                        Text(Lf("另有 %d 个…", unreadable.count - 3))
                            .font(.system(size: 10.5))
                            .foregroundColor(palette.mutedText(0.35))
                    }
                }

                if let folderNotice {
                    Text(folderNotice)
                        .font(.system(size: 10.5))
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
                .font(.system(size: 11))
                .foregroundColor(palette.mutedText(0.5))
            HStack(spacing: 10) {
                Button(L("清理缓存")) {
                    cacheNotice = model.clearTranscodeCache()
                }
                .disabled(model.transcodeCacheBytes == 0)
                Text(model.transcodeCacheSizeText)
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.mutedText(0.4))
            }
            HStack(spacing: 10) {
                Text("FFmpeg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.text.opacity(0.7))
                Text(model.ffmpegPathText)
                    .font(.system(size: 10.5))
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
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.accentLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Lyrics

    private var lyricsSection: some View {
        sectionCard(icon: Icons.settingsLyrics, title: L("歌词")) {
            Text(L("桌面歌词窗与在线歌词来源。"))
                .font(.system(size: 11))
                .foregroundColor(palette.mutedText(0.5))

            Toggle(
                L("启用在线歌词匹配"),
                isOn: Binding(
                    get: { settings.onlineLyricsEnabled },
                    set: { model.setOnlineLyricsEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .foregroundColor(palette.text.opacity(0.82))

            HStack(spacing: 10) {
                Text(L("歌词源地址"))
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.text.opacity(0.75))
                    .frame(width: 92, alignment: .leading)
                TextField(
                    "https://lrclib.net/api/get",
                    text: $lyricsEndpointText,
                    onEditingChanged: { editing in
                        if !editing { saveLyricsEndpoint() }
                    }
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit { saveLyricsEndpoint() }
                Button(L("恢复默认")) {
                    lyricsEndpointText = ""
                    lyricsEndpointNotice = nil
                    _ = model.setLyricsEndpoint(nil)
                }
                .disabled(
                    settings.lyricsEndpoint == nil
                        && lyricsEndpointText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            Text(L("兼容 LRCLIB 接口；也可填直接返回 LRC 文本的地址"))
                .font(.system(size: 10.5))
                .foregroundColor(palette.mutedText(0.45))
            if let lyricsEndpointNotice {
                Text(lyricsEndpointNotice)
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Text(L("悬停背景不透明度"))
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.text.opacity(0.75))
                    .frame(width: 120, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { settings.lyricsOpacity },
                        set: { model.setLyricsOpacity($0) }
                    ),
                    in: 0.05...0.9
                )
                Text("\(Int((settings.lyricsOpacity * 100).rounded()))%")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundColor(palette.mutedText(0.5))
                    .frame(width: 36, alignment: .trailing)
            }

            Toggle(
                L("歌词文字描边"),
                isOn: Binding(
                    get: { settings.lyricsOutline },
                    set: { model.setLyricsOutline($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .foregroundColor(palette.text.opacity(0.82))

            HStack(spacing: 10) {
                Text(L("显示行数"))
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.text.opacity(0.75))
                    .frame(width: 92, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { settings.lyricsLineMode },
                        set: { model.setLyricsLineMode($0) }
                    )
                ) {
                    Text(L("单行")).tag("one")
                    Text(L("双行")).tag("two")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        sectionCard(icon: Icons.settingsAppearance, title: L("外观")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(L("语言"))
                        .font(.system(size: 11.5))
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

                Text(L("更改语言后需要重启声屿。"))
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.mutedText(0.45))
            }

            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(palette.hairline)

                Text(L("主题皮肤"))
                    .font(.system(size: 11))
                    .foregroundColor(palette.mutedText(0.55))

                HStack(spacing: 8) {
                    ForEach(ThemePreset.allCases, id: \.self) { preset in
                        presetSwatch(preset)
                    }
                }
            }

            HStack(spacing: 10) {
                Text(L("明暗模式"))
                    .font(.system(size: 11.5))
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

            HStack(spacing: 10) {
                Text(L("自定义强调色"))
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.text.opacity(0.75))
                    .frame(width: 92, alignment: .leading)
                ColorPicker("", selection: accentColorBinding, supportsOpacity: false)
                    .labelsHidden()
                Text("Aa")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.onAccent)
                    .frame(width: 28, height: 22)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .help(L("使用强调色时的文字对比度"))
                Button(L("恢复默认")) {
                    model.setCustomAccent(hex: nil)
                }
                .disabled(settings.customAccentHex == nil)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text(L("列表行样式"))
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.text.opacity(0.75))
                    .frame(width: 92, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { settings.usesCoverRowStyle },
                        set: { model.setRowStyle(cover: $0) }
                    )
                ) {
                    Text(L("序号")).tag(false)
                    Text(L("封面")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                Spacer(minLength: 0)
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

    private func presetSwatch(_ preset: ThemePreset) -> some View {
        let selected = settings.preset == preset
        let preview = ThemePalette(
            preset: preset,
            tokens: ThemeCatalog.tokens(for: preset, isDark: palette.isDark)
        )
        return Button {
            model.setThemePreset(preset)
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [preview.backgroundMiddle, preview.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                selected ? palette.accent : palette.hairline,
                                lineWidth: selected ? 2 : 1
                            )
                    )
                Text(preset.displayName)
                    .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(palette.text.opacity(selected ? 1 : 0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.displayName)
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.customAccentHex ?? palette.tokens.accentHex) },
            set: { model.setCustomAccent(hex: $0.hexString) }
        )
    }

    // MARK: - Pieces

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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.text)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassPanel(cornerRadius: 10)
    }

    /// Saves on submit/focus loss. An invalid non-empty value keeps the text
    /// in place so it can be corrected, shows a notice, and is not persisted.
    private func saveLyricsEndpoint() {
        let trimmed = lyricsEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = model.setLyricsEndpoint(trimmed.isEmpty ? nil : trimmed) {
            lyricsEndpointNotice = message
        } else {
            lyricsEndpointNotice = nil
            lyricsEndpointText = settings.lyricsEndpoint ?? ""
        }
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
