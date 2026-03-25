import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

// --- Winsock2 Constants ---

/// AF_BTH: Bluetooth socket address family.
const int afBth = 32;

/// SOCK_STREAM socket type.
const int sockStream = 1;

/// BTHPROTO_RFCOMM protocol.
const int bthprotoRfcomm = 3;

/// FIONBIO: ioctl command for non-blocking mode.
const int fionbio = 0x8004667E;

/// WSAEWOULDBLOCK: non-blocking operation would block.
const int wsaeWouldBlock = 10035;

/// WSAECONNREFUSED: connection refused.
const int wsaeConnRefused = 10061;

/// WSAEINPROGRESS: blocking operation in progress.
const int wsaeInProgress = 10036;

/// WSAEALREADY: connect already in progress on non-blocking socket.
const int wsaeAlready = 10037;

/// INVALID_SOCKET sentinel (0xFFFFFFFFFFFFFFFF on 64-bit).
const int invalidSocket = -1;

/// SOCKET_ERROR return value.
const int socketError = -1;

/// WSAPoll event: data available for reading.
const int pollIn = 0x0100;

/// WSAPoll event: ready for writing.
const int pollOut = 0x0010;

/// WSAPoll event: error condition (output only).
const int pollErr = 0x0001;

/// WSAPoll event: hang up (output only).
const int pollHup = 0x0002;

/// Size of SOCKADDR_BTH structure (30 bytes).
const int sockaddrBthSize = 30;

/// Size of WSADATA structure on 64-bit Windows (408 bytes).
const int wsaDataSize = 408;

// --- waveOut/waveIn Constants ---

/// WAVE_MAPPER: use default audio device.
const int waveMapper = -1;

/// CALLBACK_NULL: no callback mechanism.
const int callbackNull = 0;

/// WAVE_FORMAT_PCM: PCM audio format tag.
const int waveFormatPcm = 1;

/// WHDR_DONE: buffer has been played/recorded.
const int whdrDone = 0x01;

/// WHDR_PREPARED: buffer has been prepared.
const int whdrPrepared = 0x02;

/// MMSYSERR_NOERROR: success.
const int mmsyserrNoError = 0;

/// CALLBACK_EVENT: callback is an event handle.
const int callbackEvent = 0x00050000;

/// Size of WAVEFORMATEX structure (18 bytes).
const int waveFormatExSize = 18;

/// Size of WAVEHDR structure on 64-bit (48 bytes, accounting for pointer alignment).
const int waveHdrSize = 48;

// --- Winsock2 Structs ---

/// WSAPOLLFD structure for WSAPoll().
final class WsaPollFd extends ffi.Struct {
  @ffi.IntPtr()
  external int fd;

  @ffi.Int16()
  external int events;

  @ffi.Int16()
  external int revents;
}

// --- Winsock2 Native Function Typedefs ---

typedef _WSAStartupNative = ffi.Int32 Function(
    ffi.Uint16 wVersionRequested, ffi.Pointer<ffi.Uint8> lpWSAData);
typedef _WSAStartupDart = int Function(
    int wVersionRequested, ffi.Pointer<ffi.Uint8> lpWSAData);

typedef _WSACleanupNative = ffi.Int32 Function();
typedef _WSACleanupDart = int Function();

typedef _SocketNative = ffi.IntPtr Function(
    ffi.Int32 af, ffi.Int32 type, ffi.Int32 protocol);
typedef _SocketDart = int Function(int af, int type, int protocol);

typedef _ConnectNative = ffi.Int32 Function(
    ffi.IntPtr s, ffi.Pointer<ffi.Void> name, ffi.Int32 namelen);
typedef _ConnectDart = int Function(
    int s, ffi.Pointer<ffi.Void> name, int namelen);

typedef _SendNative = ffi.Int32 Function(
    ffi.IntPtr s, ffi.Pointer<ffi.Uint8> buf, ffi.Int32 len, ffi.Int32 flags);
typedef _SendDart = int Function(
    int s, ffi.Pointer<ffi.Uint8> buf, int len, int flags);

typedef _RecvNative = ffi.Int32 Function(
    ffi.IntPtr s, ffi.Pointer<ffi.Uint8> buf, ffi.Int32 len, ffi.Int32 flags);
typedef _RecvDart = int Function(
    int s, ffi.Pointer<ffi.Uint8> buf, int len, int flags);

typedef _ClosesocketNative = ffi.Int32 Function(ffi.IntPtr s);
typedef _ClosesocketDart = int Function(int s);

typedef _WSAGetLastErrorNative = ffi.Int32 Function();
typedef _WSAGetLastErrorDart = int Function();

typedef _IoctlsocketNative = ffi.Int32 Function(
    ffi.IntPtr s, ffi.Int32 cmd, ffi.Pointer<ffi.Uint32> argp);
typedef _IoctlsocketDart = int Function(
    int s, int cmd, ffi.Pointer<ffi.Uint32> argp);

typedef _WSAPollNative = ffi.Int32 Function(
    ffi.Pointer<WsaPollFd> fdArray, ffi.Uint32 fds, ffi.Int32 timeout);
typedef _WSAPollDart = int Function(
    ffi.Pointer<WsaPollFd> fdArray, int fds, int timeout);

// --- waveOut Native Function Typedefs ---

typedef _WaveOutOpenNative = ffi.Uint32 Function(
    ffi.Pointer<ffi.IntPtr> phwo,
    ffi.Uint32 uDeviceID,
    ffi.Pointer<ffi.Uint8> pwfx,
    ffi.IntPtr dwCallback,
    ffi.IntPtr dwInstance,
    ffi.Uint32 fdwOpen);
typedef _WaveOutOpenDart = int Function(
    ffi.Pointer<ffi.IntPtr> phwo,
    int uDeviceID,
    ffi.Pointer<ffi.Uint8> pwfx,
    int dwCallback,
    int dwInstance,
    int fdwOpen);

typedef _WaveOutCloseNative = ffi.Uint32 Function(ffi.IntPtr hwo);
typedef _WaveOutCloseDart = int Function(int hwo);

typedef _WaveOutPrepareHeaderNative = ffi.Uint32 Function(
    ffi.IntPtr hwo, ffi.Pointer<ffi.Uint8> pwh, ffi.Uint32 cbwh);
typedef _WaveOutPrepareHeaderDart = int Function(
    int hwo, ffi.Pointer<ffi.Uint8> pwh, int cbwh);

typedef _WaveOutUnprepareHeaderNative = ffi.Uint32 Function(
    ffi.IntPtr hwo, ffi.Pointer<ffi.Uint8> pwh, ffi.Uint32 cbwh);
typedef _WaveOutUnprepareHeaderDart = int Function(
    int hwo, ffi.Pointer<ffi.Uint8> pwh, int cbwh);

typedef _WaveOutWriteNative = ffi.Uint32 Function(
    ffi.IntPtr hwo, ffi.Pointer<ffi.Uint8> pwh, ffi.Uint32 cbwh);
typedef _WaveOutWriteDart = int Function(
    int hwo, ffi.Pointer<ffi.Uint8> pwh, int cbwh);

typedef _WaveOutResetNative = ffi.Uint32 Function(ffi.IntPtr hwo);
typedef _WaveOutResetDart = int Function(int hwo);

// --- waveIn Native Function Typedefs ---

typedef _WaveInOpenNative = ffi.Uint32 Function(
    ffi.Pointer<ffi.IntPtr> phwi,
    ffi.Uint32 uDeviceID,
    ffi.Pointer<ffi.Uint8> pwfx,
    ffi.IntPtr dwCallback,
    ffi.IntPtr dwInstance,
    ffi.Uint32 fdwOpen);
typedef _WaveInOpenDart = int Function(
    ffi.Pointer<ffi.IntPtr> phwi,
    int uDeviceID,
    ffi.Pointer<ffi.Uint8> pwfx,
    int dwCallback,
    int dwInstance,
    int fdwOpen);

typedef _WaveInCloseNative = ffi.Uint32 Function(ffi.IntPtr hwi);
typedef _WaveInCloseDart = int Function(int hwi);

typedef _WaveInPrepareHeaderNative = ffi.Uint32 Function(
    ffi.IntPtr hwi, ffi.Pointer<ffi.Uint8> pwh, ffi.Uint32 cbwh);
typedef _WaveInPrepareHeaderDart = int Function(
    int hwi, ffi.Pointer<ffi.Uint8> pwh, int cbwh);

typedef _WaveInUnprepareHeaderNative = ffi.Uint32 Function(
    ffi.IntPtr hwi, ffi.Pointer<ffi.Uint8> pwh, ffi.Uint32 cbwh);
typedef _WaveInUnprepareHeaderDart = int Function(
    int hwi, ffi.Pointer<ffi.Uint8> pwh, int cbwh);

typedef _WaveInAddBufferNative = ffi.Uint32 Function(
    ffi.IntPtr hwi, ffi.Pointer<ffi.Uint8> pwh, ffi.Uint32 cbwh);
typedef _WaveInAddBufferDart = int Function(
    int hwi, ffi.Pointer<ffi.Uint8> pwh, int cbwh);

typedef _WaveInStartNative = ffi.Uint32 Function(ffi.IntPtr hwi);
typedef _WaveInStartDart = int Function(int hwi);

typedef _WaveInStopNative = ffi.Uint32 Function(ffi.IntPtr hwi);
typedef _WaveInStopDart = int Function(int hwi);

typedef _WaveInResetNative = ffi.Uint32 Function(ffi.IntPtr hwi);
typedef _WaveInResetDart = int Function(int hwi);

/// Native Windows API bindings for Bluetooth RFCOMM (Winsock2) and
/// audio I/O (waveOut/waveIn via winmm.dll).
class WindowsNativeMethods {
  WindowsNativeMethods._();

  // --- DLL handles ---

  static final ffi.DynamicLibrary _ws2 =
      ffi.DynamicLibrary.open('ws2_32.dll');

  static final ffi.DynamicLibrary _winmm =
      ffi.DynamicLibrary.open('winmm.dll');

  // --- Winsock2 Bindings ---

  /// Initializes the Winsock2 library. Call with version 0x0202 for Winsock 2.2.
  static final int Function(
          int wVersionRequested, ffi.Pointer<ffi.Uint8> lpWSAData)
      wsaStartup =
      _ws2.lookupFunction<_WSAStartupNative, _WSAStartupDart>('WSAStartup');

  /// Terminates use of the Winsock2 library.
  static final int Function() wsaCleanup =
      _ws2.lookupFunction<_WSACleanupNative, _WSACleanupDart>('WSACleanup');

  /// Creates a socket. Returns a SOCKET handle, or [invalidSocket] on error.
  static final int Function(int af, int type, int protocol) socket =
      _ws2.lookupFunction<_SocketNative, _SocketDart>('socket');

  /// Connects a socket to a remote address.
  static final int Function(int s, ffi.Pointer<ffi.Void> name, int namelen)
      connect =
      _ws2.lookupFunction<_ConnectNative, _ConnectDart>('connect');

  /// Sends data on a connected socket.
  static final int Function(
          int s, ffi.Pointer<ffi.Uint8> buf, int len, int flags)
      send = _ws2.lookupFunction<_SendNative, _SendDart>('send');

  /// Receives data from a connected socket.
  static final int Function(
          int s, ffi.Pointer<ffi.Uint8> buf, int len, int flags)
      recv = _ws2.lookupFunction<_RecvNative, _RecvDart>('recv');

  /// Closes a socket.
  static final int Function(int s) closesocket =
      _ws2.lookupFunction<_ClosesocketNative, _ClosesocketDart>('closesocket');

  /// Returns the error code for the last Winsock operation that failed.
  static final int Function() wsaGetLastError =
      _ws2.lookupFunction<_WSAGetLastErrorNative, _WSAGetLastErrorDart>(
          'WSAGetLastError');

  /// Controls the I/O mode of a socket (e.g., set non-blocking with [fionbio]).
  static final int Function(int s, int cmd, ffi.Pointer<ffi.Uint32> argp)
      ioctlsocket =
      _ws2.lookupFunction<_IoctlsocketNative, _IoctlsocketDart>(
          'ioctlsocket');

  /// Polls a set of sockets for readability/writability/errors.
  static final int Function(
          ffi.Pointer<WsaPollFd> fdArray, int fds, int timeout)
      wsaPoll =
      _ws2.lookupFunction<_WSAPollNative, _WSAPollDart>('WSAPoll');

  // --- waveOut Bindings ---

  /// Opens a waveform-audio output device for playback.
  static final int Function(
          ffi.Pointer<ffi.IntPtr> phwo,
          int uDeviceID,
          ffi.Pointer<ffi.Uint8> pwfx,
          int dwCallback,
          int dwInstance,
          int fdwOpen)
      waveOutOpen = _winmm
          .lookupFunction<_WaveOutOpenNative, _WaveOutOpenDart>('waveOutOpen');

  /// Closes a waveform-audio output device.
  static final int Function(int hwo) waveOutClose =
      _winmm.lookupFunction<_WaveOutCloseNative, _WaveOutCloseDart>(
          'waveOutClose');

  /// Prepares a waveform-audio data block for playback.
  static final int Function(int hwo, ffi.Pointer<ffi.Uint8> pwh, int cbwh)
      waveOutPrepareHeader = _winmm.lookupFunction<
          _WaveOutPrepareHeaderNative,
          _WaveOutPrepareHeaderDart>('waveOutPrepareHeader');

  /// Cleans up preparation of a waveform-audio data block.
  static final int Function(int hwo, ffi.Pointer<ffi.Uint8> pwh, int cbwh)
      waveOutUnprepareHeader = _winmm.lookupFunction<
          _WaveOutUnprepareHeaderNative,
          _WaveOutUnprepareHeaderDart>('waveOutUnprepareHeader');

  /// Sends a data block to a waveform-audio output device for playback.
  static final int Function(int hwo, ffi.Pointer<ffi.Uint8> pwh, int cbwh)
      waveOutWrite =
      _winmm.lookupFunction<_WaveOutWriteNative, _WaveOutWriteDart>(
          'waveOutWrite');

  /// Stops playback and resets the position to zero.
  static final int Function(int hwo) waveOutReset =
      _winmm.lookupFunction<_WaveOutResetNative, _WaveOutResetDart>(
          'waveOutReset');

  // --- waveIn Bindings ---

  /// Opens a waveform-audio input device for recording.
  static final int Function(
          ffi.Pointer<ffi.IntPtr> phwi,
          int uDeviceID,
          ffi.Pointer<ffi.Uint8> pwfx,
          int dwCallback,
          int dwInstance,
          int fdwOpen)
      waveInOpen = _winmm
          .lookupFunction<_WaveInOpenNative, _WaveInOpenDart>('waveInOpen');

  /// Closes a waveform-audio input device.
  static final int Function(int hwi) waveInClose =
      _winmm.lookupFunction<_WaveInCloseNative, _WaveInCloseDart>(
          'waveInClose');

  /// Prepares a waveform-audio data block for recording.
  static final int Function(int hwi, ffi.Pointer<ffi.Uint8> pwh, int cbwh)
      waveInPrepareHeader = _winmm.lookupFunction<
          _WaveInPrepareHeaderNative,
          _WaveInPrepareHeaderDart>('waveInPrepareHeader');

  /// Cleans up preparation of a waveform-audio data block.
  static final int Function(int hwi, ffi.Pointer<ffi.Uint8> pwh, int cbwh)
      waveInUnprepareHeader = _winmm.lookupFunction<
          _WaveInUnprepareHeaderNative,
          _WaveInUnprepareHeaderDart>('waveInUnprepareHeader');

  /// Sends an input buffer to the waveform-audio input device for filling.
  static final int Function(int hwi, ffi.Pointer<ffi.Uint8> pwh, int cbwh)
      waveInAddBuffer =
      _winmm.lookupFunction<_WaveInAddBufferNative, _WaveInAddBufferDart>(
          'waveInAddBuffer');

  /// Starts recording on a waveform-audio input device.
  static final int Function(int hwi) waveInStart =
      _winmm.lookupFunction<_WaveInStartNative, _WaveInStartDart>(
          'waveInStart');

  /// Stops recording on a waveform-audio input device.
  static final int Function(int hwi) waveInStop =
      _winmm.lookupFunction<_WaveInStopNative, _WaveInStopDart>('waveInStop');

  /// Stops recording and resets the position to zero.
  static final int Function(int hwi) waveInReset =
      _winmm.lookupFunction<_WaveInResetNative, _WaveInResetDart>(
          'waveInReset');
}

// --- Helper Functions ---

/// Parses a MAC address string into a 64-bit Bluetooth address in Windows
/// byte order (little-endian NAP:UAP:LAP).
///
/// Accepts "XX:XX:XX:XX:XX:XX", "XX-XX-XX-XX-XX-XX", or "XXXXXXXXXXXX" format.
/// Returns the address as a uint64 suitable for SOCKADDR_BTH.btAddr.
int parseMacAddress(String mac) {
  final clean = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
  if (clean.length != 12) {
    throw ArgumentError('Invalid MAC address: $mac');
  }
  // Parse as big-endian hex, which is the standard representation.
  // Windows SOCKADDR_BTH.btAddr stores the address as a uint64 in
  // host byte order (little-endian on x86), with the bytes in
  // NAP:UAP:LAP order from MSB to LSB.
  int addr = 0;
  for (int i = 0; i < 6; i++) {
    final byte = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    addr = (addr << 8) | byte;
  }
  return addr;
}

/// Builds a SOCKADDR_BTH structure for Bluetooth RFCOMM connection.
///
/// Layout (30 bytes):
/// - [0..1]:   addressFamily (uint16 LE, AF_BTH = 32)
/// - [2..9]:   btAddr (uint64 LE, Bluetooth address)
/// - [10..25]: serviceClassId (GUID, 16 bytes, zeroed for RFCOMM by channel)
/// - [26..29]: port (uint32 LE, RFCOMM channel number)
///
/// The caller must free the returned pointer with [calloc.free].
ffi.Pointer<ffi.Uint8> buildSockaddrBth(String macAddress, int channel) {
  final addr = parseMacAddress(macAddress);
  final ptr = calloc<ffi.Uint8>(sockaddrBthSize);

  // addressFamily = AF_BTH (32) in little-endian
  ptr[0] = afBth & 0xFF;
  ptr[1] = (afBth >> 8) & 0xFF;

  // btAddr as uint64 little-endian
  for (int i = 0; i < 8; i++) {
    ptr[2 + i] = (addr >> (i * 8)) & 0xFF;
  }

  // serviceClassId: 16 bytes of zeros (use RFCOMM channel instead)
  // Already zeroed by calloc.

  // port = RFCOMM channel number as uint32 little-endian
  ptr[26] = channel & 0xFF;
  ptr[27] = (channel >> 8) & 0xFF;
  ptr[28] = (channel >> 16) & 0xFF;
  ptr[29] = (channel >> 24) & 0xFF;

  return ptr;
}

/// Allocates and populates a WAVEFORMATEX structure for PCM audio.
///
/// Layout (18 bytes):
/// - [0..1]:   wFormatTag (uint16, WAVE_FORMAT_PCM = 1)
/// - [2..3]:   nChannels (uint16)
/// - [4..7]:   nSamplesPerSec (uint32)
/// - [8..11]:  nAvgBytesPerSec (uint32)
/// - [12..13]: nBlockAlign (uint16)
/// - [14..15]: wBitsPerSample (uint16)
/// - [16..17]: cbSize (uint16, 0 for PCM)
///
/// The caller must free the returned pointer with [calloc.free].
ffi.Pointer<ffi.Uint8> buildWaveFormatEx({
  required int channels,
  required int samplesPerSec,
  required int bitsPerSample,
}) {
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final avgBytesPerSec = samplesPerSec * blockAlign;
  final ptr = calloc<ffi.Uint8>(waveFormatExSize);

  void writeU16(int offset, int value) {
    ptr[offset] = value & 0xFF;
    ptr[offset + 1] = (value >> 8) & 0xFF;
  }

  void writeU32(int offset, int value) {
    ptr[offset] = value & 0xFF;
    ptr[offset + 1] = (value >> 8) & 0xFF;
    ptr[offset + 2] = (value >> 16) & 0xFF;
    ptr[offset + 3] = (value >> 24) & 0xFF;
  }

  writeU16(0, waveFormatPcm); // wFormatTag
  writeU16(2, channels); // nChannels
  writeU32(4, samplesPerSec); // nSamplesPerSec
  writeU32(8, avgBytesPerSec); // nAvgBytesPerSec
  writeU16(12, blockAlign); // nBlockAlign
  writeU16(14, bitsPerSample); // wBitsPerSample
  writeU16(16, 0); // cbSize

  return ptr;
}

/// Allocates a WAVEHDR structure (48 bytes on 64-bit).
///
/// Layout on 64-bit Windows:
/// - [0..7]:   lpData (pointer to data buffer)
/// - [8..11]:  dwBufferLength (uint32)
/// - [12..15]: dwBytesRecorded (uint32)
/// - [16..23]: dwUser (pointer-sized)
/// - [24..27]: dwFlags (uint32)
/// - [28..31]: dwLoops (uint32)
/// - [32..39]: lpNext (pointer, used by driver)
/// - [40..47]: reserved (pointer-sized)
///
/// The caller must free the returned pointer with [calloc.free].
/// The [dataBuffer] pointer must remain valid until the header is unprepared.
ffi.Pointer<ffi.Uint8> buildWaveHdr(
    ffi.Pointer<ffi.Uint8> dataBuffer, int bufferLength) {
  final ptr = calloc<ffi.Uint8>(waveHdrSize);

  // lpData: write pointer value as little-endian 64-bit
  final dataAddr = dataBuffer.address;
  for (int i = 0; i < 8; i++) {
    ptr[i] = (dataAddr >> (i * 8)) & 0xFF;
  }

  // dwBufferLength
  ptr[8] = bufferLength & 0xFF;
  ptr[9] = (bufferLength >> 8) & 0xFF;
  ptr[10] = (bufferLength >> 16) & 0xFF;
  ptr[11] = (bufferLength >> 24) & 0xFF;

  // Remaining fields zeroed by calloc.

  return ptr;
}

/// Reads the dwFlags field from a WAVEHDR structure.
int readWaveHdrFlags(ffi.Pointer<ffi.Uint8> waveHdr) {
  return waveHdr[24] |
      (waveHdr[25] << 8) |
      (waveHdr[26] << 16) |
      (waveHdr[27] << 24);
}

/// Reads the dwBytesRecorded field from a WAVEHDR structure.
int readWaveHdrBytesRecorded(ffi.Pointer<ffi.Uint8> waveHdr) {
  return waveHdr[12] |
      (waveHdr[13] << 8) |
      (waveHdr[14] << 16) |
      (waveHdr[15] << 24);
}

/// Initializes Winsock2 (version 2.2). Must be called before any socket operations.
/// Returns 0 on success.
int initializeWinsock() {
  final wsaData = calloc<ffi.Uint8>(wsaDataSize);
  try {
    // Request Winsock 2.2: MAKEWORD(2, 2) = 0x0202
    return WindowsNativeMethods.wsaStartup(0x0202, wsaData);
  } finally {
    calloc.free(wsaData);
  }
}
