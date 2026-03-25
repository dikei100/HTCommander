/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// AFSK decoder — decodes 1200 baud or 9600 baud audio into AX.25 packets.
/// Port of HTCommander.Core/hamlib/AfskDecoder.cs (orchestration layer only,
/// debug output omitted).
library;

import 'dart:typed_data';

import '../ax25/ax25_packet.dart';
import '../models/tnc_data_fragment.dart';
import 'demod_9600.dart';
import 'demod_afsk.dart';
import 'hdlc_rec2.dart';

/// Decodes AFSK (or 9600 baseband) audio samples into AX.25 packets.
class AfskDecoder {
  /// Decode 16-bit signed PCM samples into a list of AX.25 packets.
  ///
  /// [samples] — signed 16-bit mono PCM (Dart ints in ±32768 range).
  /// [sampleRate] — sampling frequency in Hz.
  /// [use9600] — `true` to use 9600 baud G3RUH instead of AFSK 1200.
  /// [profile] — AFSK demodulator profile ('A' or 'B', default 'A').
  static List<AX25Packet> decodeFromPcm(
    List<int> samples,
    int sampleRate, {
    bool use9600 = false,
    String profile = 'A',
  }) {
    final packets = <AX25Packet>[];

    // Set up HDLC receiver with frame callback.
    final hdlcRec = HdlcRec2();
    hdlcRec.onFrameReceived = (FrameReceivedEvent e) {
      final packet = _frameToPacket(e.frame, e.frameLength);
      if (packet != null) packets.add(packet);
    };

    const int chan = 0;
    const int subchan = 0;

    if (use9600) {
      final demodState = DemodulatorState();
      final state9600 = Demod9600State();
      Demod9600.init(sampleRate, 1, 9600, demodState, state9600);
      for (int i = 0; i < samples.length; i++) {
        Demod9600.processSample(
            chan, samples[i], 1, demodState, state9600, hdlcRec);
      }
    } else {
      final demodAfsk = DemodAfsk(hdlcRec);
      final demodState = DemodulatorState();
      demodAfsk.init(sampleRate, 1200, 1200, 2200, profile, demodState);
      for (int i = 0; i < samples.length; i++) {
        demodAfsk.processSample(chan, subchan, samples[i], demodState);
      }
    }

    return packets;
  }

  /// Decode 16-bit little-endian PCM byte array.
  static List<AX25Packet> decodeFromPcmBytes(
    Uint8List pcmBytes,
    int sampleRate, {
    bool use9600 = false,
    String profile = 'A',
  }) {
    final sampleCount = pcmBytes.length ~/ 2;
    final samples = List<int>.generate(sampleCount, (i) {
      final lo = pcmBytes[i * 2];
      final hi = pcmBytes[i * 2 + 1];
      final raw = lo | (hi << 8);
      return raw > 32767 ? raw - 65536 : raw;
    });
    return decodeFromPcm(samples, sampleRate,
        use9600: use9600, profile: profile);
  }

  /// Bridge: raw HDLC frame bytes → [AX25Packet].
  static AX25Packet? _frameToPacket(Uint8List frame, int frameLen) {
    final data = frameLen < frame.length
        ? Uint8List.fromList(frame.sublist(0, frameLen))
        : frame;
    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: data,
      channelId: -1,
      regionId: 0,
    );
    return AX25Packet.decodeAx25Packet(fragment);
  }
}
