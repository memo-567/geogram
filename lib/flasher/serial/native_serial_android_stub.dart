import 'dart:async';
import 'dart:typed_data';

/// Stub implementation for Android USB Serial
///
/// This is used when running in pure Dart CLI (not Flutter).
/// The actual implementation is in native_serial_android.dart which
/// requires Flutter's services package.
class NativeSerialAndroid {
  static Future<void> initialize() async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Stream<(String, bool)> get permissionChanges =>
      throw UnsupportedError('Android USB serial is only available in Flutter');

  static Future<List<Map<String, dynamic>>> listDevices() async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<bool> hasPermission(String deviceName) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<bool> requestPermission(String deviceName) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<bool> open(String deviceName, {int baudRate = 115200}) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<void> close(String deviceName) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<Uint8List> read(String deviceName,
      {int maxBytes = 4096, int timeoutMs = 1000}) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<int> write(String deviceName, Uint8List data) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<bool> setDTR(String deviceName, bool value) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<bool> setRTS(String deviceName, bool value) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<bool> setBaudRate(String deviceName, int baudRate) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }

  static Future<void> flush(String deviceName) async {
    throw UnsupportedError('Android USB serial is only available in Flutter');
  }
}
