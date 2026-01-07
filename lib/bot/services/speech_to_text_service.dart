/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Speech-to-text service using Whisper
/// Uses conditional imports to provide stub on web where FFI is unavailable
export 'speech_to_text_service_stub.dart'
    if (dart.library.io) 'speech_to_text_service_native.dart';
