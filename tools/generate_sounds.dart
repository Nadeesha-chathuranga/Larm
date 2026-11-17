/// Generates the ten original "Popular" alarm tones used by Larm.
///
/// Run from the repository root:
///   dart run tools/generate_sounds.dart
///
/// The tones are synthesized with additive waveforms and envelopes, so they
/// are royalty-free and deterministic (no external assets or licensing risk).
/// Output is written to both the Flutter asset folder and Android res/raw so
/// in-app previews and notification channels stay in sync.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;

double _env(double t, double attack, double decay) {
  if (t < 0) return 0;
  if (t < attack) return t / attack;
  return math.exp(-(t - attack) / decay);
}

double _bell(double t, double freq, double decay) {
  if (t < 0) return 0;
  final e = _env(t, 0.004, decay);
  return e *
      (0.55 * math.sin(2 * math.pi * freq * t) +
          0.28 * math.sin(2 * math.pi * freq * 2.01 * t) +
          0.13 * math.sin(2 * math.pi * freq * 3.03 * t) +
          0.06 * math.sin(2 * math.pi * freq * 4.97 * t));
}

double _pluck(double t, double freq, double decay) {
  if (t < 0) return 0;
  final e = _env(t, 0.002, decay);
  return e *
      (0.62 * math.sin(2 * math.pi * freq * t) +
          0.24 * math.sin(2 * math.pi * freq * 2 * t) +
          0.10 * math.sin(2 * math.pi * freq * 3 * t));
}

double _square(double t, double freq) {
  final phase = (t * freq) % 1.0;
  return phase < 0.5 ? 1.0 : -1.0;
}

List<double> _buffer(double seconds) =>
    List<double>.filled((seconds * sampleRate).round(), 0.0);

void _mix(List<double> out, List<double> tone, double startSec) {
  final start = (startSec * sampleRate).round();
  for (var i = 0; i < tone.length && start + i < out.length; i++) {
    out[start + i] += tone[i];
  }
}

List<double> _classicChime() {
  final out = _buffer(3.0);
  for (final start in [0.0, 0.95, 1.9]) {
    _mix(
      out,
      List<double>.generate(
        (1.15 * sampleRate).round(),
        (i) => _bell(i / sampleRate, 659.25, 0.28),
      ),
      start,
    );
  }
  return out;
}

List<double> _digitalClock() {
  final out = _buffer(2.6);
  const pattern = [
    (0.0, 880.0, 0.13),
    (0.18, 1174.66, 0.13),
    (0.36, 880.0, 0.13),
    (0.54, 1174.66, 0.13),
    (0.85, 880.0, 0.22),
    (1.15, 1174.66, 0.22),
    (1.5, 1567.98, 0.45),
  ];
  for (final (start, freq, len) in pattern) {
    _mix(
      out,
      List<double>.generate((len * sampleRate).round(), (i) {
        final t = i / sampleRate;
        return _env(t, 0.003, len * 0.35) *
            (0.32 * _square(t, freq) +
                0.18 * math.sin(2 * math.pi * freq * 2 * t));
      }),
      start,
    );
  }
  return out;
}

List<double> _morningBell() {
  final out = _buffer(3.2);
  for (final start in [0.0, 1.1, 2.2]) {
    _mix(
      out,
      List<double>.generate(
        (1.2 * sampleRate).round(),
        (i) => _bell(i / sampleRate, 523.25, 0.34),
      ),
      start,
    );
  }
  return out;
}

List<double> _retroBeep() {
  final out = _buffer(2.4);
  for (var n = 0; n < 6; n++) {
    final start = 0.12 + n * 0.38;
    final freq = n.isEven ? 740.0 : 987.77;
    _mix(
      out,
      List<double>.generate((0.2 * sampleRate).round(), (i) {
        final t = i / sampleRate;
        return _env(t, 0.004, 0.06) * 0.34 * _square(t, freq);
      }),
      start,
    );
  }
  return out;
}

List<double> _marimbaWake() {
  final out = _buffer(2.8);
  const notes = [392.0, 493.88, 587.33, 783.99, 587.33, 783.99, 987.77];
  for (var n = 0; n < notes.length; n++) {
    _mix(
      out,
      List<double>.generate(
        (0.55 * sampleRate).round(),
        (i) => _pluck(i / sampleRate, notes[n], 0.13),
      ),
      0.1 + n * 0.36,
    );
  }
  return out;
}

List<double> _radarSweep() {
  final out = _buffer(3.0);
  for (var n = 0; n < 3; n++) {
    final start = 0.05 + n * 0.95;
    _mix(
      out,
      List<double>.generate((0.9 * sampleRate).round(), (i) {
        final t = i / sampleRate;
        final progress = t / 0.9;
        final freq = 420 + 1180 * math.sin(math.pi * progress);
        final trem = 0.75 + 0.25 * math.sin(2 * math.pi * 7 * t);
        return _env(t, 0.02, 0.35) *
            trem *
            0.42 *
            math.sin(2 * math.pi * freq * t);
      }),
      start,
    );
  }
  return out;
}

List<double> _harpArpeggio() {
  final out = _buffer(3.0);
  const notes = [392.0, 493.88, 587.33, 783.99, 987.77, 783.99, 587.33, 493.88];
  for (var n = 0; n < notes.length; n++) {
    _mix(
      out,
      List<double>.generate(
        (0.7 * sampleRate).round(),
        (i) => _pluck(i / sampleRate, notes[n], 0.22) * 0.8,
      ),
      0.08 + n * 0.34,
    );
  }
  return out;
}

List<double> _solarBurst() {
  final out = _buffer(2.8);
  const chord = [523.25, 659.25, 783.99, 1046.5];
  for (final freq in chord) {
    _mix(
      out,
      List<double>.generate((2.6 * sampleRate).round(), (i) {
        final t = i / sampleRate;
        final rise = math.min(1.0, t / 0.6);
        final shimmer =
            0.6 + 0.4 * math.sin(2 * math.pi * 5.5 * t + freq / 200);
        return _env(t, 0.08, 1.1) *
            rise *
            shimmer *
            0.16 *
            math.sin(2 * math.pi * freq * t);
      }),
      0.05,
    );
  }
  return out;
}

List<double> _softPiano() {
  final out = _buffer(3.0);
  const notes = [261.63, 329.63, 392.0, 523.25, 392.0, 329.63];
  for (var n = 0; n < notes.length; n++) {
    _mix(
      out,
      List<double>.generate((0.8 * sampleRate).round(), (i) {
        final t = i / sampleRate;
        return _pluck(t, notes[n], 0.3) *
            (0.55 + 0.12 * math.sin(2 * math.pi * 3 * t));
      }),
      0.1 + n * 0.45,
    );
  }
  return out;
}

List<double> _cosmicPulse() {
  final out = _buffer(3.0);
  for (var n = 0; n < 5; n++) {
    final start = 0.08 + n * 0.56;
    _mix(
      out,
      List<double>.generate((0.5 * sampleRate).round(), (i) {
        final t = i / sampleRate;
        final pulse = math.exp(-18 * ((t - 0.12).abs()));
        return pulse *
            (0.28 * math.sin(2 * math.pi * 110 * t) +
                0.20 * math.sin(2 * math.pi * 660 * t) +
                0.12 * math.sin(2 * math.pi * 1320 * t));
      }),
      start,
    );
  }
  return out;
}

final List<(String id, String label, List<double> Function() render)> _tones = [
  ('classic_chime', 'Classic Chime', _classicChime),
  ('digital_clock', 'Digital Clock', _digitalClock),
  ('morning_bell', 'Morning Bell', _morningBell),
  ('retro_beep', 'Retro Beep', _retroBeep),
  ('marimba_wake', 'Marimba Wake', _marimbaWake),
  ('radar_sweep', 'Radar Sweep', _radarSweep),
  ('harp_arpeggio', 'Harp Arpeggio', _harpArpeggio),
  ('solar_burst', 'Solar Burst', _solarBurst),
  ('soft_piano', 'Soft Piano', _softPiano),
  ('cosmic_pulse', 'Cosmic Pulse', _cosmicPulse),
];

void _writeWav(String path, List<double> samples) {
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (clamped * 32767).round(), Endian.little);
  }
  File(path).writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  final root = Directory.current;
  if (!File('${root.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
    stderr.writeln('Run this script from the Larm repository root.');
    exitCode = 1;
    return;
  }
  final assetDir = Directory('${root.path}/assets/sounds');
  final rawDir = Directory('${root.path}/android/app/src/main/res/raw');
  for (final dir in [assetDir, rawDir]) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  for (final (id, label, render) in _tones) {
    final samples = render();
    // Short edge guard so playback does not click.
    for (var i = 0; i < 200 && i < samples.length; i++) {
      samples[i] *= i / 200;
      samples[samples.length - 1 - i] *= i / 200;
    }
    final file = '$id.wav';
    _writeWav('${assetDir.path}${Platform.pathSeparator}$file', samples);
    _writeWav('${rawDir.path}${Platform.pathSeparator}$file', samples);
    stdout.writeln('Generated $label ($file)');
  }
}
