import SoundIsleCore
import SwiftUI

@main
struct SoundIsleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(L("空山")) {
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
            PlaybackCommands(model: appDelegate.model)
        }
        // The standalone settings window. The 设置…⌘, item in the app menu is
        // provided by the system for this scene.
        Settings {
            SettingsView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
    }
}

/// Playback menu makes the shortcuts discoverable. The actual key handling
/// lives in AppModel's monitor so Space/⌘←/⌘→ never fire while typing; the
/// menu items mirror the shortcuts here and disable themselves over text
/// surfaces (search field, settings fields, rename sheets), where the menu
/// equivalent would otherwise steal the keystroke.
@MainActor
private struct PlaybackCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu(L("控制")) {
            Button(L("播放 / 暂停")) {
                model.togglePlayPause()
            }
            .keyboardShortcut(" ", modifiers: [])
            .disabled(model.currentTrack == nil || model.isSearchFocused
                      || model.isSettingsOpen || model.hasActiveSheet)

            Button(L("上一首")) {
                model.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(model.currentTrack == nil)

            Button(L("下一首")) {
                model.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(model.currentTrack == nil)
        }
    }
}
