/// Platform abstractions for native platforms (uses dart:io)

import 'dart:io';
import 'dart:typed_data';

bool get isLinuxPlatform => Platform.isLinux;
bool get isIOSPlatform => Platform.isIOS;

/// Voice messages are only supported on Linux (ALSA FFI) and Android (record + just_audio)
/// Other platforms disabled until properly tested:
/// - iOS: record works but playback format (CAF) has issues
/// - macOS: needs testing
/// - Windows: needs just_audio_windows dependency
bool get isVoiceSupported => Platform.isLinux || Platform.isAndroid;

/// Wrapper around dart:io File
class PlatformFile {
  final File _file;
  PlatformFile(String path) : _file = File(path);

  Future<bool> exists() => _file.exists();
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
  Future<void> writeAsBytes(List<int> bytes) => _file.writeAsBytes(bytes);
  Future<void> delete() async => _file.delete();
  Future<int> length() => _file.length();
  int lengthSync() => _file.lengthSync();
}
