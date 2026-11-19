# SoundIsle

[中文 README](README.md)

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white)
![Swift 5.8](https://img.shields.io/badge/Swift-5.8-orange?logo=swift)
![MIT](https://img.shields.io/badge/license-MIT-2F7D6A)
![Universal](https://img.shields.io/badge/Intel%20%2B%20Apple%20Silicon-universal-2F7D6A)

A native macOS player built for **listening to your local music while working**: fast to open, light on resources, and quiet by design. It scans folders recursively, manages playlists, lives in the menu bar, supports a mini player and floating desktop lyrics, and transcodes non-native formats in the background.

## Screenshots

### Main window: your local library
![Main window and local library](docs/screenshots/main-en.png)

Scan folders recursively, read tags, artwork and durations, and sort by title, artist, album or length. The sidebar holds the library, folders and playlists.

### Mini player: for working
![Mini player](docs/screenshots/mini-en.png)

Switching to the mini player tucks the main window away and leaves a small always-available strip that never steals focus. It shows the current lyric line and has a desktop-lyrics toggle.

### Desktop lyrics: sing along
![Desktop lyrics](docs/screenshots/overlay-en.png)

Lyrics float transparently over the desktop. Drag them, resize from the edge, or lock them to click through; hovering reveals a control bar with previous / play-pause / next. A locked overlay keeps those transports in a small pill together with unlock. Two lines show the current and next line, following the system light/dark appearance.

### Lyrics page
![Lyrics page](docs/screenshots/lyrics-en.png)

Click the cover in the player bar to switch between the track list and the full lyrics page. Clicking any synced line seeks to that line; hovering shows a clickable band and a play triangle at the trailing edge.

### Light and dark themes
| Light | Dark |
| --- | --- |
| ![Light theme](docs/screenshots/main-en.png) | ![Dark theme](docs/screenshots/main-dark-en.png) |

Six palettes — celadon, deep blue, morning, ink, berry and sea salt — follow the system appearance or pin to light or dark.

## Why SoundIsle

- **Native and light**: SwiftUI + AppKit + AVFoundation. Idle CPU is effectively zero; playback usually sits around 1–3%, with tens of MB of memory.
- **Actually background-friendly**: a menu-bar item, a mini player that never steals focus, Space/⌘←/⌘→ in the main window, and system media keys everywhere.
- **Sing along**: same-name `.lrc` first, then LRCLIB online matching, then manual import. Desktop lyrics are frosted, always-on-top, click-through when locked, and follow system light/dark. Hover for transport controls; a locked overlay still offers previous / play-pause / next and unlock in a small pill.
- **Your music files stay untouched**: scanning and playback are read-only; import, relocate and remove-from-library only update the index, never rewrite, move or delete originals.
- **Format tolerant**: ape/wma/ogg/opus/dsf and friends are decoded by your local ffmpeg and cached as ALAC in the background.
- **Pleasant to look at**: six celadon/deep-blue/morning/ink/berry/sea-salt palettes, system light/dark, custom accent and a live spectrum.
- **Bilingual**: follows the system language, with a 中文 / English override in Settings.
- **Self-updating**: checks for a new version at launch and hourly after (site manifest first, GitHub as the fallback). Choose automatic download-and-install, notify only, or off. A source without a checksum can only notify — never install silently.

## Features

### Library and playlists

- Drag in files or folders; recursive scan with tags, artwork and duration. Falls back to “Artist - Title” filenames when tags are missing.
- All Music, Recently Added, Albums, Artists, folders, user playlists; search, sort and drag to reorder.
- Albums and Artists browse as groups, with each group's tracks playable individually or as a whole.
- Rescan detects renamed files with identical size + modification date, preserving track IDs and playlists.
- Sequential / repeat all / repeat one / shuffle; remembers the queue, track and position.

### Playback, menu bar and mini player

- Menu-bar menu: play/pause, previous, next, mini mode, lyrics, quit.
- Mini player: artwork, title, current lyric, spectrum and transport; draggable, remembers its position, visible across Spaces.
- Media keys F7/F8/F9; Space/⌘←/⌘→ in the main window.
- Mini player and desktop lyrics are hidden from screen recording by default; can be changed in Settings.

### Lyrics

- Same-name `.lrc` → LRCLIB online match → manual import/override, cached locally.
- Click the player-bar artwork for a large “cover + synced lyrics” page with the current line highlighted and auto-scrolled.
- Desktop lyrics are text-only by default; hover shows a frosted background and controls. Locking makes them click-through so they never block your work.
- The control bar carries previous / play-pause / next; the locked pill keeps the same transport buttons plus unlock, so playback never needs the main window.
- Type size follows the window width; drag the window edge or the resize grip to change it. Set it before locking.
- One/two lines, opacity, text outline, and a custom LRCLIB-compatible lyrics endpoint.

### Updates

- One check about 15 seconds after launch, then hourly. No launch agent, no background service.
- Settings → Updates offers automatic download and install, notify only, or off, plus a manual Check Now (also in the app menu).
- A new version leaves a pill in the top bar until you install it or choose Skip This Version, shows one notice above the player bar, and appears in the menu-bar menu.
- Automatic mode only downloads and verifies (sha256); it never interrupts playback. The new build is swapped in when you quit, so the next launch is already updated — or click Restart to Update in the pill to apply it now.
- A source without a checksum can only notify, never install silently. Without write permission it says so instead of failing quietly.

### Appearance

- One frosted-glass material: a single light celadon gradient across the window; no stray white sidebar/player panels.
- Six palettes + custom accent; light, dark or follow system.
- Spectrum in the mini player and an optional faint spectrum under the main player bar.

## Download

- Get the latest universal build (Intel + Apple Silicon) from [Releases](https://github.com/y8gao/soundisle/releases/latest).
- Requires **macOS 12.0+**.
- The app is ad-hoc signed and not notarized. If macOS blocks the first launch, right-click → Open, or run:
  ```bash
  xattr -dr com.apple.quarantine /Applications/声屿.app
  ```

## Build from source

```bash
# 1. Run unit tests
swift test

# 2. Build build/声屿.app as a universal binary (x86_64 + arm64)
bash Scripts/build-app.sh --universal
```

Output: `build/声屿.app`. Requires Xcode Command Line Tools (Swift 5.8+); `ffmpeg` is optional and only needed for non-native formats.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `Space` | Play / pause (main window, not while typing) |
| `⌘←` / `⌘→` | Previous / next track |
| `←` / `→` | Seek back / forward 5 seconds |
| `⌘F` | Focus search |
| `⌘,` | Open Settings |

## Dependencies

- **FFmpeg**: external command-line tool, not bundled. Only `ape/wma/ogg/opus/wv/tta/dsf/dff` and similar non-native formats need it; mp3/m4a/m4r/aac/wav/aiff/flac/mp4/alac do not.
  - Recommended install: `brew install ffmpeg`.
  - Lookup order: custom path in Settings → `/usr/local/bin`, `/opt/homebrew/bin` → current `PATH`.
  - Choose the `ffmpeg` executable in Settings → Cache → FFmpeg path.

## Data directory

```
~/Library/Application Support/SoundIsle/
├── library.json       # library index (with .bak backup)
├── playlists.json     # playlists
├── settings.json      # settings and last playback position
├── covers/            # artwork cache
├── lyrics/            # online lyrics cache and manual overrides
└── transcode/         # ALAC transcode cache
```

A corrupt index falls back to `.bak`; playlists and settings live in separate files. The transcode cache can be cleared without touching original audio.

## License and credits

- This project's own source is licensed under the **MIT License**; see [`LICENSE`](LICENSE).
- **FFmpeg**: the license depends on the build (common `--enable-gpl` static builds are GPL); not distributed with the app. Install it yourself and follow its license.

## Support

SoundIsle is free and open source. If it saves you time:

- Give the project a **Star**, or share it with someone who keeps a local music library;
- Open an Issue or PR, or tell me about your use case;
- Sponsorship links (GitHub Sponsors / Afdian) will be added here once available. Donations are optional and never unlock features.

## Known limitations

- FFmpeg is not bundled; non-native formats cannot play without it, while native formats are unaffected.
- No live folder watching; use “Rescan” after changing files outside the app.
- No streaming or online music. Online lyrics use LRCLIB by default; a compatible custom endpoint can be configured.
- Media keys only reach SoundIsle while it is the system Now Playing app.
- The app is ad-hoc signed; rebuilding can reset system permission records.
- The app does not record microphone input. If macOS asks for microphone access, denying it does not affect playback.
- The lyrics overlay and mini player are hidden from screen recording/screenshots by default; this can be disabled in Settings.
