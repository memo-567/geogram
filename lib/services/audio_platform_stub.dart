/// Stub platform abstractions for web where dart:io is not available

import 'dart:typed_data';

bool get isLinuxPlatform => false;
bool get isIOSPlatform => false;

/// Voice messages are not supported on web (browser-dependent, unreliable)
bool get isVoiceSupported => false;

/// Stub File class for web
class PlatformFile {
  final String path;
  PlatformFile(this.path);

  Future<bool> exists() async => false;
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<void> writeAsBytes(List<int> bytes) async {}
  Future<void> delete() async {}
  Future<int> length() async => 0;
  int lengthSync() => 0;
}
