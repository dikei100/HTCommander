/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// AFSK (Audio Frequency Shift Keying) demodulator — 1200/2200 Hz.
/// Port of HTCommander.Core/hamlib/DemodAfsk.cs
///
/// Supports two profiles:
///  - **A**: Dual-tone amplitude comparison (best SNR)
///  - **B**: FM discriminator (center-frequency phase rate)
library;

import 'dart:math';
import 'dart:typed_data';

import 'dsp.dart';
import 'demod_9600.dart';
import 'hdlc_rec2.dart';

/// AFSK 1200 baud demodulator.
class DemodAfsk {
  static const double _minG = 0.5;
  static const double _maxG = 4.0;
  static const int _dcdThreshOn = 30;
  static const int _dcdThreshOff = 6;
  static const int _dcdGoodWidth = 512;
  static const int _maxSlicers = 9;

  static final Float64List _fcos256Table = Float64List(256);
  static final Float64List _spaceGain = Float64List(_maxSlicers);
  static bool _tablesInitialized = false;

  final HdlcRec2 _hdlcRec;

  DemodAfsk(this._hdlcRec);

  // ── Lookup tables ────────────────────────────────────────────────

  static void _initTables() {
    if (_tablesInitialized) return;
    for (int j = 0; j < 256; j++) {
      _fcos256Table[j] = cos(j * 2.0 * pi / 256.0);
    }
    _spaceGain[0] = _minG;
    final double step = pow(10.0, log(_maxG / _minG) / (ln10 * (_maxSlicers - 1))).toDouble();
    for (int j = 1; j < _maxSlicers; j++) {
      _spaceGain[j] = _spaceGain[j - 1] * step;
    }
    _tablesInitialized = true;
  }

  static double _fcos256(int x) =>
      _fcos256Table[((x >> 24) & 0xFF)];

  static double _fsin256(int x) =>
      _fcos256Table[(((x >> 24) - 64) & 0xFF)];

  static double _fastHypot(double x, double y) => sqrt(x * x + y * y);

  static void _pushSample(double val, Float64List buff, int size) {
    for (int i = size - 1; i > 0; i--) {
      buff[i] = buff[i - 1];
    }
    buff[0] = val;
  }

  static double _convolve(Float64List data, Float64List filter, int taps) {
    double sum = 0;
    for (int j = 0; j < taps; j++) {
      sum += filter[j] * data[j];
    }
    return sum;
  }

  // ── AGC ──────────────────────────────────────────────────────────

  /// Result settles to ≈ ±0.5 peak-to-peak.
  static double _agc(double input, double fastAttack, double slowDecay,
      _AgcRef ref) {
    if (input >= ref.peak) {
      ref.peak = input * fastAttack + ref.peak * (1.0 - fastAttack);
    } else {
      ref.peak = input * slowDecay + ref.peak * (1.0 - slowDecay);
    }
    if (input <= ref.valley) {
      ref.valley = input * fastAttack + ref.valley * (1.0 - fastAttack);
    } else {
      ref.valley = input * slowDecay + ref.valley * (1.0 - slowDecay);
    }
    double x = input;
    if (x > ref.peak) x = ref.peak;
    if (x < ref.valley) x = ref.valley;
    if (ref.peak > ref.valley) {
      return (x - 0.5 * (ref.peak + ref.valley)) / (ref.peak - ref.valley);
    }
    return 0;
  }

  // ── Initialization ───────────────────────────────────────────────

  /// Initialize the AFSK demodulator.
  void init(int samplesPerSec, int baud, int markFreq, int spaceFreq,
      String profile, DemodulatorState d) {
    _initTables();
    d.profile = profile;
    d.numSlicers = 1;

    switch (profile) {
      case 'A':
      case 'E':
        d.profile = 'A';
        _initProfileA(samplesPerSec, baud, markFreq, spaceFreq, d);
      case 'B':
      case 'D':
        d.profile = 'B';
        _initProfileB(samplesPerSec, baud, markFreq, spaceFreq, d);
      default:
        throw ArgumentError('Invalid AFSK demodulator profile = $profile');
    }

    // PLL timing.
    if (baud == 521) {
      d.pllStepPerSample =
          (DemodulatorState.ticksPerPllCycle * 520.83 / samplesPerSec).round();
    } else {
      d.pllStepPerSample =
          (DemodulatorState.ticksPerPllCycle * baud / samplesPerSec).round();
    }

    // Prefilter.
    if (d.usePrefilter != 0) {
      d.preFilterTaps =
          ((d.preFilterLenSym * samplesPerSec / baud).toInt()) | 1;
      if (d.preFilterTaps > Dsp.maxFilterSize) {
        d.preFilterTaps = (Dsp.maxFilterSize - 1) | 1;
      }
      double f1 =
          (min(markFreq, spaceFreq) - d.prefilterBaud * baud) / samplesPerSec;
      double f2 =
          (max(markFreq, spaceFreq) + d.prefilterBaud * baud) / samplesPerSec;
      Dsp.genBandpass(f1, f2, d.preFilter, d.preFilterTaps, d.preWindow);
    }

    // Low-pass filter.
    if (d.afsk.useRrc != 0) {
      d.lpFilterTaps =
          ((d.afsk.rrcWidthSym * samplesPerSec / baud).toInt()) | 1;
      if (d.lpFilterTaps > Dsp.maxFilterSize) {
        d.lpFilterTaps = (Dsp.maxFilterSize - 1) | 1;
      }
      Dsp.genRrcLowpass(
          d.lpFilter, d.lpFilterTaps, d.afsk.rrcRolloff,
          samplesPerSec / baud);
    } else {
      d.lpFilterTaps =
          (d.lpFilterWidthSym * samplesPerSec / baud).round();
      if (d.lpFilterTaps > Dsp.maxFilterSize) {
        d.lpFilterTaps = (Dsp.maxFilterSize - 1) | 1;
      }
      final double fc = baud * d.lpfBaud / samplesPerSec;
      Dsp.genLowpass(fc, d.lpFilter, d.lpFilterTaps, d.lpWindow);
    }
  }

  void _initProfileA(int samplesPerSec, int baud, int markFreq,
      int spaceFreq, DemodulatorState d) {
    d.usePrefilter = 1;
    if (baud > 600) {
      d.prefilterBaud = 0.155;
      d.preFilterLenSym = 383 * 1200.0 / 44100.0;
      d.preWindow = BpWindowType.truncated;
    } else {
      d.prefilterBaud = 0.87;
      d.preFilterLenSym = 1.857;
      d.preWindow = BpWindowType.cosine;
    }

    d.afsk.mOscPhase = 0;
    d.afsk.mOscDelta =
        (pow(2.0, 32) * markFreq / samplesPerSec).round() & 0xFFFFFFFF;
    d.afsk.sOscPhase = 0;
    d.afsk.sOscDelta =
        (pow(2.0, 32) * spaceFreq / samplesPerSec).round() & 0xFFFFFFFF;

    d.afsk.useRrc = 1;
    if (d.afsk.useRrc != 0) {
      d.afsk.rrcWidthSym = 2.80;
      d.afsk.rrcRolloff = 0.20;
    } else {
      d.lpfBaud = 0.14;
      d.lpFilterWidthSym = 1.388;
      d.lpWindow = BpWindowType.truncated;
    }

    d.agcFastAttack = 0.70;
    d.agcSlowDecay = 0.000090;
    d.pllLockedInertia = 0.74;
    d.pllSearchingInertia = 0.50;
    d.quickAttack = d.agcFastAttack;
    d.sluggishDecay = d.agcSlowDecay;
  }

  void _initProfileB(int samplesPerSec, int baud, int markFreq,
      int spaceFreq, DemodulatorState d) {
    d.usePrefilter = 1;
    if (baud > 600) {
      d.prefilterBaud = 0.19;
      d.preFilterLenSym = 8.163;
      d.preWindow = BpWindowType.truncated;
    } else {
      d.prefilterBaud = 0.87;
      d.preFilterLenSym = 1.857;
      d.preWindow = BpWindowType.cosine;
    }

    d.afsk.cOscPhase = 0;
    d.afsk.cOscDelta =
        (pow(2.0, 32) * 0.5 * (markFreq + spaceFreq) / samplesPerSec)
                .round() &
            0xFFFFFFFF;

    d.afsk.useRrc = 1;
    if (d.afsk.useRrc != 0) {
      d.afsk.rrcWidthSym = 2.00;
      d.afsk.rrcRolloff = 0.40;
    } else {
      d.lpfBaud = 0.5;
      d.lpFilterWidthSym = 1.714286;
      d.lpWindow = BpWindowType.truncated;
    }

    d.afsk.normalizeRpsam =
        1.0 / (0.5 * (markFreq - spaceFreq).abs() * 2 * pi / samplesPerSec);

    d.agcFastAttack = 0.70;
    d.agcSlowDecay = 0.000090;
    d.pllLockedInertia = 0.74;
    d.pllSearchingInertia = 0.50;
    d.quickAttack = d.agcFastAttack;
    d.sluggishDecay = d.agcSlowDecay;

    d.alevelMarkPeak = -1;
    d.alevelSpacePeak = -1;
  }

  // ── Per-sample processing ────────────────────────────────────────

  /// Process one 16-bit signed audio sample.
  void processSample(int chan, int subchan, int sam, DemodulatorState d) {
    final double fsam = sam / 16384.0;
    switch (d.profile) {
      case 'A':
        _processSampleProfileA(chan, subchan, fsam, d);
      case 'B':
        _processSampleProfileB(chan, subchan, fsam, d);
    }
  }

  // Reusable AGC refs to avoid per-sample allocations.
  final _AgcRef _mAgc = _AgcRef();
  final _AgcRef _sAgc = _AgcRef();

  void _processSampleProfileA(
      int chan, int subchan, double fsam, DemodulatorState d) {
    // Prefilter.
    if (d.usePrefilter != 0) {
      _pushSample(fsam, d.rawCb, d.preFilterTaps);
      fsam = _convolve(d.rawCb, d.preFilter, d.preFilterTaps);
    }

    // Mix with Mark LO.
    _pushSample(
        fsam * _fcos256(d.afsk.mOscPhase), d.afsk.mIRaw, d.lpFilterTaps);
    _pushSample(
        fsam * _fsin256(d.afsk.mOscPhase), d.afsk.mQRaw, d.lpFilterTaps);
    d.afsk.mOscPhase = (d.afsk.mOscPhase + d.afsk.mOscDelta) & 0xFFFFFFFF;

    // Mix with Space LO.
    _pushSample(
        fsam * _fcos256(d.afsk.sOscPhase), d.afsk.sIRaw, d.lpFilterTaps);
    _pushSample(
        fsam * _fsin256(d.afsk.sOscPhase), d.afsk.sQRaw, d.lpFilterTaps);
    d.afsk.sOscPhase = (d.afsk.sOscPhase + d.afsk.sOscDelta) & 0xFFFFFFFF;

    // Lowpass filter and amplitude.
    final double mI = _convolve(d.afsk.mIRaw, d.lpFilter, d.lpFilterTaps);
    final double mQ = _convolve(d.afsk.mQRaw, d.lpFilter, d.lpFilterTaps);
    final double mAmp = _fastHypot(mI, mQ);

    final double sI = _convolve(d.afsk.sIRaw, d.lpFilter, d.lpFilterTaps);
    final double sQ = _convolve(d.afsk.sQRaw, d.lpFilter, d.lpFilterTaps);
    final double sAmp = _fastHypot(sI, sQ);

    // Audio level tracking.
    if (mAmp >= d.alevelMarkPeak) {
      d.alevelMarkPeak =
          mAmp * d.quickAttack + d.alevelMarkPeak * (1.0 - d.quickAttack);
    } else {
      d.alevelMarkPeak =
          mAmp * d.sluggishDecay + d.alevelMarkPeak * (1.0 - d.sluggishDecay);
    }
    if (sAmp >= d.alevelSpacePeak) {
      d.alevelSpacePeak =
          sAmp * d.quickAttack + d.alevelSpacePeak * (1.0 - d.quickAttack);
    } else {
      d.alevelSpacePeak =
          sAmp * d.sluggishDecay +
              d.alevelSpacePeak * (1.0 - d.sluggishDecay);
    }

    if (d.numSlicers <= 1) {
      _mAgc.peak = d.mPeak;
      _mAgc.valley = d.mValley;
      final double mNorm =
          _agc(mAmp, d.agcFastAttack, d.agcSlowDecay, _mAgc);
      d.mPeak = _mAgc.peak;
      d.mValley = _mAgc.valley;

      _sAgc.peak = d.sPeak;
      _sAgc.valley = d.sValley;
      final double sNorm =
          _agc(sAmp, d.agcFastAttack, d.agcSlowDecay, _sAgc);
      d.sPeak = _sAgc.peak;
      d.sValley = _sAgc.valley;

      _nudgePll(chan, subchan, 0, mNorm - sNorm, d, 1.0);
    } else {
      _mAgc.peak = d.mPeak;
      _mAgc.valley = d.mValley;
      _agc(mAmp, d.agcFastAttack, d.agcSlowDecay, _mAgc);
      d.mPeak = _mAgc.peak;
      d.mValley = _mAgc.valley;

      _sAgc.peak = d.sPeak;
      _sAgc.valley = d.sValley;
      _agc(sAmp, d.agcFastAttack, d.agcSlowDecay, _sAgc);
      d.sPeak = _sAgc.peak;
      d.sValley = _sAgc.valley;

      for (int slice = 0; slice < d.numSlicers; slice++) {
        final double demodOut = mAmp - sAmp * _spaceGain[slice];
        double amp = 0.5 *
            (d.mPeak - d.mValley + (d.sPeak - d.sValley) * _spaceGain[slice]);
        if (amp < 0.0000001) amp = 1;
        _nudgePll(chan, subchan, slice, demodOut, d, amp);
      }
    }
  }

  void _processSampleProfileB(
      int chan, int subchan, double fsam, DemodulatorState d) {
    // Prefilter.
    if (d.usePrefilter != 0) {
      _pushSample(fsam, d.rawCb, d.preFilterTaps);
      fsam = _convolve(d.rawCb, d.preFilter, d.preFilterTaps);
    }

    // Mix with Center LO.
    _pushSample(
        fsam * _fcos256(d.afsk.cOscPhase), d.afsk.cIRaw, d.lpFilterTaps);
    _pushSample(
        fsam * _fsin256(d.afsk.cOscPhase), d.afsk.cQRaw, d.lpFilterTaps);
    d.afsk.cOscPhase = (d.afsk.cOscPhase + d.afsk.cOscDelta) & 0xFFFFFFFF;

    final double cI = _convolve(d.afsk.cIRaw, d.lpFilter, d.lpFilterTaps);
    final double cQ = _convolve(d.afsk.cQRaw, d.lpFilter, d.lpFilterTaps);

    double phase = atan2(cQ, cI);
    double rate = phase - d.afsk.prevPhase;
    if (rate > pi) {
      rate -= 2 * pi;
    } else if (rate < -pi) {
      rate += 2 * pi;
    }
    d.afsk.prevPhase = phase;

    final double normRate = rate * d.afsk.normalizeRpsam;

    if (d.numSlicers <= 1) {
      _nudgePll(chan, subchan, 0, normRate, d, 1.0);
    } else {
      for (int slice = 0; slice < d.numSlicers; slice++) {
        final double offset =
            -0.5 + slice * (1.0 / (d.numSlicers - 1));
        _nudgePll(chan, subchan, slice, normRate + offset, d, 1.0);
      }
    }
  }

  // ── Digital PLL ──────────────────────────────────────────────────

  void _nudgePll(int chan, int subchan, int slice, double demodOut,
      DemodulatorState d, double amplitude) {
    final s = d.slicer[slice];
    s.prevDClockPll = s.dataClockPll;

    // Unsigned 32-bit add.
    s.dataClockPll = (s.dataClockPll + d.pllStepPerSample) & 0xFFFFFFFF;

    // Overflow detection (zero crossing → sample the bit).
    if (_toSigned32(s.dataClockPll) < 0 &&
        _toSigned32(s.prevDClockPll) > 0) {
      final int bitValue = demodOut > 0 ? 1 : 0;
      _hdlcRec.recBit(chan, subchan, slice, bitValue);
      _pllDcdEachSymbol(d, chan, subchan, slice);
    }

    // Transition detection → nudge PLL.
    final int demodData = demodOut > 0 ? 1 : 0;
    if (demodData != s.prevDemodData) {
      _pllDcdSignalTransition(d, slice, _toSigned32(s.dataClockPll));
      if (s.dataDetect != 0) {
        s.dataClockPll =
            (_toSigned32(s.dataClockPll) * d.pllLockedInertia).toInt() &
                0xFFFFFFFF;
      } else {
        s.dataClockPll =
            (_toSigned32(s.dataClockPll) * d.pllSearchingInertia).toInt() &
                0xFFFFFFFF;
      }
    }
    s.prevDemodData = demodData;
  }

  void _pllDcdSignalTransition(
      DemodulatorState d, int slice, int dpllPhase) {
    if (dpllPhase > -_dcdGoodWidth * 1024 * 1024 &&
        dpllPhase < _dcdGoodWidth * 1024 * 1024) {
      d.slicer[slice].goodFlag = 1;
    } else {
      d.slicer[slice].badFlag = 1;
    }
  }

  void _pllDcdEachSymbol(
      DemodulatorState d, int chan, int subchan, int slice) {
    final s = d.slicer[slice];
    s.goodHist = ((s.goodHist << 1) | s.goodFlag) & 0xFF;
    s.goodFlag = 0;
    s.badHist = ((s.badHist << 1) | s.badFlag) & 0xFF;
    s.badFlag = 0;
    s.score = ((s.score << 1) & 0xFFFFFFFF);
    s.score |= ((_popCount8(s.goodHist) - _popCount8(s.badHist) >= 2) ? 1 : 0);

    final int scoreCount = _popCount32(s.score);
    if (scoreCount >= _dcdThreshOn) {
      if (s.dataDetect == 0) {
        s.dataDetect = 1;
        _hdlcRec.dcdChange(chan, subchan, slice, true);
      }
    } else if (scoreCount <= _dcdThreshOff) {
      if (s.dataDetect != 0) {
        s.dataDetect = 0;
        _hdlcRec.dcdChange(chan, subchan, slice, false);
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  static int _popCount8(int x) {
    int v = x & 0xFF;
    int c = 0;
    while (v != 0) {
      c++;
      v &= v - 1;
    }
    return c;
  }

  static int _popCount32(int x) {
    int v = x & 0xFFFFFFFF;
    int c = 0;
    while (v != 0) {
      c++;
      v &= v - 1;
    }
    return c;
  }

  static int _toSigned32(int v) {
    v &= 0xFFFFFFFF;
    if (v >= 0x80000000) return v - 0x100000000;
    return v;
  }
}

/// Mutable AGC peak/valley holder (avoids per-sample allocation).
class _AgcRef {
  double peak = 0;
  double valley = 0;
}
