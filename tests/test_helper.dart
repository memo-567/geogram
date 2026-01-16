import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

// Manual mock for OrtValue
class MockOrtValue implements OrtValue {
  final List<double> _data;
  MockOrtValue(this._data);

  @override
  Future<List<dynamic>> asList() async => _data;

  @override
  Future<Uint8List> asRawData() async => Uint8List(0);
  
  @override
  Object? get value => _data;

  @override
  void dispose() {}

  @override
  int get size => _data.length;

  @override
  List<int> get shape => [1, _data.length];

  @override
  OnnxValueType get type => OnnxValueType.tensor;
}

// Manual mock for OrtSession
class MockOrtSession implements OrtSession {
  @override
  Future<Map<String, OrtValue>> run(Map<String, OrtValue> inputs) async {
    // Return a dummy OrtValue with some data
    return {'output': MockOrtValue([1.0, 2.0, 3.0])};
  }
    @override
  Future<void> close() async {}

  @override
  int get address => 123;
}

class TestHelper {
  static void setUp() {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mock path_provider
    const MethodChannel channelPathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channelPathProvider,
            (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return Directory.systemTemp.createTempSync().path;
      }
      return null;
    });

    // Mock record
    const MethodChannel channelRecord =
        MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channelRecord, (MethodCall methodCall) async {
      if (methodCall.method == 'create') {
        return 'recorder_1';
      }
      return null;
    });

    // Mock onnxruntime
    OrtTesting.mockPlatform(
      createSession: (String path, OrtSessionOptions? options) {
        return MockOrtSession();
      },
    );
  }
}
