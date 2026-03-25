# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

HTCommander-X is a ham radio controller for Bluetooth-enabled handhelds (UV-Pro, UV-50Pro, GA-5WB, VR-N75, VR-N76, VR-N7500, VR-N7600, RT-660). Built with Flutter, targeting Linux desktop, Windows, and Android.

Two git remotes: `origin` (Ylianst/HTCommander upstream), `fork` (dikei100/HTCommander-X). Push to `fork` with `--tags` to trigger releases.

Uses "Signal Protocol" design system (dark base `#0c0e17`, cyan primary `#3cd7ff`, glassmorphism, Inter font). Stitch project "HTCommander-X: New UI" is the design reference. ~200 source files, ~55K LOC, 199 tests.

## Prerequisites

**Flutter SDK** (stable, v3.41.5+) at `~/flutter`. Add to PATH: `export PATH="$HOME/flutter/bin:$PATH"`. Linux: `sudo pacman -S ninja gcc`. Android: Java 17 + Android SDK.

## Build Commands

```bash
cd htcommander_flutter
~/flutter/bin/flutter pub get
~/flutter/bin/flutter analyze        # must pass with zero errors (warnings OK for unused protocol fields)
~/flutter/bin/flutter test           # 199 tests
~/flutter/bin/flutter test test/handlers/  # run a specific test directory
~/flutter/bin/flutter test test/radio/gps_test.dart  # run a single test file
~/flutter/bin/flutter analyze lib/handlers/aprs_handler.dart  # analyze a single file
~/flutter/bin/flutter run -d linux
~/flutter/bin/flutter build linux --release  # → build/linux/x64/release/bundle/htcommander-x
~/flutter/bin/flutter build apk --release    # → build/app/outputs/flutter-apk/app-release.apk
```

Note: Flutter SDK is at `~/flutter/bin/flutter` (not on PATH by default).

## Architecture

**Startup**: `WidgetsFlutterBinding.ensureInitialized()` → `SharedPrefsSettingsStore.create()` → `DataBroker.initialize(store)` → `initializeDataHandlers()` → `initializeHandlerPaths(appDataPath)` → `runApp()`.

**App shell** (`app.dart`): Holds `Radio?` and `PlatformServices?`. No top toolbar — sidebar contains branding, frequency display, callsign, and connect/disconnect. Screens in `IndexedStack` (preserves state across tab switches). Sidebar has 8 nav items (Communication, Contacts, Packets, Terminal, BBS, Mail, Torrent, APRS); Logbook/Map/Debug remain in IndexedStack but not in sidebar nav. `_sidebarToScreen` maps sidebar indices to screen indices. `_directScreenIndex` overrides sidebar mapping for non-sidebar screens. Settings renders as a standalone widget (not overlaid). MCP events: `McpConnectRadio`/`McpDisconnectRadio` for remote radio control, `McpNavigateTo` for screen navigation (publishes `CurrentScreen` on device 1).

**Key directories**:
- `core/` — DataBroker pub/sub, DataBrokerClient, SharedPreferences SettingsStore
- `radio/` — GAIA state machine (76 basic + 6 extended commands), SBC codec, morse/DTMF
- `radio/modem/` — Software packet modem: DSP, AFSK 1200, 9600 G3RUH, PSK, HDLC (v1 + v2 with error correction), FX.25 (Reed-Solomon FEC), MultiModem, AudioBuffer, AudioConfig
- `radio/sstv/` — SSTV encoder/decoder (20+ modes: Robot, Scottie, Martin, Wraase, PD, HF Fax), SstvMonitor, FFT, DSP
- `radio/ax25/` — AX.25 packet/address/session, raw frame assembler (Ax25Pad/Pad2), data link state machine (Ax25Link)
- `radio/aprs/` — APRS packet parser, position, message, weather
- `radio/gps/` — NMEA 0183 parser (GGA, RMC, GSA, GSV, VTG, GLL, ZDA), GPS data model
- `handlers/` — 20+ DataBroker handlers (FrameDeduplicator, PacketStore, AprsHandler, LogStore, LogFileHandler, MailStore, VoiceHandler, AudioClipHandler, TorrentHandler, BbsHandler, WinlinkClient, WinlinkGatewayRelay, YappTransfer, RepeaterBookClient, ImportUtils, AdifExport, GpsSerialHandler, AirplaneHandler, VirtualAudioBridge, FileDownloader, server stubs on mobile). `winlink_utils.dart` has LZHUF compression, CRC16, checksum, and auth security for B2F protocol.
- `handlers/adventurer/` — Text adventure game (Easter egg)
- `dialogs/` — 43 dialog widgets (APRS, radio config, channel editor, SSTV send, spectrogram, RepeaterBook, mail, beacon/ident settings, station selector, etc.)
- `servers/` — MCP (41 tools on desktop, including `navigate_to`/`get_current_screen`), Web (HTTP/HTTPS + WebSocket audio), Rigctld, AGWPE, SMTP, IMAP, CAT Serial (TS-2000), TLS Certificate Manager. All real on desktop, stubs on mobile.
- `platform/` — Abstract interfaces: `PlatformServices` (factory, `bluetooth_service.dart`), `AudioOutput`/`MicCapture` (`audio_service.dart`), `SpeechService`, `WhisperEngine`. `PlatformServices.instance` static provides global access.
- `platform/linux/` — dart:ffi RFCOMM Bluetooth (Isolate), audio I/O (paplay/parecord), LinuxSpeechService (espeak-ng), LinuxWhisperEngine (whisper-cli subprocess), LinuxVirtualAudioProvider (PulseAudio virtual devices)
- `platform/windows/` — dart:ffi Winsock2 RFCOMM Bluetooth (Isolate), waveOut/waveIn audio, PowerShell TTS (System.Speech), whisper-cli STT
- `platform/android/` — MethodChannel/EventChannel bridge to Kotlin native code for Bluetooth RFCOMM, AudioTrack/AudioRecord, Android TTS. GAIA frame decoding in Dart (accumulator + `GaiaProtocol.decode()`). Whisper STT stubbed (no-op).
- `screens/` — 12 screens wired to DataBroker. Communication screen loads current state on init. Screens use 42px inline header bars (not 46px).
- `widgets/` — VfoDisplay, PttButton, SignalBars, RadioStatusCard, GlassCard, SidebarNav, StatusStrip

### GAIA Protocol

```
[0xFF] [0x01] [flags] [body_length] [group_hi] [group_lo] [cmd_hi] [cmd_lo] [body...]
```
- `body_length` = cmd body only (max 255), total frame = body_length + 8
- Reply bit: `cmd_hi | 0x80`. Frequencies stored in Hz.
- SBC codec: 32kHz, 16 blocks, mono, loudness allocation, 8 subbands, bitpool 18
- Audio framing: `0x7E` start/end, `0x7D` escape (XOR `0x20`). Separate RFCOMM channel (GenericAudio UUID `00001203`).

### DataBroker Pattern

`DataBroker.dispatch(deviceId, name, data)` / `broker.subscribe(deviceId, name, callback)`. Device 0 = settings (auto-persisted), device 1 = app events, device 100+ = radios. Screens subscribe in `initState()`, call `setState()` in callbacks. Handlers self-initialize in constructors.

### Linux Bluetooth (dart:ffi)

`native_methods.dart` binds libc: `socket()`, `connect()`, `close()`, `read()`, `write()`, `fcntl()`, `poll()`, `sigprocmask()`, `sigemptyset()`, `sigaddset()`. Poll constants: POLLIN=1, POLLOUT=4, POLLERR=8, POLLHUP=16, POLLNVAL=32.

Connection flow: `bluetoothctl connect` (ACL, 3s wait) → `sdptool browse` (SDP) → RFCOMM socket per channel → GAIA GET_DEV_ID verification → async read loop. Channel probing: 1-30.

**Critical**: Read loop MUST be `async` with `await Future.delayed()`, NOT `sleep()`. Dart isolates are single-threaded — `sleep()` blocks the event loop, preventing write command delivery. Writes queued in `List<Uint8List>`, drained by read loop between reads. SIGPROF/SIGALRM blocked around each syscall batch and restored before yielding.

**Disconnect**: Sends `{'cmd': 'disconnect'}` then delays 1s before killing isolate for clean fd close. Without this, fd leaks and reconnection fails (ECONNREFUSED on all channels).

**Connection loss**: When `Radio._onReceivedData` gets error+null, calls `disconnect()` to transition state. Read loop logs exit reason before exiting.

### Windows Bluetooth (dart:ffi)

`windows_native_methods.dart` binds ws2_32.dll (Winsock2 RFCOMM) and winmm.dll (waveOut/waveIn). Same Isolate pattern as Linux but using `socket(AF_BTH=32, SOCK_STREAM, BTHPROTO_RFCOMM=3)`, `ioctlsocket(FIONBIO)` for non-blocking, `WSAPoll` for readability, `send()`/`recv()`. No SIGPROF blocking needed. No `bluetoothctl` ACL step (Windows handles automatically). Error code `WSAEWOULDBLOCK=10035` instead of `EAGAIN`. Device scanning via PowerShell `Get-PnpDevice -Class Bluetooth`.

### Android Bluetooth (MethodChannel)

Kotlin native code in `android/app/src/main/kotlin/.../` bridges Dart to Android Bluetooth Classic APIs via MethodChannel/EventChannel. Five Kotlin services registered in `MainActivity.configureFlutterEngine()`:

- **BluetoothService** (`com.htcommander/bluetooth`) — RFCOMM command channel. Tries SPP UUID `00001101` first, falls back to reflection-based channel probing 1-30. Read loop on `Dispatchers.IO` coroutine, events sent to Dart via EventChannel. 30s connection timeout. Double-connect guard (disconnects existing socket before new connection).
- **AudioTransportService** (`com.htcommander/audio_transport`) — Audio RFCOMM channel (GenericAudio UUID `00001203`). Same pattern as BluetoothService. 2s delay before connecting to let command channel stabilize.
- **AudioService** (`com.htcommander/audio`) — AudioTrack (32kHz mono, `USAGE_VOICE_COMMUNICATION`) for playback, AudioRecord (44100Hz mono, 2x min buffer) for mic capture. `writePcm()` runs on IO dispatcher to avoid ANR. Mic data sent to Dart via EventChannel, resampled 44100→32000 in Dart.
- **SpeechService** (`com.htcommander/speech`) — Android `TextToSpeech` API. `synthesizeToWav()` uses `Handler(Looper.getMainLooper())` to marshal TTS thread callbacks back to main thread for MethodChannel.Result.

**GAIA decoding on Android**: Raw socket bytes are sent from Kotlin to Dart. `AndroidRadioBluetooth` has an accumulator buffer and decodes GAIA frames in Dart using `GaiaProtocol.decode()`, matching the Linux isolate's frame reassembly logic. GAIA encoding also stays in Dart (`GaiaProtocol.encode()` in `enqueueWrite()`).

**Disconnect**: Delays cleanup by 1s (matching Linux pattern) to let Kotlin close the socket cleanly.

**Permissions**: `MainActivity.onCreate()` requests runtime permissions — `BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN` (API 31+) or `ACCESS_FINE_LOCATION` (API < 31), plus `RECORD_AUDIO`.

### Audio Pipeline (Fully Wired)

**RX**: BT audio RFCOMM → 0x7E deframe → SBC decode → PCM → platform AudioOutput → speaker. **TX**: PTT press → platform MicCapture → resample to 32kHz → `TransmitVoicePCM` event → `RadioAudioManager` → SBC encode → 0x7E frame → BT audio RFCOMM. PTT release → `CancelVoiceTransmit` event → end frame sent.

**Lifecycle**: `Radio` creates `RadioAudioManager` in constructor, subscribes to `SetAudio` event. Audio auto-starts 3s after radio connects via `_setAudioEnabled(true)`. `AudioOutput`/`MicCapture` created via `PlatformServices.instance` factory by `CommunicationScreen` on `AudioState(true)` / PTT press respectively. Linux uses paplay/parecord subprocesses; Windows uses waveOut/waveIn via dart:ffi; Android uses AudioTrack/AudioRecord via MethodChannel.

### Dialog Pattern

Dialogs in `lib/dialogs/` follow Signal Protocol design system. Key conventions:
- `Dialog` with `surfaceContainerHigh` background, `BorderRadius.circular(8)`
- 9px uppercase bold headers (`letterSpacing: 1, fontWeight: w700`)
- 10-11px body text, `outlineVariant` borders, compact `InputDecoration`
- Return results via `Navigator.pop(context, result)`, null on cancel
- Stateless for read-only display, StatefulWidget for forms with controllers

### Handler Initialization

`app_init.dart` has two phases: `initializeDataHandlers()` registers all handlers/servers with DataBroker (desktop gets real servers, mobile gets stubs), then `initializeHandlerPaths(appDataPath)` calls `initialize()` on handlers needing file persistence (PacketStore, VoiceHandler, BbsHandler, TorrentHandler, WinlinkClient, LogFileHandler). App data path: Linux `~/.local/share/HTCommander`, Windows `%APPDATA%\HTCommander`, Android `getApplicationDocumentsDirectory()`.

Platform-specific services injected in `app_init.dart`: Linux gets `LinuxSpeechService` + `LinuxWhisperEngine`, Windows gets `WindowsSpeechService` + `WindowsWhisperEngine`, Android gets `AndroidSpeechService` (Whisper STT not yet available). Platform selection in `app.dart` `_initPlatformServices()` sets `PlatformServices.instance`. Whisper STT requires `whisper-cli` (Linux) or `whisper-cli.exe` (Windows) on PATH and `ggml-{model}.bin` in app data dir.

### Security

All servers default to loopback. MCP requires Bearer token when `ServerBindAll` enabled. All subprocess calls use `Process.run`/`Process.start` with argument lists (no shell injection). Path traversal validated via prefix check. Protocol bounds checked on all constructors. Files chmod 600 on Linux. CSP on web pages. Constant-time auth comparisons throughout.

### Conventions

- Import `radio/radio.dart` with `as ht` prefix (avoids Flutter `Radio` widget clash)
- Dart `int` is 64-bit — use `& 0xFFFFFFFF` for unsigned 32-bit
- Settings: int 0/1 for booleans: `DataBroker.getValue<int>(0, key, 0) == 1`
- All `Process.run`/`Process.start` calls must be guarded with platform checks (e.g., `if (Platform.isLinux)`) to prevent crashes on Android

## Repository Structure

- `htcommander_flutter/` — Flutter app (active development)
- `htcommander_flutter/android/` — Android native Kotlin code (BluetoothService, AudioTransportService, AudioService, SpeechService)
- `docs/` — feature & protocol documentation
- `web/` — embedded web interface (desktop Web Bluetooth + mobile SPA)
- `assets/` — shared icons
- `.github/workflows/release.yml` — CI/CD (version tags trigger Linux, Windows, Android builds)

## Related Projects

- [khusmann/benlink](https://github.com/khusmann/benlink) — Python GAIA protocol reference
- [SarahRoseLives/flutter_benlink](https://github.com/SarahRoseLives/flutter_benlink) — Dart GAIA reference, VR-N76 quirks
