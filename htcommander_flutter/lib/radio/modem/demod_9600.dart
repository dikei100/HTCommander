/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// 9600 baud G3RUH baseband demodulator.
/// Port of HTCommander.Core/hamlib/Demod9600.cs
library;

import 'dart:math';
import 'dart:typed_data';

import 'dsp.dart';
import 'hdlc_rec2.dart';

// ---------------------------------------------------------------------------
// Slicer state (shared with PSK demod)
// ---------------------------------------------------------------------------

/// Per-slicer PLL and DCD state.
class SlicerState {
  int dataClockPll = 0;
  int prevDClockPll = 0;
  double prevDemodOutF = 0;
  int prevDemodData = 0;
  int dataDetect = 0;
  int goodFlag = 0;
  int badFlag = 0;
  int goodHist = 0;
  int badHist = 0;
  int score = 0;
  int pllSymbolCount = 0;
  int lfsr = 0;
  int pllNudgeTotal = 0;
}

// ---------------------------------------------------------------------------
// Demodulator state (shared base)
// ---------------------------------------------------------------------------

/// Common demodulator state shared between 9600, PSK, and AFSK demodulators.
class DemodulatorState {
  static const double ticksPerPllCycle = 256.0 * 256.0 * 256.0 * 256.0;

  int numSlicers = 1;
  int pllStepPerSample = 0;
  double pllLockedInertia = 0.89;
  double pllSearchingInertia = 0.67;
  double quickAttack = 0.080;
  double sluggishDecay = 0.00012;
  double alevelMarkPeak = 0;
  double alevelSpacePeak = 0;
  double mPeak = 0;
  double mValley = 0;

  // AFSK-specific fields (used by DemodAfsk)
  String profile = 'A';
  int usePrefilter = 0;
  double prefilterBaud = 0;
  double preFilterLenSym = 0;
  BpWindowType preWindow = BpWindowType.truncated;
  int preFilterTaps = 0;
  final Float64List preFilter = Float64List(Dsp.maxFilterSize);
  final Float64List rawCb = Float64List(Dsp.maxFilterSize);
  double lpfBaud = 0;
  double lpFilterWidthSym = 0;
  BpWindowType lpWindow = BpWindowType.truncated;
  int lpFilterTaps = 0;
  final Float64List lpFilter = Float64List(Dsp.maxFilterSize);
  double agcFastAttack = 0.70;
  double agcSlowDecay = 0.000090;
  double sPeak = 0;
  double sValley = 0;
  double alevelRecPeak = 0;
  double alevelRecValley = 0;

  /// AFSK oscillator/mixer state.
  final AfskState afsk = AfskState();

  final List<SlicerState> slicer;

  DemodulatorState({int maxSlicers = 9})
      : slicer = List.generate(maxSlicers, (_) => SlicerState());
}

/// AFSK-specific oscillator, mixer, and filter state.
class AfskState {
  // Local oscillators for Mark, Space, and Center frequencies
  int mOscPhase = 0;
  int mOscDelta = 0;
  int sOscPhase = 0;
  int sOscDelta = 0;
  int cOscPhase = 0;
  int cOscDelta = 0;

  // Mixer outputs for Mark (profile A)
  final Float64List mIRaw = Float64List(Dsp.maxFilterSize);
  final Float64List mQRaw = Float64List(Dsp.maxFilterSize);

  // Mixer outputs for Space (profile A)
  final Float64List sIRaw = Float64List(Dsp.maxFilterSize);
  final Float64List sQRaw = Float64List(Dsp.maxFilterSize);

  // Mixer outputs for Center (profile B)
  final Float64List cIRaw = Float64List(Dsp.maxFilterSize);
  final Float64List cQRaw = Float64List(Dsp.maxFilterSize);

  // Root Raised Cosine filter settings
  int useRrc = 0;
  double rrcWidthSym = 0;
  double rrcRolloff = 0;

  // For FM demodulator (profile B)
  double prevPhase = 0;
  double normalizeRpsam = 0;
}

// ---------------------------------------------------------------------------
// 9600-specific state
// ---------------------------------------------------------------------------

class _BasebandState {
  final Float64List audioIn = Float64List(Dsp.maxFilterSize);
  final Float64List lpFilter = Float64List(Dsp.maxFilterSize);
  final Float64List lpPolyphase1 = Float64List(Dsp.maxFilterSize);
  final Float64List lpPolyphase2 = Float64List(Dsp.maxFilterSize);
  final Float64List lpPolyphase3 = Float64List(Dsp.maxFilterSize);
  final Float64List lpPolyphase4 = Float64List(Dsp.maxFilterSize);
}

/// 9600-baud demodulator-specific configuration.
class Demod9600State {
  final _BasebandState _bb = _BasebandState();
  int lpFilterSize = 0;
  BpWindowType lpWindow = BpWindowType.cosine;
  double agcFastAttack = 0.080;
  double agcSlowDecay = 0.00012;
  double pllLockedInertia = 0.89;
  double pllSearchingInertia = 0.67;
  int pllStepPerSample = 0;
}

// ---------------------------------------------------------------------------
// Demod9600
// ---------------------------------------------------------------------------

/// 9600 baud G3RUH baseband demodulator.
class Demod9600 {
  static const int _dcdThreshOn = 32;
  static const int _dcdThreshOff = 8;
  static const int _dcdGoodWidth = 1024;
  static const double _ticksPerPllCycle = 256.0 * 256.0 * 256.0 * 256.0;
  static const int _maxSubchans = 9;

  static final Float64List _slicePoint = Float64List(_maxSubchans);

  Demod9600._();

  /// Initialize the 9600 baud demodulator.
  static void init(int originalSampleRate, int upsample, int baud,
      DemodulatorState d, Demod9600State state9600) {
    if (upsample < 1) upsample = 1;
    if (upsample > 4) upsample = 4;
    d.numSlicers = 1;

    final double lpFilterLenBits = 1.0;
    state9600.lpFilterSize =
        (lpFilterLenBits * originalSampleRate / baud + 0.5).toInt();
    state9600.lpWindow = BpWindowType.cosine;

    state9600.agcFastAttack = 0.080;
    state9600.agcSlowDecay = 0.00012;
    state9600.pllLockedInertia = 0.89;
    state9600.pllSearchingInertia = 0.67;
    state9600.pllStepPerSample =
        (_ticksPerPllCycle * baud / (originalSampleRate * upsample)).round();

    final double fc = baud * 1.00 / (originalSampleRate * upsample);
    Dsp.genLowpass(fc, state9600._bb.lpFilter,
        state9600.lpFilterSize * upsample, state9600.lpWindow);

    // Scatter into polyphase filters.
    int k = 0;
    for (int i = 0; i < state9600.lpFilterSize; i++) {
      state9600._bb.lpPolyphase1[i] = state9600._bb.lpFilter[k++];
      if (upsample >= 2) {
        state9600._bb.lpPolyphase2[i] = state9600._bb.lpFilter[k++];
        if (upsample >= 3) {
          state9600._bb.lpPolyphase3[i] = state9600._bb.lpFilter[k++];
          if (upsample >= 4) {
            state9600._bb.lpPolyphase4[i] = state9600._bb.lpFilter[k++];
          }
        }
      }
    }

    for (int j = 0; j < _maxSubchans; j++) {
      _slicePoint[j] = 0.02 * (j - 0.5 * (_maxSubchans - 1));
    }
  }

  /// Process a single audio sample.
  static void processSample(int chan, int sam, int upsample,
      DemodulatorState d, Demod9600State s, HdlcRec2 hdlcReceiver) {
    final double fsam = sam / 16384.0;
    _pushSample(fsam, s._bb.audioIn, s.lpFilterSize);

    double filtered =
        _convolve(s._bb.audioIn, s._bb.lpPolyphase1, s.lpFilterSize);
    _processFilteredSample(chan, filtered, d, s, hdlcReceiver);

    if (upsample >= 2) {
      filtered =
          _convolve(s._bb.audioIn, s._bb.lpPolyphase2, s.lpFilterSize);
      _processFilteredSample(chan, filtered, d, s, hdlcReceiver);
      if (upsample >= 3) {
        filtered =
            _convolve(s._bb.audioIn, s._bb.lpPolyphase3, s.lpFilterSize);
        _processFilteredSample(chan, filtered, d, s, hdlcReceiver);
        if (upsample >= 4) {
          filtered = _convolve(
              s._bb.audioIn, s._bb.lpPolyphase4, s.lpFilterSize);
          _processFilteredSample(chan, filtered, d, s, hdlcReceiver);
        }
      }
    }
  }

  static void _pushSample(double val, Float64List buff, int size) {
    for (int i = size - 1; i > 0; i--) {
      buff[i] = buff[i - 1];
    }
    buff[0] = val;
  }

  static double _convolve(Float64List data, Float64List filter, int size) {
    double sum = 0;
    for (int j = 0; j < size; j++) {
      sum += filter[j] * data[j];
    }
    return sum;
  }

  static double _agc(double input, double fastAttack, double slowDecay,
      _AgcState agc) {
    if (input >= agc.peak) {
      agc.peak = input * fastAttack + agc.peak * (1.0 - fastAttack);
    } else {
      agc.peak = input * slowDecay + agc.peak * (1.0 - slowDecay);
    }
    if (input <= agc.valley) {
      agc.valley = input * fastAttack + agc.valley * (1.0 - fastAttack);
    } else {
      agc.valley = input * slowDecay + agc.valley * (1.0 - slowDecay);
    }
    if (agc.peak > agc.valley) {
      return (input - 0.5 * (agc.peak + agc.valley)) /
          (agc.peak - agc.valley);
    }
    return 0.0;
  }

  static final _AgcState _agcState = _AgcState();

  static void _processFilteredSample(int chan, double fsam,
      DemodulatorState d, Demod9600State s, HdlcRec2 hdlcReceiver) {
    const int subchan = 0;

    // Audio level tracking.
    if (fsam >= d.alevelMarkPeak) {
      d.alevelMarkPeak =
          fsam * d.quickAttack + d.alevelMarkPeak * (1.0 - d.quickAttack);
    } else {
      d.alevelMarkPeak =
          fsam * d.sluggishDecay + d.alevelMarkPeak * (1.0 - d.sluggishDecay);
    }
    if (fsam <= d.alevelSpacePeak) {
      d.alevelSpacePeak =
          fsam * d.quickAttack + d.alevelSpacePeak * (1.0 - d.quickAttack);
    } else {
      d.alevelSpacePeak =
          fsam * d.sluggishDecay +
              d.alevelSpacePeak * (1.0 - d.sluggishDecay);
    }

    _agcState.peak = d.mPeak;
    _agcState.valley = d.mValley;
    final double demodOut =
        _agc(fsam, s.agcFastAttack, s.agcSlowDecay, _agcState);
    d.mPeak = _agcState.peak;
    d.mValley = _agcState.valley;

    if (d.numSlicers <= 1) {
      _nudgePll(chan, subchan, 0, demodOut, d, s, hdlcReceiver);
    } else {
      for (int slice = 0; slice < d.numSlicers; slice++) {
        _nudgePll(chan, subchan, slice, demodOut - _slicePoint[slice], d,
            s, hdlcReceiver);
      }
    }
  }

  static void _nudgePll(int chan, int subchan, int slice, double demodOutF,
      DemodulatorState d, Demod9600State s, HdlcRec2 hdlcReceiver) {
    final ss = d.slicer[slice];
    ss.prevDClockPll = ss.dataClockPll;

    // Unsigned 32-bit add.
    ss.dataClockPll =
        (ss.dataClockPll + s.pllStepPerSample) & 0xFFFFFFFF;

    // Check for overflow (was large positive, now wrapped).
    final int prev = _toSigned32(ss.prevDClockPll);
    final int curr = _toSigned32(ss.dataClockPll);
    if (prev > 1000000000 && curr < -1000000000) {
      final int rawBit = demodOutF > 0 ? 1 : 0;
      final int descrambled = descramble(rawBit, ss);
      hdlcReceiver.recBit(chan, subchan, slice, descrambled);
      ss.pllSymbolCount++;
      _pllDcdEachSymbol(d, chan, subchan, slice);
    }

    if ((ss.prevDemodOutF < 0 && demodOutF > 0) ||
        (ss.prevDemodOutF > 0 && demodOutF < 0)) {
      _pllDcdSignalTransition(d, slice, _toSigned32(ss.dataClockPll));

      final double target = s.pllStepPerSample *
          demodOutF /
          (demodOutF - ss.prevDemodOutF);
      final int before = _toSigned32(ss.dataClockPll);

      if (ss.dataDetect != 0) {
        ss.dataClockPll = (_toSigned32(ss.dataClockPll) *
                    s.pllLockedInertia +
                target * (1.0 - s.pllLockedInertia))
            .toInt() &
            0xFFFFFFFF;
      } else {
        ss.dataClockPll = (_toSigned32(ss.dataClockPll) *
                    s.pllSearchingInertia +
                target * (1.0 - s.pllSearchingInertia))
            .toInt() &
            0xFFFFFFFF;
      }
      ss.pllNudgeTotal += _toSigned32(ss.dataClockPll) - before;
    }
    ss.prevDemodOutF = demodOutF;
  }

  /// G3RUH/K9NG descrambler.
  static int descramble(int input, SlicerState s) {
    final int output =
        (input ^ (s.lfsr >> 16) ^ (s.lfsr >> 11)) & 1;
    s.lfsr = ((s.lfsr << 1) | (input & 1)) & 0x1FFFF;
    return output;
  }

  static void _pllDcdSignalTransition(
      DemodulatorState d, int slice, int dpllPhase) {
    if (dpllPhase > -_dcdGoodWidth * 1024 * 1024 &&
        dpllPhase < _dcdGoodWidth * 1024 * 1024) {
      d.slicer[slice].goodFlag = 1;
    } else {
      d.slicer[slice].badFlag = 1;
    }
  }

  static void _pllDcdEachSymbol(
      DemodulatorState d, int chan, int subchan, int slice) {
    final ss = d.slicer[slice];

    ss.goodHist = ((ss.goodHist << 1) | ss.goodFlag) & 0xFF;
    ss.goodFlag = 0;
    ss.badHist = ((ss.badHist << 1) | ss.badFlag) & 0xFF;
    ss.badFlag = 0;
    ss.score = ((ss.score << 1) & 0xFFFFFFFF);

    final int goodCount = _popCount(ss.goodHist);
    final int badCount = _popCount(ss.badHist);
    ss.score |= ((goodCount - badCount >= 2) ? 1 : 0);

    final int scoreCount = _popCount32(ss.score);
    if (scoreCount >= _dcdThreshOn) {
      if (ss.dataDetect == 0) ss.dataDetect = 1;
    } else if (scoreCount <= _dcdThreshOff) {
      if (ss.dataDetect != 0) ss.dataDetect = 0;
    }
  }

  static int _popCount(int value) {
    int v = value & 0xFF;
    int count = 0;
    while (v != 0) {
      count++;
      v &= v - 1;
    }
    return count;
  }

  static int _popCount32(int value) {
    int v = value & 0xFFFFFFFF;
    int count = 0;
    while (v != 0) {
      count++;
      v &= v - 1;
    }
    return count;
  }

  static int _toSigned32(int v) {
    v &= 0xFFFFFFFF;
    if (v >= 0x80000000) return v - 0x100000000;
    return v;
  }
}

class _AgcState {
  double peak = 0;
  double valley = 0;
}
