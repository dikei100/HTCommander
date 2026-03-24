# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

HTCommander is a ham radio controller for Bluetooth-enabled handhelds (UV-Pro, UV-50Pro, GA-5WB, VR-N75, VR-N76, VR-N7500, VR-N7600, RT-660). **Active development is in the Flutter rewrite** (`htcommander_flutter/`). The C#/Avalonia app in the root is the stable reference implementation.

Two git remotes: `origin` (Ylianst/HTCommander upstream), `fork` (dikei100/HTCommander-X). Push to `fork` with `--tags` to trigger releases.

## C#/Avalonia App (reference, stable)

### Build

**.NET SDK 9.0** required. `dotnet build HTCommander.sln` / `dotnet run --project HTCommander.Desktop/HTCommander.Desktop.csproj`. No test projects. Versioning in `HTCommander.Desktop.csproj` `<Version>` property — must match git tag.

### Architecture

```
HTCommander.Desktop (Avalonia UI) ──┐
                                     ├──> HTCommander.Core (all business logic)
HTCommander.Platform.Linux ──────────┤
HTCommander.Platform.Windows ────────┘
```

**Core** (net9.0): Radio.cs (GAIA protocol), DataBroker pub/sub, AX.25/APRS, SBC codec, SSTV, VoiceHandler, RadioAudioManager, servers (MCP/Web/Rigctld/AGWPE/SMTP/IMAP), AudioClipHandler, RepeaterBookClient, AdifExport.

**Key patterns**: DataBroker event flow (device 0=settings, 1=app events, 100+=radios), data handler self-registration, radio connection lifecycle (transport→OnConnected→GAIA init→DataBroker dispatch), IRadioHost interface for circular dependency breaking.

**Linux Bluetooth**: Direct native RFCOMM sockets. `poll()`/`SO_RCVTIMEO` broken on RFCOMM — use `O_NONBLOCK` + `Thread.Sleep(50)`. `OnConnected` must fire on background thread. RFCOMM channels vary by model (VR-N76: ch 1 or 4 for commands, ch 2 for audio). Block SIGPROF around syscalls.

### GAIA Protocol

```
[0xFF] [0x01] [flags] [body_length] [group_hi] [group_lo] [cmd_hi] [cmd_lo] [body...]
```
- `body_length` = cmd body only (max 255), total frame = body_length + 8
- Reply bit: `cmd_hi | 0x80`. Frequencies stored in Hz.
- SBC codec: 32kHz, 16 blocks, mono, loudness allocation, 8 subbands, bitpool 18
- Audio framing: `0x7E` start/end, `0x7D` escape (XOR `0x20`). Separate RFCOMM channel (GenericAudio UUID `00001203`).

### Code Conventions

- net9.0, nullable disabled, implicit usings disabled, unsafe blocks enabled
- Radio state dispatched as **string** (e.g. `"Connected"`)
- Settings: int 0/1 for booleans, `DataBroker.GetValue<int>(0, key, 0) == 1`
- Avalonia: `ComboBox` has no `.Text` — use `AutoCompleteBox`. Dialogs use `Confirmed` bool pattern.
- SSTV uses SkiaSharp, not System.Drawing

### Security Summary

All servers default to loopback. MCP requires Bearer token when `ServerBindAll` enabled. All subprocess calls use `ArgumentList` (no injection). Path traversal validated via `GetFullPath()` prefix check. Protocol bounds checked on all constructors. Error responses never expose `ex.Message`. Files chmod 600 on Linux. CSP on web pages. Constant-time auth comparisons throughout.

---

## HTCommander-X Flutter Rewrite (`htcommander_flutter/`)

Full Dart/Flutter rewrite targeting Linux desktop, Windows, and Android. Uses "Signal Protocol" design system (dark base `#080a12`, cyan primary `#3cd7ff`, glassmorphism, Inter font). ~102 source files, ~26K LOC, 98 tests.

### Prerequisites

**Flutter SDK** (stable, v3.41.5+) at `~/flutter`. Add to PATH: `export PATH="$HOME/flutter/bin:$PATH"`. Linux: `sudo pacman -S ninja gcc`.

### Build Commands

```bash
cd htcommander_flutter
flutter pub get
flutter analyze        # must pass with zero issues
flutter test           # 98 tests
flutter run -d linux
flutter build linux --release  # → build/linux/x64/release/bundle/htcommander-x
flutter build apk
```

### Architecture

**Startup**: `WidgetsFlutterBinding.ensureInitialized()` → `SharedPrefsSettingsStore.create()` → `DataBroker.initialize(store)` → `initializeDataHandlers()` → `runApp()`.

**App shell** (`app.dart`): Holds `Radio?` and `PlatformServices?`. Connect button uses last saved MAC directly (dialog only when no MAC saved). Looks up BT friendly name via `bluetoothctl info`. Screens in `IndexedStack` (preserves state across tab switches). MCP `McpConnectRadio`/`McpDisconnectRadio` events wired for remote control.

**Key directories**:
- `core/` — DataBroker pub/sub, DataBrokerClient, SharedPreferences SettingsStore
- `radio/` — GAIA state machine, SBC codec, SSTV, AX.25, APRS, software modem, morse/DTMF
- `handlers/` — 14 DataBroker handlers (FrameDeduplicator, PacketStore, AprsHandler, LogStore, MailStore, VoiceHandler, AudioClipHandler, TorrentHandler, BbsHandler, WinlinkClient, YappTransfer + server stubs on mobile)
- `servers/` — MCP (real on desktop, 16 tools), Web, Rigctld, AGWPE, SMTP, IMAP
- `platform/linux/` — dart:ffi RFCOMM Bluetooth (Isolate), audio I/O (paplay/parecord)
- `screens/` — 12 screens wired to DataBroker. Communication screen loads current state on init.
- `widgets/` — VfoDisplay, PttButton, SignalBars, RadioStatusCard, GlassCard, SidebarNav

### DataBroker Pattern (Same as C#)

`DataBroker.dispatch(deviceId, name, data)` / `broker.subscribe(deviceId, name, callback)`. Device 0 = settings (auto-persisted), device 1 = app events, device 100+ = radios. Screens subscribe in `initState()`, call `setState()` in callbacks. Handlers self-initialize in constructors.

### Linux Bluetooth (dart:ffi)

`native_methods.dart` binds libc: `socket()`, `connect()`, `close()`, `read()`, `write()`, `fcntl()`, `poll()`, `sigprocmask()`, `sigemptyset()`, `sigaddset()`. Poll constants: POLLIN=1, POLLOUT=4, POLLERR=8, POLLHUP=16, POLLNVAL=32.

Connection flow: `bluetoothctl connect` (ACL, 3s wait) → `sdptool browse` (SDP) → RFCOMM socket per channel → GAIA GET_DEV_ID verification → async read loop. Channel probing: 1-30.

**Critical**: Read loop MUST be `async` with `await Future.delayed()`, NOT `sleep()`. Dart isolates are single-threaded — `sleep()` blocks the event loop, preventing write command delivery. Writes queued in `List<Uint8List>`, drained by read loop between reads. SIGPROF/SIGALRM blocked around each syscall batch and restored before yielding.

**Disconnect**: Sends `{'cmd': 'disconnect'}` then delays 1s before killing isolate for clean fd close. Without this, fd leaks and reconnection fails (ECONNREFUSED on all channels).

**Connection loss**: When `Radio._onReceivedData` gets error+null, calls `disconnect()` to transition state. Read loop logs exit reason before exiting.

### Audio Pipeline

**RX**: BT audio RFCOMM → 0x7E deframe → SBC decode → PCM → `paplay` (mono→stereo). **TX**: `parecord` (48kHz) → resample to 32kHz → SBC encode → 0x7E frame → BT audio RFCOMM.

### Conventions

- Import `radio/radio.dart` with `as ht` prefix (avoids Flutter `Radio` widget clash)
- Dart `int` is 64-bit — use `& 0xFFFFFFFF` for unsigned 32-bit
- C# `byte[]` → `Uint8List`, `short[]` → `Int16List`
- C# `SynchronizationContext.Post()` → `Future.microtask()`
- C# `volatile`/`lock` → Dart main isolate is single-threaded; use `Completer` for async
- C# `Thread` → Dart `Isolate` (RFCOMM) or `async`/`await`
- Settings: int 0/1 for booleans: `DataBroker.getValue<int>(0, key, 0) == 1`

## Repository Structure

- `HTCommander.Core/`, `HTCommander.Platform.Linux/`, `HTCommander.Platform.Windows/`, `HTCommander.Desktop/` — C#/Avalonia app
- `htcommander_flutter/` — Flutter rewrite (active development)
- `docs/` — architecture docs
- `packaging/linux/` — AppImage/deb build scripts
- `web/` — embedded web interface (desktop Web Bluetooth + mobile SPA)
- `assets/` — shared icons
- `.github/workflows/release.yml` — CI/CD (version tags trigger builds)

## Related Projects

- [khusmann/benlink](https://github.com/khusmann/benlink) — Python GAIA protocol reference
- [SarahRoseLives/flutter_benlink](https://github.com/SarahRoseLives/flutter_benlink) — Dart GAIA reference, VR-N76 quirks
