import SoundIsleCore
import SwiftUI

@main
struct SoundIsleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(L("声屿")) {
            MainWindowView(model: appDelegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button(L("搜索")) {
                    appDelegate.model.requestSearchFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button(L("设置…")) {
                    appDelegate.model.isSettingsPresented = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            PlaybackCommands(model: appDelegate.model)
            LyricsCommands(model: appDelegate.model)
        }
    }
}

/// Mirrors the menu-bar enablement so 恢复自动匹配 and 重试匹配 are not offered
/// when they cannot do anything.
@MainActor
private struct LyricsCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu(L("歌词")) {
            Button(L("更换歌词…")) {
                model.promptImportLyrics()
            }
            .disabled(model.currentTrack == nil)

            Button(L("恢复自动匹配")) {
                model.restoreAutomaticLyrics()
            }
            .disabled(!model.hasLyricsOverride)

            Button(L("重试匹配")) {
                model.retryLyrics()
            }
            .disabled(model.currentTrack == nil || model.isResolvingLyrics)
        }
    }
}

/// Playback menu makes the shortcuts discoverable. The actual key handling
/// lives in AppModel's monitor so Space/⌘←/⌘→ never fire while typing.
@MainActor
private struct PlaybackCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu(L("播放菜单")) {
            Button(L("播放 / 暂停（空格）")) {
                model.togglePlayPause()
            }
            .disabled(model.currentTrack == nil)

            Button(L("上一首（⌘←）")) {
                model.previous()
            }
            .disabled(model.currentTrack == nil)

            Button(L("下一首（⌘→）")) {
                model.next()
            }
            .disabled(model.currentTrack == nil)
        }
    }
}
