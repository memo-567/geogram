/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// TFLite service with conditional imports for web compatibility
/// Uses native implementation on mobile/desktop, stub on web

export 'tflite_service_stub.dart'
    if (dart.library.io) 'tflite_service_native.dart';
