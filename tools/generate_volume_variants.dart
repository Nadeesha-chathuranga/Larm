/// Generates 10%-step gain variants of every bundled alarm tone.
///
/// Run from the repository root:
///   dart run tools/generate_volume_variants.dart
///
/// Android notification channels own their sound, so the in-app slider cannot
/// change the OS alarm stream. These `*_vNN.wav` files let a channel be
/// recreated with a quieter copy of the selected tone, making the Settings
/// volume slider actually control scheduled alarm/timer loudness. Variants are
/// written only to Android `res/raw`; previews keep using the full-quality
/// originals in `assets/sounds`.
library;

import 'dart:io';
import 'dart:typed_data';

const int levels = 10;
const int outputSampleRate = 11025;

void main() => generateVolumeVariants();

/// Writes 10%-step gain variants of every bundled tone into Android res/raw.
void generateVolumeVariants() {
  final root = Directory.current;
  if (!File('${root.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
    stderr.writeln('Run this script from the Larm repository root.');
    exitCode = 1;
    return;
  }

  final source = Directory('${root.path}/assets/sounds');
  final rawDir = Directory('${root.path}/android/app/src/main/res/raw');
  if (!rawDir.existsSync()) rawDir.createSync(recursive: true);

  final originals = source
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.wav'))
      .where((f) => !RegExp(r'_v(10|20|30|40|50|60|70|80|90|100)\.wav$')
          .hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (originals.isEmpty) {
    stderr.writeln('No source WAVs found in assets/sounds.');
    exitCode = 1;
    return;
  }

  for (final file in originals) {
    final id = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.wav$'), '');
    final samples = _readWav(file.readAsBytesSync());
    final downsampled = <double>[];
    for (var i = 0; i + 1 < samples.length; i += 2) {
      downsampled.add((samples[i] + samples[i + 1]) / 2);
    }
    for (var level = 1; level <= levels; level++) {
      final bucket = level * 10;
      final gain = bucket / 100;
      final scaled = downsampled
          .map((s) => (s * gain).clamp(-1.0, 1.0).toDouble())
          .toList(growable: false);
      File('${rawDir.path}${Platform.pathSeparator}${id}_v$bucket.wav')
          .writeAsBytesSync(_writeWav(scaled));
    }
  }

  stdout.writeln(
    'Wrote ${originals.length * levels} gain variants to ${rawDir.path}.',
  );
}

List<double> _readWav(List<int> bytes) {
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.take(4)) != 'RIFF' ||
      String.fromCharCodes(bytes.skip(8).take(4)) != 'WAVE') {
    throw FormatException('Not a RIFF/WAVE file');
  }

  var fmt = <int>[];
  var data = <int>[];
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.skip(offset).take(4));
    final size = bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    final start = offset + 8;
    final end = start + size;
    if (end > bytes.length) break;
    if (id == 'fmt ') {
      fmt = bytes.sublist(start, end);
    } else if (id == 'data') {
      data = bytes.sublist(start, end);
    }
    offset = end + (size.isOdd ? 1 : 0);
  }

  if (fmt.length < 16) throw const FormatException('WAV has no fmt chunk');
  final channels = fmt[2] | (fmt[3] << 8);
  final bits = fmt[14] | (fmt[15] << 8);
  if (channels != 1 || bits != 16) {
    throw FormatException('Expected 16-bit mono WAV, got $bits-bit/$channels-ch');
  }

  final samples = List<double>.filled(data.length ~/ 2, 0.0);
  for (var i = 0; i < samples.length; i++) {
    final o = i * 2;
    final raw = data[o] | (data[o + 1] << 8);
    samples[i] = (raw > 32767 ? raw - 65536 : raw) / 32768.0;
  }
  return samples;
}

List<int> _writeWav(List<double> samples) {
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
  bytes.setUint32(24, outputSampleRate, Endian.little);
  bytes.setUint32(28, outputSampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i].clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
