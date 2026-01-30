/*
 * Copyright (c) 田梓萱[小草林] 2021-2024.
 * All Rights Reserved.
 * All codes are protected by China's regulations on the protection of computer software, and infringement must be investigated.
 * 版权所有 (c) 田梓萱[小草林] 2021-2024.
 * 所有代码均受中国《计算机软件保护条例》保护，侵权必究.
 */

import "dart:convert";
import "dart:ffi";
import "dart:io";

import "package:ffi/ffi.dart";
import "package:flutter/foundation.dart";
import "package:path_provider/path_provider.dart";
import "package:whisper_flutter_new/bean/_models.dart";
import "package:whisper_flutter_new/bean/whisper_dto.dart";
import "package:whisper_flutter_new/download_model.dart";
import "package:whisper_flutter_new/whisper_bindings_generated.dart";

export "package:whisper_flutter_new/bean/_models.dart";
export "package:whisper_flutter_new/download_model.dart" show WhisperModel;

/// Parameters for isolate FFI work - must be top-level for serialization
class _IsolateParams {
  final String requestString;
  final String? customLibraryPath;

  const _IsolateParams({
    required this.requestString,
    this.customLibraryPath,
  });
}

/// Top-level function for isolate execution - required for proper serialization
/// This function runs entirely in the isolate, including library loading and FFI calls
Map<String, dynamic> _executeInIsolate(_IsolateParams params) {
  print('[WHISPER_ISOLATE] Starting FFI work in isolate');

  // Open library inside isolate
  DynamicLibrary lib;
  if (Platform.isAndroid || Platform.isLinux) {
    if (params.customLibraryPath != null) {
      print('[WHISPER_ISOLATE] Opening custom library: ${params.customLibraryPath}');
      lib = DynamicLibrary.open(params.customLibraryPath!);
    } else {
      print('[WHISPER_ISOLATE] Opening libwhisper.so');
      lib = DynamicLibrary.open("libwhisper.so");
    }
  } else {
    print('[WHISPER_ISOLATE] Using process library');
    lib = DynamicLibrary.process();
  }

  print('[WHISPER_ISOLATE] Calling FFI request...');
  // Perform FFI call
  final Pointer<Utf8> data = params.requestString.toNativeUtf8();
  final Pointer<Char> res = WhisperFlutterBindings(lib).request(data.cast<Char>());
  print('[WHISPER_ISOLATE] FFI request completed');

  final Map<String, dynamic> result = json.decode(
    res.cast<Utf8>().toDartString(),
  ) as Map<String, dynamic>;

  try {
    malloc.free(data);
    malloc.free(res);
  } catch (_) {}

  print('[WHISPER_ISOLATE] Returning result from isolate');
  return result;
}

/// Entry point of whisper_flutter_plus
class Whisper {
  /// [model] is required
  /// [modelDir] is path where downloaded model will be stored.
  /// Default to library directory
  const Whisper({required this.model, this.modelDir, this.downloadHost});

  /// model used for transcription
  final WhisperModel model;

  /// override of model storage path
  final String? modelDir;

  // override of model download host
  final String? downloadHost;

  /// Custom library path for runtime-loaded libraries (e.g., F-Droid builds)
  static String? _customLibraryPath;

  /// Set custom path to libwhisper.so for runtime loading
  /// Used when the library is not bundled (e.g., F-Droid builds)
  static void setLibraryPath(String path) {
    _customLibraryPath = path;
  }

  /// Check if the whisper library is available (either bundled or custom path set)
  static bool isLibraryAvailable() {
    if (_customLibraryPath != null) {
      return File(_customLibraryPath!).existsSync();
    }
    // For bundled library, try to open it
    if (Platform.isAndroid || Platform.isLinux) {
      try {
        DynamicLibrary.open("libwhisper.so");
        return true;
      } catch (_) {
        return false;
      }
    }
    return true; // Other platforms use process()
  }

  Future<String> _getModelDir() async {
    if (modelDir != null) {
      return modelDir!;
    }
    final Directory libraryDirectory = Platform.isAndroid
        ? await getApplicationSupportDirectory()
        : await getLibraryDirectory();
    return libraryDirectory.path;
  }

  Future<void> _initModel() async {
    final String modelDir = await _getModelDir();
    final File modelFile = File(model.getPath(modelDir));
    final bool isModelExist = modelFile.existsSync();
    if (isModelExist) {
      if (kDebugMode) {
        debugPrint("Use existing model ${model.modelName}");
      }
      return;
    } else {
      await downloadModel(
          model: model, destinationPath: modelDir, downloadHost: downloadHost);
    }
  }

  Future<Map<String, dynamic>> _request({
    required WhisperRequestDto whisperRequest,
  }) async {
    if (model != WhisperModel.none) {
      await _initModel();
    }

    // Use compute() with top-level function for proper isolate serialization
    // This ensures FFI work truly runs in a separate thread
    final params = _IsolateParams(
      requestString: whisperRequest.toRequestString(),
      customLibraryPath: _customLibraryPath,
    );

    final result = await compute(_executeInIsolate, params);

    if (kDebugMode) {
      debugPrint("Result =  $result");
    }
    return result;
  }

  /// Transcribe audio file to text
  Future<WhisperTranscribeResponse> transcribe({
    required TranscribeRequest transcribeRequest,
  }) async {
    final String modelDir = await _getModelDir();
    final Map<String, dynamic> result = await _request(
      whisperRequest: TranscribeRequestDto.fromTranscribeRequest(
        transcribeRequest,
        model.getPath(modelDir),
      ),
    );
    if (kDebugMode) {
      debugPrint("Transcribe request $result");
    }
    if (result["text"] == null) {
      if (kDebugMode) {
        debugPrint('Transcribe Exception ${result['message']}');
      }
      throw Exception(result["message"]);
    }
    return WhisperTranscribeResponse.fromJson(result);
  }

  /// Get whisper version
  Future<String?> getVersion() async {
    final Map<String, dynamic> result = await _request(
      whisperRequest: const VersionRequest(),
    );

    final WhisperVersionResponse response = WhisperVersionResponse.fromJson(
      result,
    );
    return response.message;
  }
}
