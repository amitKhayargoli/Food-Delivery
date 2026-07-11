import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import '../../providers/auth_provider.dart';

/// Dio interceptor that automatically refreshes an expired JWT token
/// when a 401 response is received.
///
/// On a 401:
/// 1. Reads the current token from [FlutterSecureStorage]
/// 2. Calls POST /auth/refresh with the old token
/// 3. If successful: saves the new token, updates the request Authorization
///    header, and retries the request
/// 4. If failed: passes the original 401 error through so the calling code
///    can handle it (e.g. redirect to login)
///
/// Uses [QueuedInterceptorsWrapper] so that if multiple requests fail with
/// 401 simultaneously, only one refresh call is made and all pending
/// requests are retried once the new token is available.
class AuthInterceptor extends QueuedInterceptorsWrapper {
  final FlutterSecureStorage _secureStorage;
  final Dio _dio;

  /// Whether a token refresh is currently in progress.
  bool _isRefreshing = false;

  /// Requests that are waiting for the refresh to complete so they can retry.
  final List<_RetryRequest> _pendingRetries = [];

  AuthInterceptor({
    required FlutterSecureStorage secureStorage,
    required Dio dio,
  })  : _secureStorage = secureStorage,
        _dio = dio;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    // The current codebase passes tokens manually via Options.headers,
    // so we don't need to add the header here. The interceptor only
    // handles 401 error responses.
    handler.next(options);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only handle 401 errors
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Don't try to refresh if the failing request itself is the refresh call
    if (err.requestOptions.path.contains('/auth/refresh')) {
      return handler.next(err);
    }

    // Don't try to refresh for auth endpoints that don't need it
    // (send-otp, verify-otp, etc. don't use tokens)
    if (_isAuthEndpoint(err.requestOptions.path)) {
      return handler.next(err);
    }

    final requestOptions = err.requestOptions;

    // If we're already refreshing, queue this request to retry later
    if (_isRefreshing) {
      _pendingRetries.add(_RetryRequest(
        options: requestOptions,
        handler: handler,
      ));
      return;
    }

    _isRefreshing = true;

    try {
      final oldToken = await _secureStorage.read(key: 'jwt_token');
      if (oldToken == null) {
        _isRefreshing = false;
        _flushPendingRetries(null);
        return handler.next(err);
      }

      final response = await _dio.post(
        '/auth/refresh',
        data: {'token': oldToken},
      );

      final data = response.data as Map<String, dynamic>;
      final newToken = data['token'] as String?;

      if (newToken == null || newToken.isEmpty) {
        _isRefreshing = false;
        _flushPendingRetries(null);
        return handler.next(err);
      }

      // Save the new token
      await _secureStorage.write(key: 'jwt_token', value: newToken);

      // Update the token in GetIt-registered services (if available)
      _updateAuthProviderToken(newToken);

      // Retry the original request with the new token
      requestOptions.headers['Authorization'] = 'Bearer $newToken';
      final retryResponse = await _dio.fetch(requestOptions);
      handler.resolve(retryResponse);

      // Retry all pending requests with the new token
      _flushPendingRetries(newToken);
    } catch (_) {
      // Refresh failed — pass the original error through
      _flushPendingRetries(null);
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }

  /// Retry all queued requests with the new token, or pass their errors through.
  void _flushPendingRetries(String? newToken) {
    final retries = List<_RetryRequest>.from(_pendingRetries);
    _pendingRetries.clear();

    for (final retry in retries) {
      if (newToken != null) {
        retry.options.headers['Authorization'] = 'Bearer $newToken';
        _dio
            .fetch(retry.options)
            .then((response) => retry.handler.resolve(response))
            .catchError((error) => retry.handler.next(error as DioException));
      } else {
        retry.handler.next(
          DioException(
            requestOptions: retry.options,
            type: DioExceptionType.badResponse,
          ),
        );
      }
    }
  }

  bool _isAuthEndpoint(String path) {
    return path.contains('/auth/send-otp') ||
        path.contains('/auth/verify-otp') ||
        path.contains('/auth/check-availability') ||
        path.contains('/auth/google') ||
        path.contains('/auth/register') ||
        path.contains('/auth/login');
  }

  /// Try to update the AuthProvider's token in GetIt so the in-memory
  /// state stays in sync with the refreshed token from secure storage.
  void _updateAuthProviderToken(String newToken) {
    try {
      final provider = GetIt.instance<AuthProvider>(instanceName: 'auth_provider');
      provider.setToken(newToken);
    } catch (_) {
      // GetIt not available — token is already saved to secure storage
      // and will be picked up on next API call or app launch
    }
  }
}

/// Bundles a failed request's options and handler for later retry.
class _RetryRequest {
  final RequestOptions options;
  final ErrorInterceptorHandler handler;

  _RetryRequest({required this.options, required this.handler});
}
