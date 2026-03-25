/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Multi-slicer HDLC frame receiver with bit-error correction.
/// Port of HTCommander.Core/hamlib/HdlcRec2.cs
///
/// NOTE: The existing software_modem.dart already has a simpler single-slicer
/// HDLC decoder (_HdlcDecoder) and CRC-16 (_Crc16Ccitt). This file provides
/// the advanced multi-slicer version with error correction for use by
/// Demod9600, DemodPsk, and FX.25.
library;

import 'dart:typed_data';

import 'fcs_calc.dart';

// ---------------------------------------------------------------------------
// Enums and config types
// ---------------------------------------------------------------------------

/// Retry/fix-up attempt levels for bad CRC frames.
enum RetryType {
  none, // = 0
  invertSingle, // = 1
  invertDouble, // = 2
  invertTriple, // = 3
  invertTwoSep, // = 4
  max, // = 5
}

/// Sanity test levels to apply after fixing bits.
enum SanityTest { aprs, ax25, none }

/// Retry mode -- how bits are modified.
enum RetryMode { contiguous, separated }

/// Type of retry operation.
enum RetryOperation { none, swap }

/// FEC type for received signal.
enum FecType { none, fx25, il2p }

/// Configuration for retry/fix-up attempts.
class RetryConfig {
  RetryType retry = RetryType.none;
  RetryMode mode = RetryMode.contiguous;
  RetryOperation type = RetryOperation.none;
  // Separated mode indices.
  int bitIdxA = 0;
  int bitIdxB = 0;
  int bitIdxC = -1;
  // Contiguous mode.
  int bitIdx = 0;
  int numBits = 0;
  int insertValue = 0;
}

/// Audio-level placeholder.
class AudioLevel {
  final int rec;
  final int mark;
  final int space;
  const AudioLevel([this.rec = 0, this.mark = 0, this.space = 0]);
}

/// Correction information attached to decoded frames.
class CorrectionInfo {
  RetryType correctionType;
  FecType fecType;
  List<int> correctedBitPositions;
  int rsSymbolsCorrected;
  int fx25CorrelationTag;
  int frameLengthBits;
  int frameLengthBytes;
  int originalCrc;
  int expectedCrc;
  bool crcValid;

  CorrectionInfo({
    this.correctionType = RetryType.none,
    this.fecType = FecType.none,
    List<int>? correctedBitPositions,
    this.rsSymbolsCorrected = -1,
    this.fx25CorrelationTag = -1,
    this.frameLengthBits = 0,
    this.frameLengthBytes = 0,
    this.originalCrc = 0,
    this.expectedCrc = 0,
    this.crcValid = false,
  }) : correctedBitPositions = correctedBitPositions ?? [];
}

/// Event payload for decoded HDLC frames.
class FrameReceivedEvent {
  final int channel;
  final int subchannel;
  final int slice;
  final Uint8List frame;
  final int frameLength;
  final AudioLevel audioLevel;
  final CorrectionInfo? correctionInfo;

  const FrameReceivedEvent({
    required this.channel,
    required this.subchannel,
    required this.slice,
    required this.frame,
    required this.frameLength,
    this.audioLevel = const AudioLevel(),
    this.correctionInfo,
  });
}

// ---------------------------------------------------------------------------
// Raw bit buffer
// ---------------------------------------------------------------------------

/// Buffer that stores raw received bits between flag patterns.
class RawReceivedBitBuffer {
  final int chan;
  final int subchan;
  final int slice;
  bool isScrambled;
  int descramState;
  int prevDescram;
  AudioLevel audioLevel;

  final List<int> _bits = [];

  RawReceivedBitBuffer(
    this.chan,
    this.subchan,
    this.slice,
    this.isScrambled,
    this.descramState,
    this.prevDescram, {
    this.audioLevel = const AudioLevel(),
  });

  int get length => _bits.length;

  void appendBit(int bit) => _bits.add(bit & 1);

  int getBit(int index) => _bits[index];

  /// Remove the last 8 bits (flag pattern).
  void chop8() {
    if (_bits.length >= 8) {
      _bits.removeRange(_bits.length - 8, _bits.length);
    }
  }

  void clear(bool scrambled, int lfsr, int prevDesc) {
    _bits.clear();
    isScrambled = scrambled;
    descramState = lfsr;
    prevDescram = prevDesc;
  }
}

// ---------------------------------------------------------------------------
// HDLC state
// ---------------------------------------------------------------------------

class _HdlcState2 {
  int prevRaw = 0;
  bool isScrambled = false;
  int lfsr = 0;
  int prevDescram = 0;
  int patDet = 0;
  int oAcc = 0;
  int oLen = 0;
  final Uint8List frameBuffer = Uint8List(_maxFrameLen);
  int frameLen = 0;

  static const int _maxFrameLen = 2048 + 2;
}

// ---------------------------------------------------------------------------
// HdlcRec2
// ---------------------------------------------------------------------------

/// HDLC frame receiver with advanced error correction (Version 2).
class HdlcRec2 {
  static const int _minFrameLen = 8 + 2; // min packet + FCS
  static const int _maxFrameLen = 2048 + 2;

  RetryType fixBits;
  SanityTest sanityTest;
  bool passAll;

  RawReceivedBitBuffer? _currentBlock;
  final _HdlcState2 _state = _HdlcState2();

  /// Callback invoked when a valid frame is decoded.
  void Function(FrameReceivedEvent event)? onFrameReceived;

  HdlcRec2({
    this.fixBits = RetryType.invertTwoSep,
    this.sanityTest = SanityTest.aprs,
    this.passAll = false,
  });

  /// Handle DCD (Data Carrier Detect) state change.
  ///
  /// Currently a no-op — DCD state is tracked within the demodulator.
  /// Provided so that [DemodAfsk] can call it without special-casing.
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    // No-op: HdlcRec2 does not use DCD for frame assembly.
  }

  /// Process a single received bit.
  void recBit(int chan, int subchan, int slice, int raw,
      {bool isScrambled = false}) {
    _currentBlock ??= RawReceivedBitBuffer(
        chan, subchan, slice, isScrambled, 0, 0);

    // NRZI decode for pattern detection.
    final int dbit = (raw == _state.prevRaw) ? 1 : 0;
    _state.prevRaw = raw;

    _state.patDet = ((_state.patDet >> 1) | (dbit != 0 ? 0x80 : 0)) & 0xFF;

    _currentBlock!.appendBit(raw);

    if (_state.patDet == 0x7E) {
      _currentBlock!.chop8();

      if (_currentBlock!.length >= _minFrameLen * 8) {
        _currentBlock!.audioLevel = const AudioLevel();
        final blockToProcess = _currentBlock!;
        // Process synchronously (Dart is single-threaded).
        processBlock(blockToProcess);
        _currentBlock = RawReceivedBitBuffer(chan, subchan, slice,
            isScrambled, _state.lfsr, _state.prevDescram);
      } else {
        _currentBlock!
            .clear(isScrambled, _state.lfsr, _state.prevDescram);
      }
      _currentBlock!.appendBit(_state.prevRaw);
    } else if (_state.patDet == 0xFE) {
      _currentBlock!.clear(isScrambled, 0, 0);
      _state.prevRaw = raw;
    }
  }

  /// Process a block of raw bits extracted between flag patterns.
  void processBlock(RawReceivedBitBuffer block) {
    final int chan = block.chan;
    final int subchan = block.subchan;
    final int slice = block.slice;
    final AudioLevel alevel = block.audioLevel;

    // Simple HDLC decode.
    final Uint8List frame = Uint8List(_maxFrameLen);
    int frameLen = 0;
    int acc = 0;
    int bitCount = 0;
    int onesCount = 0;
    int prevRaw = block.getBit(0);
    bool skipNext = false;

    for (int i = 1; i < block.length; i++) {
      final int raw = block.getBit(i);
      final int dbit = (raw == prevRaw) ? 1 : 0;
      prevRaw = raw;

      if (skipNext) {
        skipNext = false;
        onesCount = 0;
        continue;
      }

      if (dbit == 1) {
        onesCount++;
        if (onesCount == 5) {
          skipNext = true;
        }
      } else {
        onesCount = 0;
      }

      acc = ((acc >> 1) | (dbit != 0 ? 0x80 : 0)) & 0xFF;
      bitCount++;

      if (bitCount == 8) {
        if (frameLen < _maxFrameLen) frame[frameLen++] = acc;
        bitCount = 0;
        acc = 0;
      }
    }

    if (frameLen >= _minFrameLen) {
      final int actualFcs = frame[frameLen - 2] | (frame[frameLen - 1] << 8);
      final int expectedFcs = FcsCalc.calculate(frame, frameLen - 2);

      if (actualFcs == expectedFcs) {
        _processReceivedFrame(chan, subchan, slice, frame, frameLen - 2,
            alevel, RetryType.none, null);
      } else if (fixBits.index > RetryType.none.index) {
        if (!_tryToFixQuickNow(block, chan, subchan, slice, alevel)) {
          if (passAll) {
            _processReceivedFrame(chan, subchan, slice, frame,
                frameLen - 2, alevel, RetryType.max, null);
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Error correction
  // -------------------------------------------------------------------------

  bool _tryToFixQuickNow(RawReceivedBitBuffer block, int chan, int subchan,
      int slice, AudioLevel alevel) {
    final int len = block.length;
    final rc = RetryConfig()..mode = RetryMode.contiguous;

    // Try inverting one bit.
    if (fixBits.index < RetryType.invertSingle.index) return false;
    rc.type = RetryOperation.swap;
    rc.retry = RetryType.invertSingle;
    rc.numBits = 1;
    for (int i = 0; i < len; i++) {
      rc.bitIdx = i;
      if (_tryDecode(block, chan, subchan, slice, alevel, rc, false)) {
        return true;
      }
    }

    // Try inverting two adjacent bits.
    if (fixBits.index < RetryType.invertDouble.index) return false;
    rc.retry = RetryType.invertDouble;
    rc.numBits = 2;
    for (int i = 0; i < len - 1; i++) {
      rc.bitIdx = i;
      if (_tryDecode(block, chan, subchan, slice, alevel, rc, false)) {
        return true;
      }
    }

    return false;
  }

  bool _tryDecode(RawReceivedBitBuffer block, int chan, int subchan,
      int slice, AudioLevel alevel, RetryConfig rc, bool passall) {
    final h = _HdlcState2();
    final int blen = block.length;

    h.isScrambled = block.isScrambled;
    h.prevDescram = block.prevDescram;
    h.lfsr = block.descramState;
    h.prevRaw = block.getBit(0);

    if (_isModified(0, rc)) {
      h.prevRaw = h.prevRaw == 0 ? 1 : 0;
    }

    for (int i = 1; i < blen; i++) {
      int raw = block.getBit(i);
      if (_isModified(i, rc)) {
        raw = raw == 0 ? 1 : 0;
      }

      h.patDet = ((h.patDet >> 1) & 0xFF);

      int dbit;
      if (h.isScrambled) {
        final int descram = _descramble(raw, h);
        dbit = (descram == h.prevDescram) ? 1 : 0;
        h.prevDescram = descram;
        h.prevRaw = raw;
      } else {
        dbit = (raw == h.prevRaw) ? 1 : 0;
        h.prevRaw = raw;
      }

      if (dbit != 0) {
        h.patDet = (h.patDet | 0x80) & 0xFF;
        if (h.patDet == 0xFE) return false; // abort
        h.oAcc = ((h.oAcc >> 1) | 0x80) & 0xFF;
      } else {
        if (h.patDet == 0x7E) return false; // flag inside data
        if ((h.patDet >> 2) == 0x1F) continue; // stuff bit
        h.oAcc = (h.oAcc >> 1) & 0xFF;
      }

      h.oLen++;
      if ((h.oLen & 8) != 0) {
        h.oLen = 0;
        if (h.frameLen < _maxFrameLen) {
          h.frameBuffer[h.frameLen] = h.oAcc;
          h.frameLen++;
        }
      }
    }

    if (h.oLen == 0 && h.frameLen >= _minFrameLen) {
      final int actualFcs =
          h.frameBuffer[h.frameLen - 2] | (h.frameBuffer[h.frameLen - 1] << 8);
      final int expectedFcs =
          FcsCalc.calculate(h.frameBuffer, h.frameLen - 2);

      if (actualFcs == expectedFcs &&
          _sanityCheck(h.frameBuffer, h.frameLen - 2, rc.retry)) {
        final corrInfo = CorrectionInfo(
          correctionType: rc.retry,
          frameLengthBits: blen,
          frameLengthBytes: h.frameLen - 2,
          originalCrc: actualFcs,
          expectedCrc: expectedFcs,
          crcValid: true,
        );
        _processReceivedFrame(chan, subchan, slice, h.frameBuffer,
            h.frameLen - 2, alevel, rc.retry, corrInfo);
        return true;
      }
    }
    return false;
  }

  bool _isModified(int bitIdx, RetryConfig rc) {
    if (rc.type != RetryOperation.swap) return false;
    if (rc.mode == RetryMode.contiguous) {
      return bitIdx >= rc.bitIdx && bitIdx < rc.bitIdx + rc.numBits;
    } else {
      return bitIdx == rc.bitIdxA ||
          bitIdx == rc.bitIdxB ||
          bitIdx == rc.bitIdxC;
    }
  }

  static int _descramble(int input, _HdlcState2 h) {
    final int bit16 = (h.lfsr >> 16) & 1;
    final int bit11 = (h.lfsr >> 11) & 1;
    final int output = (input ^ bit16 ^ bit11) & 1;
    h.lfsr = ((h.lfsr << 1) | (input & 1)) & 0x1FFFF;
    return output;
  }

  bool _sanityCheck(Uint8List buf, int blen, RetryType bitsFlipped) {
    if (bitsFlipped == RetryType.none) return true;
    if (sanityTest == SanityTest.none) return true;

    // Check address part is multiple of 7.
    int alen = 0;
    for (int j = 0; j < blen && alen == 0; j++) {
      if ((buf[j] & 0x01) != 0) alen = j + 1;
    }
    if (alen % 7 != 0) return false;
    if (alen ~/ 7 < 2 || alen ~/ 7 > 10) return false;

    for (int j = 0; j < alen; j += 7) {
      final int c0 = buf[j] >> 1;
      if (!_isUpperOrDigit(c0)) return false;
      for (int k = 1; k < 6; k++) {
        final int ch = buf[j + k] >> 1;
        if (!_isUpperOrDigit(ch) && ch != 0x20) return false;
      }
    }

    if (sanityTest == SanityTest.ax25) return true;

    // APRS check.
    if (alen >= blen || buf[alen] != 0x03 || buf[alen + 1] != 0xF0) {
      return false;
    }
    return true;
  }

  static bool _isUpperOrDigit(int ch) {
    return (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x30 && ch <= 0x39);
  }

  void _processReceivedFrame(int chan, int subchan, int slice,
      Uint8List frame, int frameLen, AudioLevel alevel,
      RetryType retries, CorrectionInfo? corrInfo) {
    if (onFrameReceived == null) return;
    onFrameReceived!(FrameReceivedEvent(
      channel: chan,
      subchannel: subchan,
      slice: slice,
      frame: Uint8List.fromList(frame.sublist(0, frameLen)),
      frameLength: frameLen,
      audioLevel: alevel,
      correctionInfo: corrInfo,
    ));
  }
}
