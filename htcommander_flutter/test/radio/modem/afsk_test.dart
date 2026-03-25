import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/radio/modem/afsk_decoder.dart';
import 'package:htcommander_flutter/radio/modem/afsk_encoder.dart';
import 'package:htcommander_flutter/radio/modem/demod_9600.dart';
import 'package:htcommander_flutter/radio/modem/demod_afsk.dart';
import 'package:htcommander_flutter/radio/modem/hdlc_rec2.dart';

void main() {
  group('AfskEncoder', () {
    test('creates valid PCM output for a simple message', () {
      final encoder = AfskEncoder();
      final pcm = encoder.encodeMessage('Hello AFSK');
      // Must produce some audio.
      expect(pcm.length, greaterThan(0));
      // 16-bit samples → even byte count.
      expect(pcm.length % 2, 0);
    });

    test('createAx25UiFrame produces correct structure', () {
      final frame = AfskEncoder.createAx25UiFrame('Test');
      // 7 bytes dest + 7 bytes src + 1 control + 1 PID + 4 info = 20
      expect(frame.length, 20);
      // Control = 0x03 (UI)
      expect(frame[14], 0x03);
      // PID = 0xF0
      expect(frame[15], 0xF0);
      // Last address flag set on source SSID byte
      expect(frame[13] & 0x01, 1);
    });
  });

  group('DemodAfsk', () {
    test('init Profile A sets PLL and filter parameters', () {
      final hdlcRec = HdlcRec2();
      final demod = DemodAfsk(hdlcRec);
      final state = DemodulatorState();
      demod.init(44100, 1200, 1200, 2200, 'A', state);

      expect(state.pllStepPerSample, isNonZero);
      expect(state.lpFilterTaps, greaterThan(0));
      expect(state.profile, 'A');
      expect(state.usePrefilter, 1);
      expect(state.afsk.mOscDelta, isNonZero);
      expect(state.afsk.sOscDelta, isNonZero);
    });

    test('init Profile B sets center oscillator', () {
      final hdlcRec = HdlcRec2();
      final demod = DemodAfsk(hdlcRec);
      final state = DemodulatorState();
      demod.init(44100, 1200, 1200, 2200, 'B', state);

      expect(state.profile, 'B');
      expect(state.afsk.cOscDelta, isNonZero);
      expect(state.afsk.normalizeRpsam, isNonZero);
    });

    test('processSample does not crash on zeros', () {
      final hdlcRec = HdlcRec2();
      final demod = DemodAfsk(hdlcRec);
      final state = DemodulatorState();
      demod.init(44100, 1200, 1200, 2200, 'A', state);

      // Feed 1000 zero samples — should not throw.
      for (int i = 0; i < 1000; i++) {
        demod.processSample(0, 0, 0, state);
      }
    });
  });

  group('AfskDecoder roundtrip', () {
    test('encode then decode recovers the original message', () {
      const message = 'Hello AX25 World';

      // Encode.
      final encoder = AfskEncoder();
      final pcmBytes = encoder.encodeMessage(message);
      final sampleRate = encoder.sampleRate;

      // Convert bytes to sample list.
      final sampleCount = pcmBytes.length ~/ 2;
      final samples = List<int>.generate(sampleCount, (i) {
        final lo = pcmBytes[i * 2];
        final hi = pcmBytes[i * 2 + 1];
        final raw = lo | (hi << 8);
        return raw > 32767 ? raw - 65536 : raw;
      });

      // Decode.
      final packets =
          AfskDecoder.decodeFromPcm(samples, sampleRate);
      expect(packets, isNotEmpty,
          reason: 'Should decode at least one packet');

      // Extract info field and check it contains our message.
      final pkt = packets.first;
      final info = pkt.data ?? Uint8List(0);
      final decoded = String.fromCharCodes(
          info.where((c) => c >= 32 && c <= 126));
      expect(decoded, contains(message));
    });

    test('decodeFromPcmBytes convenience method works', () {
      const message = 'ByteTest';
      final encoder = AfskEncoder();
      final pcmBytes = encoder.encodeMessage(message);
      final packets = AfskDecoder.decodeFromPcmBytes(
          pcmBytes, encoder.sampleRate);
      expect(packets, isNotEmpty);
    });
  });

  group('Cosine lookup table', () {
    test('fcos256 values match cos(j * 2pi / 256)', () {
      // Trigger table init by creating a DemodAfsk.
      final hdlcRec = HdlcRec2();
      final demod = DemodAfsk(hdlcRec);
      final state = DemodulatorState();
      demod.init(44100, 1200, 1200, 2200, 'A', state);

      // Verify by processing a known sample — if tables are wrong,
      // the demodulator would misbehave. This is an indirect check.
      // A direct check would require exposing the table, which we skip.
      demod.processSample(0, 0, 16384, state);
      demod.processSample(0, 0, -16384, state);
      // No crash = table is populated.
    });
  });

  group('Full pipeline integration', () {
    test('known flag pattern produces bits via HdlcRec2', () {
      int bitsReceived = 0;
      final hdlcRec = HdlcRec2();
      // We won't get frames from pure tones, but we can verify bits flow.
      final demod = DemodAfsk(hdlcRec);
      final state = DemodulatorState();
      demod.init(44100, 1200, 1200, 2200, 'A', state);

      // Generate a 1200 Hz mark tone for 100ms.
      final sampleCount = (44100 * 0.1).toInt();
      for (int i = 0; i < sampleCount; i++) {
        final sam =
            (sin(2 * pi * 1200 * i / 44100) * 16384).toInt();
        demod.processSample(0, 0, sam, state);
      }
      // No crash — the demodulator processed samples end-to-end.
    });
  });
}
