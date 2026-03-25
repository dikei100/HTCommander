/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// AFSK encoder — encodes AX.25 frames to AFSK 1200 baud audio.
/// Port of HTCommander.Core/hamlib/AfskEncoder.cs
library;

import 'dart:typed_data';

import 'gen_tone.dart';
import 'hdlc_send.dart';

/// Encodes AX.25 frames to AFSK or 9600 baud audio PCM.
class AfskEncoder {
  GenTone _genTone = GenTone();
  HdlcSend _hdlcSend = HdlcSend(_placeholderGenTone);
  int _sampleRate = 44100;
  int _txdelayFlags = 30;
  int _txtailFlags = 10;

  static final GenTone _placeholderGenTone = GenTone();

  AfskEncoder() {
    configureFor1200Baud();
  }

  /// Configure for standard AFSK 1200 baud (Bell 202).
  void configureFor1200Baud() {
    _sampleRate = 44100;
    _txdelayFlags = 30;
    _txtailFlags = 10;
    _genTone = GenTone();
    _genTone.init(
      sampleRate: _sampleRate,
      baud: 1200,
      markFreq: 1200,
      spaceFreq: 2200,
      amp: 50,
      modemType: GenToneModemType.afsk,
    );
    _hdlcSend = HdlcSend(_genTone);
  }

  /// Configure for 9600 baud G3RUH.
  void configureFor9600Baud() {
    _sampleRate = 44100;
    _txdelayFlags = 30;
    _txtailFlags = 10;
    _genTone = GenTone();
    _genTone.init(
      sampleRate: _sampleRate,
      baud: 9600,
      amp: 50,
      modemType: GenToneModemType.scramble,
    );
    _hdlcSend = HdlcSend(_genTone);
  }

  /// Encode a raw AX.25 frame to 16-bit signed PCM audio.
  ///
  /// [frameData] is the AX.25 frame (addresses + control + PID + info),
  /// without FCS — FCS is appended by the HDLC encoder.
  /// Returns PCM samples as little-endian bytes.
  Uint8List encodeFrame(Uint8List frameData, {bool use9600 = false}) {
    if (use9600) {
      configureFor9600Baud();
    } else {
      configureFor1200Baud();
    }

    // Preamble flags.
    _hdlcSend.sendFlags(_txdelayFlags);

    // Frame data.
    _hdlcSend.sendFrame(frameData, frameData.length);

    // Postamble flags.
    _hdlcSend.sendFlags(_txtailFlags);

    return _genTone.drainSamples();
  }

  /// Convenience: encode a text message into a basic AX.25 UI frame, then
  /// modulate to AFSK audio.
  Uint8List encodeMessage(String message, {bool use9600 = false}) {
    final frame = createAx25UiFrame(message);
    return encodeFrame(frame, use9600: use9600);
  }

  /// The sample rate of the most recent encoding.
  int get sampleRate => _sampleRate;

  // ── AX.25 frame helpers ──────────────────────────────────────────

  /// Create a minimal AX.25 UI frame (NOCALL→APRS) for [message].
  static Uint8List createAx25UiFrame(String message) {
    final frame = <int>[];
    // Destination: APRS
    _addAddress(frame, 'APRS', 0, false);
    // Source: NOCALL
    _addAddress(frame, 'NOCALL', 0, true);
    // Control: 0x03 (UI), PID: 0xF0 (no layer 3)
    frame.add(0x03);
    frame.add(0xF0);
    // Info field.
    for (int i = 0; i < message.length; i++) {
      frame.add(message.codeUnitAt(i) & 0x7F);
    }
    return Uint8List.fromList(frame);
  }

  static void _addAddress(List<int> frame, String callsign, int ssid,
      bool isLast) {
    final padded = callsign.padRight(6).substring(0, 6);
    for (int i = 0; i < 6; i++) {
      frame.add((padded.codeUnitAt(i) & 0x7F) << 1);
    }
    int ssidByte = 0x60 | ((ssid & 0x0F) << 1);
    if (isLast) ssidByte |= 0x01;
    frame.add(ssidByte);
  }
}
