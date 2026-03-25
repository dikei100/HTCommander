/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// Useful references:
// https://github.com/la5nta/wl2k-go
// https://github.com/la5nta/wl2k-go/blob/c52b1a2774edb0c7829d377ae4f21b2ae75c907a/docs/F6FBB-B2F/protocole.html
// https://outpostpm.org/index.php?content=bbs/bbswl2k
// https://raw.githubusercontent.com/ham-radio-software/lzhuf/refs/heads/main/lzhuf.c
// https://raw.githubusercontent.com/ARSFI/Winlink-Compression/refs/heads/master/WinlinkSupport.vb
// https://kg4nxo.com/wp-content/uploads/2021/04/WINLINK-COMMAND-CODES.pdf

/// Winlink secure login authentication.
class WinlinkSecurity {
  static const List<int> _winlinkSecureSalt = [
    77, 197, 101, 206, 190, 249, 93, 200, 51, 243, 93, 237, 71, 94, 239, 138,
    68, 108, 70, 185, 225, 137, 217, 16, 51, 122, 193, 48, 194, 195, 198, 175,
    172, 169, 70, 84, 61, 62, 104, 186, 114, 52, 61, 168, 66, 129, 192, 208,
    187, 249, 232, 193, 41, 113, 41, 45, 240, 16, 29, 228, 208, 228, 61, 20,
  ];

  /// MD5(challenge + password + salt), returns 8-digit decimal string.
  static String secureLoginResponse(String challenge, String password) {
    final a1 = challenge.codeUnits;
    final a2 = password.codeUnits;
    final a3 = _winlinkSecureSalt;

    final rv = Uint8List(a1.length + a2.length + a3.length);
    rv.setRange(0, a1.length, a1);
    rv.setRange(a1.length, a1.length + a2.length, a2);
    rv.setRange(a1.length + a2.length, rv.length, a3);

    final hashBytes = md5.convert(rv).bytes;
    int pr = hashBytes[3] & 0x3f;
    for (int i = 2; i >= 0; i--) {
      pr = (pr << 8) | hashBytes[i];
    }
    final str = pr.toString().padLeft(8, '0');
    return str.substring(str.length - 8);
  }

  /// Generate a random 8-digit challenge string.
  static String generateChallenge() {
    final rng = Random.secure();
    final value = rng.nextInt(100000000);
    return value.toString().padLeft(8, '0');
  }
}

/// LZHUF compression/decompression for Winlink B2F protocol.
class WinlinkCompression {
  static const int _n = 2048;
  static const int _f = 60;
  static const int _threshold = 2;
  static const int _nodeNIL = _n;
  static const int _nChar = (256 - _threshold) + _f;
  static const int _t = (_nChar * 2) - 1;
  static const int _r = _t - 1;
  static const int _maxFreq = 0x8000;
  static const int _tbSize = _n + _f - 2;

  // Position encode length
  static const List<int> _pLen = [
    0x3, 0x4, 0x4, 0x4, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
    0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
    0x8, 0x8, 0x8, 0x8,
  ];

  // Position encode table
  static const List<int> _pCode = [
    0x0, 0x20, 0x30, 0x40, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80, 0x88,
    0x90, 0x94, 0x98, 0x9C, 0xA0, 0xA4, 0xA8, 0xAC, 0xB0, 0xB4, 0xB8, 0xBC,
    0xC0, 0xC2, 0xC4, 0xC6, 0xC8, 0xCA, 0xCC, 0xCE, 0xD0, 0xD2, 0xD4, 0xD6,
    0xD8, 0xDA, 0xDC, 0xDE, 0xE0, 0xE2, 0xE4, 0xE6, 0xE8, 0xEA, 0xEC, 0xEE,
    0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB,
    0xFC, 0xFD, 0xFE, 0xFF,
  ];

  // Position decode table
  static const List<int> _dCode = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03,
    0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x04, 0x04, 0x04, 0x04,
    0x04, 0x04, 0x04, 0x04, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
    0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x07,
    0x07, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
    0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x0A, 0x0A, 0x0A, 0x0A,
    0x0A, 0x0A, 0x0A, 0x0A, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0C, 0x0C, 0x0C, 0x0C, 0x0D, 0x0D, 0x0D, 0x0D, 0x0E, 0x0E, 0x0E, 0x0E,
    0x0F, 0x0F, 0x0F, 0x0F, 0x10, 0x10, 0x10, 0x10, 0x11, 0x11, 0x11, 0x11,
    0x12, 0x12, 0x12, 0x12, 0x13, 0x13, 0x13, 0x13, 0x14, 0x14, 0x14, 0x14,
    0x15, 0x15, 0x15, 0x15, 0x16, 0x16, 0x16, 0x16, 0x17, 0x17, 0x17, 0x17,
    0x18, 0x18, 0x19, 0x19, 0x1A, 0x1A, 0x1B, 0x1B, 0x1C, 0x1C, 0x1D, 0x1D,
    0x1E, 0x1E, 0x1F, 0x1F, 0x20, 0x20, 0x21, 0x21, 0x22, 0x22, 0x23, 0x23,
    0x24, 0x24, 0x25, 0x25, 0x26, 0x26, 0x27, 0x27, 0x28, 0x28, 0x29, 0x29,
    0x2A, 0x2A, 0x2B, 0x2B, 0x2C, 0x2C, 0x2D, 0x2D, 0x2E, 0x2E, 0x2F, 0x2F,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B,
    0x3C, 0x3D, 0x3E, 0x3F,
  ];

  // Position decode length
  static const List<int> _dLen = [
    0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
    0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
    0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x4, 0x4, 0x4,
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
    0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x4, 0x5, 0x5, 0x5, 0x5,
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
    0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
    0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
    0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
    0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
    0x8, 0x8, 0x8, 0x8,
  ];

  // CRC Table (same polynomial as WinlinkCrc16 but used internally during LZHUF)
  static const int _crcMask = 0xFFFF;
  static const List<int> _crcTable = [
    0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50A5, 0x60C6, 0x70E7,
    0x8108, 0x9129, 0xA14A, 0xB16B, 0xC18C, 0xD1AD, 0xE1CE, 0xF1EF,
    0x1231, 0x0210, 0x3273, 0x2252, 0x52B5, 0x4294, 0x72F7, 0x62D6,
    0x9339, 0x8318, 0xB37B, 0xA35A, 0xD3BD, 0xC39C, 0xF3FF, 0xE3DE,
    0x2462, 0x3443, 0x0420, 0x1401, 0x64E6, 0x74C7, 0x44A4, 0x5485,
    0xA56A, 0xB54B, 0x8528, 0x9509, 0xE5EE, 0xF5CF, 0xC5AC, 0xD58D,
    0x3653, 0x2672, 0x1611, 0x0630, 0x76D7, 0x66F6, 0x5695, 0x46B4,
    0xB75B, 0xA77A, 0x9719, 0x8738, 0xF7DF, 0xE7FE, 0xD79D, 0xC7BC,
    0x48C4, 0x58E5, 0x6886, 0x78A7, 0x0840, 0x1861, 0x2802, 0x3823,
    0xC9CC, 0xD9ED, 0xE98E, 0xF9AF, 0x8948, 0x9969, 0xA90A, 0xB92B,
    0x5AF5, 0x4AD4, 0x7AB7, 0x6A96, 0x1A71, 0x0A50, 0x3A33, 0x2A12,
    0xDBFD, 0xCBDC, 0xFBBF, 0xEB9E, 0x9B79, 0x8B58, 0xBB3B, 0xAB1A,
    0x6CA6, 0x7C87, 0x4CE4, 0x5CC5, 0x2C22, 0x3C03, 0x0C60, 0x1C41,
    0xEDAE, 0xFD8F, 0xCDEC, 0xDDCD, 0xAD2A, 0xBD0B, 0x8D68, 0x9D49,
    0x7E97, 0x6EB6, 0x5ED5, 0x4EF4, 0x3E13, 0x2E32, 0x1E51, 0x0E70,
    0xFF9F, 0xEFBE, 0xDFDD, 0xCFFC, 0xBF1B, 0xAF3A, 0x9F59, 0x8F78,
    0x9188, 0x81A9, 0xB1CA, 0xA1EB, 0xD10C, 0xC12D, 0xF14E, 0xE16F,
    0x1080, 0x00A1, 0x30C2, 0x20E3, 0x5004, 0x4025, 0x7046, 0x6067,
    0x83B9, 0x9398, 0xA3FB, 0xB3DA, 0xC33D, 0xD31C, 0xE37F, 0xF35E,
    0x02B1, 0x1290, 0x22F3, 0x32D2, 0x4235, 0x5214, 0x6277, 0x7256,
    0xB5EA, 0xA5CB, 0x95A8, 0x8589, 0xF56E, 0xE54F, 0xD52C, 0xC50D,
    0x34E2, 0x24C3, 0x14A0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
    0xA7DB, 0xB7FA, 0x8799, 0x97B8, 0xE75F, 0xF77E, 0xC71D, 0xD73C,
    0x26D3, 0x36F2, 0x0691, 0x16B0, 0x6657, 0x7676, 0x4615, 0x5634,
    0xD94C, 0xC96D, 0xF90E, 0xE92F, 0x99C8, 0x89E9, 0xB98A, 0xA9AB,
    0x5844, 0x4865, 0x7806, 0x6827, 0x18C0, 0x08E1, 0x3882, 0x28A3,
    0xCB7D, 0xDB5C, 0xEB3F, 0xFB1E, 0x8BF9, 0x9BD8, 0xABBB, 0xBB9A,
    0x4A75, 0x5A54, 0x6A37, 0x7A16, 0x0AF1, 0x1AD0, 0x2AB3, 0x3A92,
    0xFD2E, 0xED0F, 0xDD6C, 0xCD4D, 0xBDAA, 0xAD8B, 0x9DE8, 0x8DC9,
    0x7C26, 0x6C07, 0x5C64, 0x4C45, 0x3CA2, 0x2C83, 0x1CE0, 0x0CC1,
    0xEF1F, 0xFF3E, 0xCF5D, 0xDF7C, 0xAF9B, 0xBFBA, 0x8FD9, 0x9FF8,
    0x6E17, 0x7E36, 0x4E55, 0x5E74, 0x2E93, 0x3EB2, 0x0ED1, 0x1EF0,
  ];

  // Instance state (Dart is single-threaded, no lock needed)
  late Uint8List _textBuf;
  late List<int> _lSon;
  late List<int> _dad;
  late List<int> _rSon;
  late List<int> _freq;
  late List<int> _son;
  late List<int> _parent;
  Uint8List? _inBuf;
  Uint8List? _outBuf;
  int _inPtr = 0;
  int _inEnd = 0;
  int _outPtr = 0;
  int _crc = 0;
  bool _encDec = false; // true=encode, false=decode
  int _getBuf = 0;
  int _getLen = 0;
  int _putBuf = 0;
  int _putLen = 0;
  int _textSize = 0;
  int _codeSize = 0;
  int _matchPosition = 0;
  int _matchLength = 0;

  /// Compress [input]. Returns (compressed data, CRC16).
  /// If [prependCrc] is true, the CRC is prepended to the output.
  static ({Uint8List compressed, int crc}) encode(Uint8List input,
      {bool prependCrc = false}) {
    final c = WinlinkCompression();
    return c._encode(input, prependCrc: prependCrc);
  }

  /// Decompress [input] to [expectedSize] bytes. Returns (decompressed data, CRC16).
  /// If [checkCrc] is true, validates the prepended CRC and returns empty on mismatch.
  static ({Uint8List decompressed, int crc}) decode(
      Uint8List input, int expectedSize,
      {bool checkCrc = false}) {
    final c = WinlinkCompression();
    return c._decode(input, expectedSize, checkCrc: checkCrc);
  }

  ({Uint8List compressed, int crc}) _encode(Uint8List iBuf,
      {bool prependCrc = false}) {
    _init();
    _encDec = true;

    _inBuf = Uint8List(iBuf.length + 100);
    _outBuf = Uint8List(iBuf.length * 2 + 10000);

    for (int i = 0; i < iBuf.length; i++) {
      _inBuf![_inEnd++] = iBuf[i];
    }

    _putc(_inEnd & 0xFF);
    _putc((_inEnd >> 8) & 0xFF);
    _putc((_inEnd >> 16) & 0xFF);
    _putc((_inEnd >> 24) & 0xFF);
    _codeSize += 4;

    if (_inEnd == 0) {
      return (compressed: Uint8List(0), crc: 0);
    }

    _textSize = 0;
    _startHuff();
    _initTree();
    int s = 0;
    int r = _n - _f;
    for (int i = 0; i < r; i++) {
      _textBuf[i] = 0x20;
    }

    int len = 0;
    while (len < _f && _inPtr < _inEnd) {
      _textBuf[r + len++] = _getc() & 0xFF;
    }
    _textSize = len;
    for (int i = 1; i <= _f; i++) {
      _insertNode(r - i);
    }
    _insertNode(r);

    do {
      if (_matchLength > len) _matchLength = len;
      if (_matchLength <= _threshold) {
        _matchLength = 1;
        _encodeChar(_textBuf[r]);
      } else {
        _encodeChar((255 - _threshold) + _matchLength);
        _encodePosition(_matchPosition);
      }
      int lastMatchLength = _matchLength;
      int i = 0;
      while (i < lastMatchLength && _inPtr < _inEnd) {
        i++;
        _deleteNode(s);
        int c = _getc();
        _textBuf[s] = c & 0xFF;
        if (s < _f - 1) _textBuf[s + _n] = c & 0xFF;
        s = (s + 1) & (_n - 1);
        r = (r + 1) & (_n - 1);
        _insertNode(r);
      }
      _textSize += i;
      while (i < lastMatchLength) {
        i++;
        _deleteNode(s);
        s = (s + 1) & (_n - 1);
        r = (r + 1) & (_n - 1);
        len--;
        if (len > 0) _insertNode(r);
      }
    } while (len > 0);

    _encodeEnd();
    int retCrc = _getCRC();

    Uint8List result;
    int j;
    if (prependCrc) {
      result = Uint8List(_codeSize + 2);
      result[0] = (retCrc >> 8) & 0xFF;
      result[1] = retCrc & 0xFF;
      j = 2;
    } else {
      result = Uint8List(_codeSize);
      j = 0;
    }
    for (int i = 0; i < _codeSize; i++) {
      result[j++] = _outBuf![i];
    }

    return (compressed: result, crc: retCrc);
  }

  ({Uint8List decompressed, int crc}) _decode(
      Uint8List iBuf, int expectedSize,
      {bool checkCrc = false}) {
    _encDec = false;
    _init();

    _inBuf = Uint8List(iBuf.length + 100);
    _outBuf = Uint8List(expectedSize + 10000);

    int iBufStart = 0;
    int suppliedCrc = 0;

    if (checkCrc) {
      iBufStart = 2;
      suppliedCrc = iBuf[1] & 0xFF;
      suppliedCrc |= (iBuf[0] << 8);
    }

    for (int i = iBufStart; i < iBuf.length; i++) {
      _inBuf![_inEnd++] = iBuf[i];
    }

    _textSize = _getc();
    _textSize |= (_getc() << 8);
    _textSize |= (_getc() << 16);
    _textSize |= (_getc() << 24);

    if (_textSize == 0) {
      return (decompressed: Uint8List(0), crc: 0);
    }

    _startHuff();

    for (int i = 0; i < (_n - _f); i++) {
      _textBuf[i] = 0x20;
    }

    int r = _n - _f;
    int count = 0;
    while (count < _textSize) {
      int c = _decodeChar();
      if (c < 256) {
        _putc(c & 0xFF);
        _textBuf[r] = c & 0xFF;
        r = (r + 1) & (_n - 1);
        count++;
      } else {
        int i = ((r - _decodePosition()) - 1) & (_n - 1);
        int j = (c - 255) + _threshold;
        for (int k = 0; k < j; k++) {
          c = _textBuf[(i + k) & (_n - 1)];
          _putc(c & 0xFF);
          _textBuf[r] = c & 0xFF;
          r = (r + 1) & (_n - 1);
          count++;
        }
      }
    }

    final retCrc = _getCRC();
    final result = Uint8List(count);
    for (int i = 0; i < count; i++) {
      result[i] = _outBuf![i];
    }

    if (checkCrc && retCrc != suppliedCrc) {
      return (decompressed: Uint8List(0), crc: retCrc);
    }

    return (decompressed: result, crc: retCrc);
  }

  int _getCRC() {
    return _swap(_crc & 0xFFFF);
  }

  void _init() {
    _inPtr = 0;
    _inEnd = 0;
    _outPtr = 0;
    _getBuf = 0;
    _getLen = 0;
    _putBuf = 0;
    _putLen = 0;
    _textSize = 0;
    _codeSize = 0;
    _matchPosition = 0;
    _matchLength = 0;
    _textBuf = Uint8List(_tbSize + 1);
    _lSon = List<int>.filled(_n + 1, 0);
    _dad = List<int>.filled(_n + 1, 0);
    _rSon = List<int>.filled(_n + 256 + 1, 0);
    _freq = List<int>.filled(_t + 1, 0);
    _son = List<int>.filled(_t, 0);
    _parent = List<int>.filled(_t + _nChar, 0);
    _crc = 0;
  }

  void _doCRC(int c) {
    _crc = ((_crc << 8) ^ _crcTable[((_crc >> 8) ^ c) & 0xFF]) & _crcMask;
  }

  int _getc() {
    int c = 0;
    if (_inPtr < _inEnd) {
      c = _inBuf![_inPtr++] & 0xFF;
      if (!_encDec) _doCRC(c);
    }
    return c;
  }

  void _putc(int c) {
    _outBuf![_outPtr++] = c & 0xFF;
    if (_encDec) _doCRC(c & 0xFF);
  }

  void _initTree() {
    for (int i = _n + 1; i <= _n + 256; i++) {
      _rSon[i] = _nodeNIL;
    }
    for (int i = 0; i < _n; i++) {
      _dad[i] = _nodeNIL;
    }
  }

  void _insertNode(int r) {
    int i, p, c;
    bool geq = true;

    p = _n + 1 + _textBuf[r];
    _rSon[r] = _nodeNIL;
    _lSon[r] = _nodeNIL;
    _matchLength = 0;

    while (true) {
      if (geq) {
        if (_rSon[p] == _nodeNIL) {
          _rSon[p] = r;
          _dad[r] = p;
          return;
        } else {
          p = _rSon[p];
        }
      } else {
        if (_lSon[p] == _nodeNIL) {
          _lSon[p] = r;
          _dad[r] = p;
          return;
        } else {
          p = _lSon[p];
        }
      }

      i = 1;
      while (i < _f && _textBuf[r + i] == _textBuf[p + i]) {
        i++;
      }

      geq = (_textBuf[r + i] >= _textBuf[p + i]) || (i == _f);

      if (i > _threshold) {
        if (i > _matchLength) {
          _matchPosition = ((r - p) & (_n - 1)) - 1;
          _matchLength = i;
          if (_matchLength >= _f) break;
        }
        if (i == _matchLength) {
          c = ((r - p) & (_n - 1)) - 1;
          if (c < _matchPosition) _matchPosition = c;
        }
      }
    }

    _dad[r] = _dad[p];
    _lSon[r] = _lSon[p];
    _rSon[r] = _rSon[p];
    _dad[_lSon[p]] = r;
    _dad[_rSon[p]] = r;
    if (_rSon[_dad[p]] == p) {
      _rSon[_dad[p]] = r;
    } else {
      _lSon[_dad[p]] = r;
    }
    _dad[p] = _nodeNIL;
  }

  void _deleteNode(int p) {
    int q;
    if (_dad[p] == _nodeNIL) return;

    if (_rSon[p] == _nodeNIL) {
      q = _lSon[p];
    } else if (_lSon[p] == _nodeNIL) {
      q = _rSon[p];
    } else {
      q = _lSon[p];
      if (_rSon[q] != _nodeNIL) {
        do {
          q = _rSon[q];
        } while (_rSon[q] != _nodeNIL);
        _rSon[_dad[q]] = _lSon[q];
        _dad[_lSon[q]] = _dad[q];
        _lSon[q] = _lSon[p];
        _dad[_lSon[p]] = q;
      }
      _rSon[q] = _rSon[p];
      _dad[_rSon[p]] = q;
    }
    _dad[q] = _dad[p];
    if (_rSon[_dad[p]] == p) {
      _rSon[_dad[p]] = q;
    } else {
      _lSon[_dad[p]] = q;
    }
    _dad[p] = _nodeNIL;
  }

  int _getBit() {
    while (_getLen <= 8) {
      _getBuf = (_getBuf | (_getc() << (8 - _getLen))) & 0xFFFF;
      _getLen += 8;
    }
    int retVal = (_getBuf >> 15) & 0x1;
    _getBuf = (_getBuf << 1) & 0xFFFF;
    _getLen--;
    return retVal;
  }

  int _getByte() {
    while (_getLen <= 8) {
      _getBuf = (_getBuf | (_getc() << (8 - _getLen))) & 0xFFFF;
      _getLen += 8;
    }
    int retVal = _hi(_getBuf) & 0xFF;
    _getBuf = (_getBuf << 8) & 0xFFFF;
    _getLen -= 8;
    return retVal;
  }

  void _putcode(int n, int c) {
    _putBuf = (_putBuf | (c >> _putLen)) & 0xFFFF;
    _putLen += n;
    if (_putLen >= 8) {
      _putc(_hi(_putBuf) & 0xFF);
      _putLen -= 8;
      if (_putLen >= 8) {
        _putc(_lo(_putBuf) & 0xFF);
        _codeSize += 2;
        _putLen -= 8;
        _putBuf = (c << (n - _putLen)) & 0xFFFF;
      } else {
        _putBuf = _swap(_putBuf & 0xFF);
        _codeSize += 1;
      }
    }
  }

  void _startHuff() {
    int i, j;
    for (i = 0; i < _nChar; i++) {
      _freq[i] = 1;
      _son[i] = i + _t;
      _parent[i + _t] = i;
    }
    i = 0;
    j = _nChar;
    while (j <= _r) {
      _freq[j] = (_freq[i] + _freq[i + 1]) & 0xFFFF;
      _son[j] = i;
      _parent[i] = j;
      _parent[i + 1] = j;
      i += 2;
      j++;
    }
    _freq[_t] = 0xFFFF;
    _parent[_r] = 0;
  }

  void _reconst() {
    int i, j = 0, k, f, n;

    for (i = 0; i < _t; i++) {
      if (_son[i] >= _t) {
        _freq[j] = (_freq[i] + 1) >> 1;
        _son[j] = _son[i];
        j++;
      }
    }

    i = 0;
    j = _nChar;
    while (j < _t) {
      k = i + 1;
      f = (_freq[i] + _freq[k]) & 0xFFFF;
      _freq[j] = f;
      k = j - 1;
      while (f < _freq[k]) {
        k--;
      }
      k++;
      for (n = j; n >= k + 1; n--) {
        _freq[n] = _freq[n - 1];
        _son[n] = _son[n - 1];
      }
      _freq[k] = f;
      _son[k] = i;
      i += 2;
      j++;
    }

    for (i = 0; i < _t; i++) {
      k = _son[i];
      _parent[k] = i;
      if (k < _t) _parent[k + 1] = i;
    }
  }

  void _update(int c) {
    int i, j, k, n;

    if (_freq[_r] == _maxFreq) _reconst();
    c = _parent[c + _t];
    do {
      _freq[c]++;
      k = _freq[c];

      n = c + 1;
      if (k > _freq[n]) {
        while (k > _freq[n + 1]) {
          n++;
        }
        _freq[c] = _freq[n];
        _freq[n] = k;

        i = _son[c];
        _parent[i] = n;
        if (i < _t) _parent[i + 1] = n;
        j = _son[n];
        _son[n] = i;

        _parent[j] = c;
        if (j < _t) _parent[j + 1] = c;
        _son[c] = j;

        c = n;
      }
      c = _parent[c];
    } while (c != 0);
  }

  void _encodeChar(int c) {
    int code = 0, k = _parent[c + _t];
    int len = 0;

    do {
      code >>= 1;
      if ((k & 1) > 0) code += 0x8000;
      len++;
      k = _parent[k];
    } while (k != _r);
    _putcode(len, code);
    _update(c);
  }

  void _encodePosition(int c) {
    int i = c >> 6;
    _putcode(_pLen[i], _pCode[i] << 8);
    _putcode(6, (c & 0x3F) << 10);
  }

  void _encodeEnd() {
    if (_putLen > 0) {
      _putc(_hi(_putBuf));
      _codeSize++;
    }
  }

  int _decodeChar() {
    int c = _son[_r];
    while (c < _t) {
      c = _son[c + _getBit()];
    }
    c -= _t;
    _update(c);
    return c & 0xFFFF;
  }

  int _decodePosition() {
    int i = _getByte();
    int c = (_dCode[i] << 6) & 0xFFFF;
    int j = _dLen[i];
    j -= 2;
    while (j > 0) {
      j--;
      i = ((i << 1) | _getBit()) & 0xFFFF;
    }
    return c | (i & 0x3F);
  }

  static int _hi(int x) => (x >> 8) & 0xFF;
  static int _lo(int x) => x & 0xFF;
  static int _swap(int x) => (((x >> 8) & 0xFF) | ((x & 0xFF) << 8)) & 0xFFFF;
}

/// Single-byte checksum for Winlink message validation.
class WinlinkChecksum {
  static int computeChecksum(Uint8List data, [int offset = 0, int? length]) {
    final len = length ?? data.length;
    int crc = 0;
    for (int i = offset; i < len; i++) {
      crc += data[i];
    }
    return ((~(crc % 256) + 1) % 256) & 0xFF;
  }

  static bool checkChecksum(Uint8List data, int checksum) {
    int crc = 0;
    for (int i = 0; i < data.length; i++) {
      crc += data[i];
    }
    return ((crc + checksum) & 0xFF) == 0;
  }
}

/// CRC-16 calculator for Winlink binary data blocks.
class WinlinkCrc16 {
  static const List<int> _crc16Tab = [
    0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7,
    0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef,
    0x1231, 0x0210, 0x3273, 0x2252, 0x52b5, 0x4294, 0x72f7, 0x62d6,
    0x9339, 0x8318, 0xb37b, 0xa35a, 0xd3bd, 0xc39c, 0xf3ff, 0xe3de,
    0x2462, 0x3443, 0x0420, 0x1401, 0x64e6, 0x74c7, 0x44a4, 0x5485,
    0xa56a, 0xb54b, 0x8528, 0x9509, 0xe5ee, 0xf5cf, 0xc5ac, 0xd58d,
    0x3653, 0x2672, 0x1611, 0x0630, 0x76d7, 0x66f6, 0x5695, 0x46b4,
    0xb75b, 0xa77a, 0x9719, 0x8738, 0xf7df, 0xe7fe, 0xd79d, 0xc7bc,
    0x48c4, 0x58e5, 0x6886, 0x78a7, 0x0840, 0x1861, 0x2802, 0x3823,
    0xc9cc, 0xd9ed, 0xe98e, 0xf9af, 0x8948, 0x9969, 0xa90a, 0xb92b,
    0x5af5, 0x4ad4, 0x7ab7, 0x6a96, 0x1a71, 0x0a50, 0x3a33, 0x2a12,
    0xdbfd, 0xcbdc, 0xfbbf, 0xeb9e, 0x9b79, 0x8b58, 0xbb3b, 0xab1a,
    0x6ca6, 0x7c87, 0x4ce4, 0x5cc5, 0x2c22, 0x3c03, 0x0c60, 0x1c41,
    0xedae, 0xfd8f, 0xcdec, 0xddcd, 0xad2a, 0xbd0b, 0x8d68, 0x9d49,
    0x7e97, 0x6eb6, 0x5ed5, 0x4ef4, 0x3e13, 0x2e32, 0x1e51, 0x0e70,
    0xff9f, 0xefbe, 0xdfdd, 0xcffc, 0xbf1b, 0xaf3a, 0x9f59, 0x8f78,
    0x9188, 0x81a9, 0xb1ca, 0xa1eb, 0xd10c, 0xc12d, 0xf14e, 0xe16f,
    0x1080, 0x00a1, 0x30c2, 0x20e3, 0x5004, 0x4025, 0x7046, 0x6067,
    0x83b9, 0x9398, 0xa3fb, 0xb3da, 0xc33d, 0xd31c, 0xe37f, 0xf35e,
    0x02b1, 0x1290, 0x22f3, 0x32d2, 0x4235, 0x5214, 0x6277, 0x7256,
    0xb5ea, 0xa5cb, 0x95a8, 0x8589, 0xf56e, 0xe54f, 0xd52c, 0xc50d,
    0x34e2, 0x24c3, 0x14a0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
    0xa7db, 0xb7fa, 0x8799, 0x97b8, 0xe75f, 0xf77e, 0xc71d, 0xd73c,
    0x26d3, 0x36f2, 0x0691, 0x16b0, 0x6657, 0x7676, 0x4615, 0x5634,
    0xd94c, 0xc96d, 0xf90e, 0xe92f, 0x99c8, 0x89e9, 0xb98a, 0xa9ab,
    0x5844, 0x4865, 0x7806, 0x6827, 0x18c0, 0x08e1, 0x3882, 0x28a3,
    0xcb7d, 0xdb5c, 0xeb3f, 0xfb1e, 0x8bf9, 0x9bd8, 0xabbb, 0xbb9a,
    0x4a75, 0x5a54, 0x6a37, 0x7a16, 0x0af1, 0x1ad0, 0x2ab3, 0x3a92,
    0xfd2e, 0xed0f, 0xdd6c, 0xcd4d, 0xbdaa, 0xad8b, 0x9de8, 0x8dc9,
    0x7c26, 0x6c07, 0x5c64, 0x4c45, 0x3ca2, 0x2c83, 0x1ce0, 0x0cc1,
    0xef1f, 0xff3e, 0xcf5d, 0xdf7c, 0xaf9b, 0xbfba, 0x8fd9, 0x9ff8,
    0x6e17, 0x7e36, 0x4e55, 0x5e74, 0x2e93, 0x3eb2, 0x0ed1, 0x1ef0,
  ];

  static int _udpCrc16(int cp, int sum) {
    return (((sum << 8) & 0xff00) ^ _crc16Tab[(sum >> 8) & 0xff] ^ cp) &
        0xFFFF;
  }

  /// Compute CRC-16 over [data], appending two zero bytes per the Winlink spec.
  static int compute(Uint8List data) {
    int sum = 0;
    final extended = Uint8List(data.length + 2);
    extended.setRange(0, data.length, data);
    // Last two bytes are already 0
    for (int i = 0; i < extended.length; i++) {
      sum = _udpCrc16(extended[i], sum);
    }
    return sum;
  }
}

/// Convert a hex string to bytes.
Uint8List hexStringToByteArray(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

/// Convert bytes to uppercase hex string.
String bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
}
