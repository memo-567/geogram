/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * API error types for unified error handling across all transports.
 */

/// API error with optional status code and details
class ApiError implements Exception {
  final String message;
  final int? statusCode;
  final String? transportUsed;
  final dynamic details;

  const ApiError({
    required this.message,
    this.statusCode,
    this.transportUsed,
    this.details,
  });

  /// Network/transport error (couldn't reach device)
  factory ApiError.network(String message, {String? transportUsed}) {
    return ApiError(
      message: message,
      transportUsed: transportUsed,
    );
  }

  /// Timeout error
  factory ApiError.timeout({String? transportUsed}) {
    return ApiError(
      message: 'Request timed out',
      transportUsed: transportUsed,
    );
  }

  /// Not found error (404)
  factory ApiError.notFound(String resource) {
    return ApiError(
      message: '$resource not found',
      statusCode: 404,
    );
  }

  /// Unauthorized error (401/403)
  factory ApiError.unauthorized({String? message}) {
    return ApiError(
      message: message ?? 'Unauthorized',
      statusCode: 401,
    );
  }

  /// Server error (5xx)
  factory ApiError.server(String message, {int? statusCode}) {
    return ApiError(
      message: message,
      statusCode: statusCode ?? 500,
    );
  }

  /// Validation error (400)
  factory ApiError.validation(String message, {dynamic details}) {
    return ApiError(
      message: message,
      statusCode: 400,
      details: details,
    );
  }

  /// Device offline (queued for later)
  factory ApiError.offline(String callsign) {
    return ApiError(
      message: 'Device $callsign is offline',
    );
  }

  bool get isNetworkError => statusCode == null;
  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isServerError => statusCode != null && statusCode! >= 500;
  bool get isValidationError => statusCode == 400;

  @override
  String toString() {
    final parts = <String>['ApiError: $message'];
    if (statusCode != null) parts.add('status=$statusCode');
    if (transportUsed != null) parts.add('via=$transportUsed');
    return parts.join(', ');
  }
}
