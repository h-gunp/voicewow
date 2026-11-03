import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class WavAudio {
  const WavAudio({required this.samples, required this.sampleRate});
  final Float64List samples;
  final int sampleRate;
  double get duration => samples.length / sampleRate;
}

/// Decode a standard RIFF/WAVE file, averaging channels to mono. Android TTS
/// commonly produces PCM16; PCM8/24/32 and IEEE float32/64 are also supported.
/// Unknown, compressed or truncated files are rejected rather than guessed.
WavAudio decodeWav(Uint8List bytes) {
  if (bytes.length < 12) throw const FormatException('음성 파일이 너무 짧아요.');
  final data = ByteData.sublistView(bytes);
  String tag(int offset) =>
      ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true);
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('PCM WAV 음성 파일이 필요해요.');
  }
  final declaredEnd = data.getUint32(4, Endian.little) + 8;
  if (declaredEnd > bytes.length) {
    throw const FormatException('음성 파일이 완전히 저장되지 않았어요.');
  }
  var format = 0, channels = 0, sampleRate = 0, bits = 0, blockAlign = 0;
  int? audioOffset, audioLength;
  for (var at = 12; at + 8 <= declaredEnd;) {
    final id = tag(at),
        size = data.getUint32(at + 4, Endian.little),
        body = at + 8;
    if (body + size > declaredEnd) {
      throw const FormatException('WAV 데이터의 길이가 맞지 않아요.');
    }
    if (id == 'fmt ') {
      if (size < 16) throw const FormatException('WAV 형식을 확인하지 못했어요.');
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      blockAlign = data.getUint16(body + 12, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
      if (format == 0xfffe && size >= 40) {
        format = data.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data' && audioOffset == null) {
      audioOffset = body;
      audioLength = size;
    }
    at = body + size + (size.isOdd ? 1 : 0);
  }
  if (audioOffset == null ||
      audioLength == null ||
      channels < 1 ||
      channels > 32 ||
      sampleRate < 8000 ||
      sampleRate > 192000) {
    throw const FormatException('WAV 음성 정보를 확인하지 못했어요.');
  }
  final integerPcm = format == 1 && [8, 16, 24, 32].contains(bits);
  final floatPcm = format == 3 && [32, 64].contains(bits);
  if (!integerPcm && !floatPcm) {
    throw const FormatException('압축하지 않은 PCM WAV 파일이 필요해요.');
  }
  final sampleBytes = bits ~/ 8;
  if (blockAlign != channels * sampleBytes || audioLength % blockAlign != 0) {
    throw const FormatException('WAV 음성 프레임의 길이가 맞지 않아요.');
  }
  final frameCount = audioLength ~/ blockAlign;
  if (frameCount / sampleRate > 30) {
    throw const FormatException('연습 음성은 30초 이하로 준비해 주세요.');
  }
  final samples = Float64List(frameCount);
  double sampleAt(int offset) {
    if (format == 3) {
      final value = bits == 32
          ? data.getFloat32(offset, Endian.little)
          : data.getFloat64(offset, Endian.little);
      return value.isFinite ? value : 0;
    }
    switch (bits) {
      case 8:
        return (data.getUint8(offset) - 128) / 128;
      case 16:
        return data.getInt16(offset, Endian.little) / 32768;
      case 24:
        var value =
            data.getUint8(offset) |
            data.getUint8(offset + 1) << 8 |
            data.getUint8(offset + 2) << 16;
        if ((value & 0x800000) != 0) value -= 0x1000000;
        return value / 8388608;
      case 32:
        return data.getInt32(offset, Endian.little) / 2147483648;
      default:
        throw const FormatException('지원하지 않는 WAV 샘플 형식이에요.');
    }
  }

  for (var i = 0; i < frameCount; i++) {
    var total = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      total += sampleAt(audioOffset + i * blockAlign + channel * sampleBytes);
    }
    samples[i] = total / channels;
  }
  return WavAudio(samples: samples, sampleRate: sampleRate);
}

/// Little-endian mono PCM16 samples from the native recorder stream.
Float64List decodePcm16(Uint8List bytes) {
  if (bytes.length.isOdd) {
    throw const FormatException('PCM16 음성 데이터의 길이가 맞지 않아요.');
  }
  final view = ByteData.sublistView(bytes),
      samples = Float64List(bytes.length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = view.getInt16(i * 2, Endian.little) / 32768;
  }
  return samples;
}

Uint8List encodeWav(List<double> samples, int sampleRate) {
  if (sampleRate < 8000 || sampleRate > 192000) {
    throw ArgumentError('지원하지 않는 샘플 레이트예요.');
  }
  final bytes = Uint8List(44 + samples.length * 2),
      data = ByteData.sublistView(bytes);
  void tag(int offset, String text) {
    bytes.setRange(offset, offset + text.length, ascii.encode(text));
  }

  tag(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final value = samples[i].isFinite
        ? samples[i].clamp(-1.0, 1.0).toDouble()
        : 0.0;
    data.setInt16(
      44 + i * 2,
      math.max(-32768, math.min(32767, (value * 32767).round())),
      Endian.little,
    );
  }
  return bytes;
}
