# audiloc

*[Читать на русском](README.md)*

Cross-platform (Linux/Windows/Android) music player with automatic P2P
library synchronization (tracks, tags, favorites, playlists) between
devices on the local network — no cloud, no central server.

Status: **1.0.0**. Discovery, confirmed pairing, metadata sync, audio
file and cover transfer, accounts/profiles, "Share" a track/album
between devices — all verified live on real devices (Linux + Android).
Deduplication is still just a rough heuristic (not `chromaprint`).
Details and known limitations: [`docs/roadmap.md`](docs/roadmap.md).

## Features

- Library: import a folder → auto-extract tags and covers → the file's
  sha256 as the track id (idempotent re-import). Long-press (or
  right-click on desktop) a track for a menu: edit
  (title/artist/album/genre/cover), add to playlist, share, delete.
- Player: bottom mini-player + full-screen (swipe up/tap), queue,
  favorites — offline-first, no waiting on the network. On Android —
  playback notification, lock-screen and headset/Bluetooth button
  control (`audio_service`,
  `lib/services/playback/audiloc_audio_handler.dart`). Tabs can also be
  switched with a swipe, not just by tapping the bottom bar.
- Playlists: creation, multi-select when adding tracks (with search),
  delete/rename, fractional-index ordering (docs/data-model.md), cover
  art — either from one of its own tracks or an image file.
- Profiles: several people can share one device — each with their own
  library and their own list of paired devices (a separate local
  database per profile); deleting a profile is irreversible, confirmed
  by typing its name. One person, two of their own devices — "Wait for
  pairing" turns the second device into a copy of the first
  (docs/adr/0013, docs/adr/0020).
- Devices: list of paired nodes with online/offline status, automatic
  sync with already-paired devices as they're discovered on the LAN, a
  "synced N changes" badge, and a manual refresh button to force-restart
  discovery (useful after switching Wi-Fi networks or waking from
  sleep). Pairing requires explicit confirmation on both sides ("Found
  nearby" → "Add" → an "Allow/Decline" dialog on the other device) and
  **only ever between the same profile** — pairing across different
  profiles is forbidden (docs/adr/0017); a device can be unpaired at any
  time.
- "Share" — send a specific track or album to any nearby visible
  device, regardless of profile and without pairing; the receiving side
  sees a preview (title, cover) before accepting (docs/adr/0017).
- File transfer — built in, no third-party software: audiloc's own
  HTTP server and client fetch missing tracks from online peers on the
  local network, resuming after an interruption (docs/adr/0010).
- "About" (the "ⓘ" icon on the Devices tab) — author, version, license,
  and a short guide to the less obvious features, right inside the app
  (docs/adr/0024).

## Architecture

Details — [`docs/architecture.md`](docs/architecture.md) (with
diagrams) and [`docs/data-model.md`](docs/data-model.md) (database
tables). Rationale for key decisions and package choices —
[`docs/adr/`](docs/adr/).

In short: Flutter (Riverpod, go_router) + `media_kit` for playback +
`sqlite_crdt`/`crdt_sync` (cachapa) for the CRDT metadata layer and P2P
sync + `bonsoir` for mDNS discovery + a custom HTTP server/client
(`dart:io`/`dio`) for file transfer — fully self-contained, no
third-party software (docs/adr/0010).

## Setup and running

### Requirements

- Flutter SDK (stable), Dart is bundled with it.
- **Linux desktop**: system `clang`, `cmake`, `ninja`, `pkg-config`,
  `gtk+-3.0`, `mpv` (for `media_kit`). On Arch/CachyOS:
  `sudo pacman -S clang cmake ninja pkgconf gtk3 mpv`; on
  Debian/Ubuntu — `sudo apt install clang cmake ninja-build
  pkg-config libgtk-3-dev libmpv-dev`.
- **Android**: Android SDK/NDK — full instructions:
  [`docs/building-android.md`](docs/building-android.md).
- **Windows**: Visual Studio with the C++ workload — full instructions:
  [`docs/building-windows.md`](docs/building-windows.md) (building is
  only possible on Windows itself, cross-compiling from Linux isn't
  available).

No third-party software needs to be installed — file transfer is built
right into the app.

### Commands

```bash
flutter pub get

# Static analysis
flutter analyze

# Tests: all unit tests at once
flutter test test/unit/

# Tests: each widget test individually — see docs/testing-notes.md
# (this Flutter build has a known shutdown hang after real sqflite
# writes when running `flutter test` with no arguments)
flutter test test/widget/mini_player_test.dart
flutter test test/widget/track_tile_test.dart
flutter test test/widget/library_screen_test.dart

# Run on Linux desktop
flutter run -d linux

# Build the Linux binary
flutter build linux --release
```

Building for Android and Windows needs its own platform setup
(SDK/NDK, Visual Studio) — full step-by-step instructions:
[`docs/building-android.md`](docs/building-android.md),
[`docs/building-windows.md`](docs/building-windows.md).

## Tests

- `test/unit/data/` — repositories (`TracksRepository`,
  `FavoritesRepository`, `PlaylistsRepository`, `ProfilesStore`) on
  `SqliteCrdt.openInMemory()`: CRUD, soft-delete/restore, fractional
  playlist ordering.
- `test/unit/services/` — dedup heuristic, library import (real sha256
  hashing + a fake `TagReader`), a **real** `crdt_sync` P2P round-trip
  between two in-memory nodes over an actual localhost socket, a
  **real** HTTP round-trip file transfer between
  `FileTransferServer`/`FileTransferClient` (including resuming an
  interrupted file), pairing (`PairingService`) and "Share"
  (`ShareService`) — also real HTTP round-trips, not mocks.
- `test/widget/` — mini-player, track tile (offline-first favorite
  toggle), library screen (empty state / list).

All tests pass; for why they're worth running per directory/file
rather than one bare `flutter test` in this specific environment, see
[`docs/testing-notes.md`](docs/testing-notes.md).

## Repository structure

```
lib/            — application code (core/ data/ services/ features/)
test/           — unit and widget tests
docs/           — architecture, data model, ADRs, roadmap
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md) — open source, free for any
non-commercial purpose: use it, fork it, change it, study it.
Commercial use requires the author's separate permission.

If you fork it — please make real changes/improvements rather than
just re-publishing it under your own name: change the project's name
and identity, and keep the credit to the original author and source.
