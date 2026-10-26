import 'dart:math' as math;
import 'dart:typed_data';

/// Which speaker(s) a test tone plays on.
enum ToneChannel {
  left('Left channel', 'Did you hear it from the left speaker only?'),
  right('Right channel', 'Did you hear it from the right speaker only?'),
  both('Both channels', 'Did you hear it from both speakers equally?');

  const ToneChannel(this.title, this.question);

  /// Card heading, e.g. "Left channel".
  final String title;

  /// What the user is asked after the tone plays.
  final String question;
}

/// Builds a 16-bit stereo PCM WAV containing a sine tone on the chosen
/// channel(s) and silence on the other. A short fade in/out avoids clicks
/// that could be mistaken for a crackling speaker.
Uint8List buildToneWav({
  required ToneChannel channel,
  int sampleRate = 44100,
  double seconds = 1.5,
  double frequencyHz = 440,
  double amplitude = 0.4,
  double fadeSeconds = 0.03,
}) {
  const channels = 2;
  const bytesPerSample = 2;
  final frames = (sampleRate * seconds).round();
  final dataSize = frames * channels * bytesPerSample;

  final bytes = Uint8List(44 + dataSize);
  final d = ByteData.sublistView(bytes);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[offset + i] = s.codeUnitAt(i);
    }
  }

  // RIFF/WAVE header, PCM.
  ascii(0, 'RIFF');
  d.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little); // PCM
  d.setUint16(22, channels, Endian.little);
  d.setUint32(24, sampleRate, Endian.little);
  d.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  d.setUint16(32, channels * bytesPerSample, Endian.little);
  d.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  d.setUint32(40, dataSize, Endian.little);

  final fadeFrames = (sampleRate * fadeSeconds).round();
  final peak = (amplitude.clamp(0.0, 1.0) * 32767).round();
  final left = channel != ToneChannel.right;
  final right = channel != ToneChannel.left;

  for (var i = 0; i < frames; i++) {
    final env = i < fadeFrames
        ? i / fadeFrames
        : (i > frames - fadeFrames ? (frames - i) / fadeFrames : 1.0);
    final sample = (math.sin(2 * math.pi * frequencyHz * i / sampleRate) * peak * env).round();
    final o = 44 + i * channels * bytesPerSample;
    d.setInt16(o, left ? sample : 0, Endian.little);
    d.setInt16(o + 2, right ? sample : 0, Endian.little);
  }
  return bytes;
}
