/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Unified API response wrapper for all transports.
 */

import '../connection/transport_message.dart';
import 'api_error.dart';

/// Generic API response wrapper
///
/// Wraps [TransportResult] and provides typed data access.
class ApiResponse<T> {
  final bool success;
  final T? data;
  final ApiError? error;
  final int? statusCode;
  final String? transportUsed;
  final Duration? latency;
  final bool wasQueued;

  /// Raw response data (before parsing)
  final dynamic rawData;

  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.statusCode,
    this.transportUsed,
    this.latency,
    this.wasQueued = false,
    this.rawData,
  });

  /// Create from TransportResult with optional data parser
  factory ApiResponse.fromTransportResult(
    TransportResult result, {
    T Function(dynamic json)? fromJson,
  }) {
    if (!result.success) {
      return ApiResponse<T>(
        success: false,
        error: ApiError(
          message: result.error ?? 'Unknown error',
          statusCode: result.statusCode,
          transportUsed: result.transportUsed,
        ),
        statusCode: result.statusCode,
        transportUsed: result.transportUsed,
        latency: result.latency,
        wasQueued: result.wasQueued,
      );
    }

    // Parse response data if parser provided
    T? parsedData;
    if (fromJson != null && result.responseData != null) {
      try {
        parsedData = fromJson(result.responseData);
      } catch (e) {
        return ApiResponse<T>(
          success: false,
          error: ApiError(
            message: 'Failed to parse response: $e',
            transportUsed: result.transportUsed,
          ),
          statusCode: result.statusCode,
          transportUsed: result.transportUsed,
          latency: result.latency,
          rawData: result.responseData,
        );
      }
    } else if (result.responseData is T) {
      parsedData = result.responseData as T;
    }

    return ApiResponse<T>(
      success: true,
      data: parsedData,
      statusCode: result.statusCode,
      transportUsed: result.transportUsed,
      latency: result.latency,
      wasQueued: result.wasQueued,
      rawData: result.responseData,
    );
  }

  /// Create a successful response
  factory ApiResponse.ok(T data, {String? transportUsed, Duration? latency}) {
    return ApiResponse<T>(
      success: true,
      data: data,
      statusCode: 200,
      transportUsed: transportUsed,
      latency: latency,
    );
  }

  /// Create an error response
  factory ApiResponse.error(ApiError error, {String? transportUsed}) {
    return ApiResponse<T>(
      success: false,
      error: error,
      statusCode: error.statusCode,
      transportUsed: transportUsed,
    );
  }

  /// Create a queued response (will be delivered later)
  factory ApiResponse.queued({String? transportUsed}) {
    return ApiResponse<T>(
      success: true,
      wasQueued: true,
      transportUsed: transportUsed,
    );
  }

  /// Get data or throw if not successful
  T get dataOrThrow {
    if (!success) {
      throw error ?? ApiError(message: 'Unknown error');
    }
    if (data == null) {
      throw ApiError(message: 'Response data is null');
    }
    return data!;
  }

  /// Get data or return default value
  T dataOr(T defaultValue) => data ?? defaultValue;

  /// Map the data to a different type
  ApiResponse<R> map<R>(R Function(T data) mapper) {
    if (!success || data == null) {
      return ApiResponse<R>(
        success: success,
        error: error,
        statusCode: statusCode,
        transportUsed: transportUsed,
        latency: latency,
        wasQueued: wasQueued,
        rawData: rawData,
      );
    }

    try {
      return ApiResponse<R>(
        success: true,
        data: mapper(data!),
        statusCode: statusCode,
        transportUsed: transportUsed,
        latency: latency,
        wasQueued: wasQueued,
        rawData: rawData,
      );
    } catch (e) {
      return ApiResponse<R>(
        success: false,
        error: ApiError(message: 'Failed to map response: $e'),
        statusCode: statusCode,
        transportUsed: transportUsed,
        latency: latency,
        rawData: rawData,
      );
    }
  }

  /// Chain another API call if this one succeeded
  Future<ApiResponse<R>> then<R>(
    Future<ApiResponse<R>> Function(T data) next,
  ) async {
    if (!success || data == null) {
      return ApiResponse<R>(
        success: false,
        error: error ?? ApiError(message: 'Previous call failed'),
        statusCode: statusCode,
        transportUsed: transportUsed,
      );
    }
    return next(data!);
  }

  @override
  String toString() {
    if (success) {
      if (wasQueued) {
        return 'ApiResponse(queued via $transportUsed)';
      }
      return 'ApiResponse(success via $transportUsed, '
          'status: $statusCode, latency: ${latency?.inMilliseconds}ms)';
    }
    return 'ApiResponse(failed: ${error?.message})';
  }
}

/// List response with pagination support
class ApiListResponse<T> extends ApiResponse<List<T>> {
  final int? total;
  final int? offset;
  final int? limit;
  final bool hasMore;

  const ApiListResponse({
    required super.success,
    super.data,
    super.error,
    super.statusCode,
    super.transportUsed,
    super.latency,
    super.wasQueued,
    super.rawData,
    this.total,
    this.offset,
    this.limit,
    this.hasMore = false,
  });

  /// Create from TransportResult with list parser
  factory ApiListResponse.fromTransportResult(
    TransportResult result, {
    required T Function(dynamic json) itemFromJson,
    String listKey = 'items',
  }) {
    if (!result.success) {
      return ApiListResponse<T>(
        success: false,
        error: ApiError(
          message: result.error ?? 'Unknown error',
          statusCode: result.statusCode,
          transportUsed: result.transportUsed,
        ),
        statusCode: result.statusCode,
        transportUsed: result.transportUsed,
        latency: result.latency,
      );
    }

    final rawData = result.responseData;
    List<T>? items;
    int? total;
    int? offset;
    int? limit;
    bool hasMore = false;

    if (rawData is Map<String, dynamic>) {
      // Try to extract list from common keys
      final listData = rawData[listKey] ?? rawData['data'] ?? rawData['results'];
      if (listData is List) {
        items = listData.map((e) => itemFromJson(e)).toList();
      }
      total = rawData['total'] as int? ?? rawData['count'] as int?;
      offset = rawData['offset'] as int?;
      limit = rawData['limit'] as int?;
      hasMore = rawData['hasMore'] as bool? ??
                rawData['has_more'] as bool? ??
                (total != null && items != null && (offset ?? 0) + items.length < total);
    } else if (rawData is List) {
      items = rawData.map((e) => itemFromJson(e)).toList();
    }

    return ApiListResponse<T>(
      success: true,
      data: items ?? [],
      statusCode: result.statusCode,
      transportUsed: result.transportUsed,
      latency: result.latency,
      rawData: rawData,
      total: total,
      offset: offset,
      limit: limit,
      hasMore: hasMore,
    );
  }

  int get count => data?.length ?? 0;
  bool get isEmpty => count == 0;
  bool get isNotEmpty => count > 0;
}
