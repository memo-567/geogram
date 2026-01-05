/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Stub for flutter_pty on web platform.
 */

/// Stub Pty class for web platform
class Pty {
  static Pty start(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnsupportedError('Pty is not supported on web');
  }

  Stream<List<int>> get output => throw UnsupportedError('Pty is not supported on web');
  Future<int> get exitCode => throw UnsupportedError('Pty is not supported on web');

  void write(List<int> data) {
    throw UnsupportedError('Pty is not supported on web');
  }

  void kill([int signal = 15]) {
    throw UnsupportedError('Pty is not supported on web');
  }
}
