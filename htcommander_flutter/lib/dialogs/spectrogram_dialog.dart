import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';

/// Dialog for real-time audio spectrogram display with FFT analysis.
class SpectrogramDialog extends StatefulWidget {
  final int deviceId;

  const SpectrogramDialog({super.key, required this.deviceId});

  @override
  State<SpectrogramDialog> createState() => _SpectrogramDialogState();
}

class _SpectrogramDialogState extends State<SpectrogramDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  static const int _fftSize = 512;
  static const int _sampleRate = 32000;

  int _maxFreqHz = 16000;
  final List<List<double>> _spectrogramLines = [];
  static const int _maxLines = 200;

  // Audio sample buffer for FFT
  final List<double> _audioBuffer = [];

  @override
  void initState() {
    super.initState();
    _maxFreqHz = DataBroker.getValue<int>(0, 'SpectrogramMaxFreq', 16000);
    _broker.subscribe(
        widget.deviceId, 'AudioDataAvailable', _onAudioData);
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _onAudioData(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final pcmData = data['Data'];
    if (pcmData is! Uint8List) return;

    // Convert 16-bit PCM to doubles
    final bd = ByteData.view(pcmData.buffer, pcmData.offsetInBytes);
    final sampleCount = pcmData.length ~/ 2;
    for (var i = 0; i < sampleCount; i++) {
      _audioBuffer.add(bd.getInt16(i * 2, Endian.little) / 32768.0);
    }

    // Process FFT when we have enough samples
    while (_audioBuffer.length >= _fftSize) {
      final samples = Float64List(_fftSize);
      for (var i = 0; i < _fftSize; i++) {
        samples[i] = _audioBuffer[i];
      }
      _audioBuffer.removeRange(0, _fftSize ~/ 2); // 50% overlap

      // Apply Hanning window
      for (var i = 0; i < _fftSize; i++) {
        samples[i] *= 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (_fftSize - 1)));
      }

      // Compute FFT magnitude (Cooley-Tukey radix-2 in-place)
      final imag = Float64List(_fftSize);
      _fftInPlace(samples, imag);

      final binCount = _fftSize ~/ 2;
      final maxBin = (_maxFreqHz * _fftSize / _sampleRate).round().clamp(1, binCount);
      final magnitudes = List<double>.filled(maxBin, 0);
      for (var i = 0; i < maxBin; i++) {
        final re = samples[i];
        final im = imag[i];
        final mag = math.sqrt(re * re + im * im);
        // Convert to dB, normalize to 0..1 range (-60dB to 0dB)
        final db = 20 * math.log(mag + 1e-10) / math.ln10;
        magnitudes[i] = ((db + 60) / 60).clamp(0.0, 1.0);
      }

      setState(() {
        _spectrogramLines.add(magnitudes);
        while (_spectrogramLines.length > _maxLines) {
          _spectrogramLines.removeAt(0);
        }
      });
    }
  }

  /// Cooley-Tukey radix-2 DIT FFT in-place.
  void _fftInPlace(Float64List real, Float64List imag) {
    final n = real.length;
    // Bit-reversal permutation
    var j = 0;
    for (var i = 0; i < n - 1; i++) {
      if (i < j) {
        var t = real[i]; real[i] = real[j]; real[j] = t;
        t = imag[i]; imag[i] = imag[j]; imag[j] = t;
      }
      var m = n >> 1;
      while (m >= 1 && j >= m) { j -= m; m >>= 1; }
      j += m;
    }
    // FFT
    for (var step = 1; step < n; step <<= 1) {
      final halfStep = step;
      final tableStep = math.pi / halfStep;
      for (var group = 0; group < n; group += step << 1) {
        for (var pair = 0; pair < halfStep; pair++) {
          final angle = -tableStep * pair;
          final wr = math.cos(angle);
          final wi = math.sin(angle);
          final i1 = group + pair;
          final i2 = i1 + halfStep;
          final tr = wr * real[i2] - wi * imag[i2];
          final ti = wr * imag[i2] + wi * real[i2];
          real[i2] = real[i1] - tr;
          imag[i2] = imag[i1] - ti;
          real[i1] += tr;
          imag[i1] += ti;
        }
      }
    }
  }

  Color _viridisColor(double t) {
    // Simplified viridis-inspired colormap
    t = t.clamp(0.0, 1.0);
    if (t < 0.15) return Color.lerp(const Color(0xFF000020), const Color(0xFF0D0887), t / 0.15)!;
    if (t < 0.35) return Color.lerp(const Color(0xFF0D0887), const Color(0xFF6A00A8), (t - 0.15) / 0.2)!;
    if (t < 0.55) return Color.lerp(const Color(0xFF6A00A8), const Color(0xFF21918C), (t - 0.35) / 0.2)!;
    if (t < 0.75) return Color.lerp(const Color(0xFF21918C), const Color(0xFF5EC962), (t - 0.55) / 0.2)!;
    if (t < 0.90) return Color.lerp(const Color(0xFF5EC962), const Color(0xFFFDE725), (t - 0.75) / 0.15)!;
    return Color.lerp(const Color(0xFFFDE725), const Color(0xFFFFFFFF), (t - 0.90) / 0.10)!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('SPECTROGRAM', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: colors.onSurfaceVariant)),
              const Spacer(),
              _freqButton('4k', 4000, colors),
              _freqButton('8k', 8000, colors),
              _freqButton('16k', 16000, colors),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(
                    painter: _SpectrogramPainter(_spectrogramLines, _viridisColor),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('0 Hz — $_maxFreqHz Hz', style: TextStyle(fontSize: 9,
                  color: colors.onSurfaceVariant)),
              TextButton(onPressed: () => Navigator.pop(context),
                  child: Text('CLOSE', style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w600, letterSpacing: 1,
                      color: colors.onSurfaceVariant))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _freqButton(String label, int freq, ColorScheme colors) {
    final isSelected = _maxFreqHz == freq;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: () {
          setState(() => _maxFreqHz = freq);
          DataBroker.dispatch(0, 'SpectrogramMaxFreq', freq, store: true);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary.withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label, style: TextStyle(fontSize: 9,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? colors.primary : colors.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _SpectrogramPainter extends CustomPainter {
  final List<List<double>> lines;
  final Color Function(double) colorMapper;

  _SpectrogramPainter(this.lines, this.colorMapper);

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;
    final lineWidth = size.width / lines.length;
    for (var x = 0; x < lines.length; x++) {
      final line = lines[x];
      if (line.isEmpty) continue;
      final binHeight = size.height / line.length;
      for (var y = 0; y < line.length; y++) {
        canvas.drawRect(
          Rect.fromLTWH(x * lineWidth, size.height - (y + 1) * binHeight,
              lineWidth + 1, binHeight + 1),
          Paint()..color = colorMapper(line[y]),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter old) => true;
}
