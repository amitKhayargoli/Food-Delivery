import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  /// Send OTP to the given phone number
  Future<OtpSendResponse> sendOtp({
    required String phone,
    required String purpose,
  }) async {
    try {
      final response = await _dio.post('/auth/send-otp', data: {
        'phone': phone,
        'purpose': purpose,
      });

      final data = response.data as Map<String, dynamic>;
      return OtpSendResponse(
        message: data['message'] as String? ?? '',
        expiresAt: data['expires_at'] as String?,
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Verify the OTP entered by the user
  Future<OtpVerifyResponse> verifyOtp({
    required String phone,
    required String otp,
    String? username,
  }) async {
    try {
      final response = await _dio.post('/auth/verify-otp', data: {
        'phone': phone,
        'otp': otp,
        if (username != null) 'username': username,
      });

      final data = response.data as Map<String, dynamic>;
      return OtpVerifyResponse(
        message: data['message'] as String? ?? '',
        token: data['token'] as String?,
        user: data['user'] != null
            ? UserData.fromJson(data['user'] as Map<String, dynamic>)
            : null,
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Check if username, phone, or email are already taken
  Future<AvailabilityResponse> checkAvailability({
    String? username,
    String? phone,
    String? email,
  }) async {
    try {
      final response = await _dio.post('/auth/check-availability', data: {
        if (username != null) 'username': username,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
      });

      final data = response.data as Map<String, dynamic>;
      final taken = data['taken'] as Map<String, dynamic>? ?? {};
      return AvailabilityResponse(
        available: data['available'] as bool? ?? true,
        usernameTaken: taken['username'] as bool? ?? false,
        phoneTaken: taken['phone'] as bool? ?? false,
        emailTaken: taken['email'] as bool? ?? false,
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Resend OTP (alias for sendOtp)
  Future<OtpSendResponse> resendOtp({
    required String phone,
    required String purpose,
  }) async {
    return sendOtp(phone: phone, purpose: purpose);
  }

  /// Submit a restaurant owner application
  Future<RestaurantApplicationResponse> submitRestaurantApplication({
    required String restaurantName,
    required String ownerName,
    required String phone,
    required String email,
    required String address,
    required String panNumber,
    required String panCertificateUrl,
    String? description,
    String? logoUrl,
    String? coverImageUrl,
    String? openTime,
    String? closeTime,
    String? cuisineType,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/restaurant-applications',
        data: {
          'restaurant_name': restaurantName,
          'owner_name': ownerName,
          'phone': phone,
          'email': email,
          'address': address,
          'pan_number': panNumber,
          'pan_certificate_url': panCertificateUrl,
          if (description != null) 'description': description,
          if (logoUrl != null) 'logo_url': logoUrl,
          if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
          if (openTime != null) 'open_time': openTime,
          if (closeTime != null) 'close_time': closeTime,
          if (cuisineType != null) 'cuisine_type': cuisineType,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final data = response.data as Map<String, dynamic>;
      final app = data['application'] as Map<String, dynamic>?;
      return RestaurantApplicationResponse(
        message: data['message'] as String? ?? '',
        applicationId: app?['id'] as String?,
        status: app?['status'] as String? ?? 'PENDING',
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch the current user's restaurant application status
  Future<Map<String, dynamic>?> getMyApplication({required String token}) async {
    try {
      final response = await _dio.get(
        '/restaurant-applications/my',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['application'] as Map<String, dynamic>?;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Extract error message from DioException
  String _extractError(DioException e) {
    if (e.response?.data is Map<String, dynamic>) {
      final data = e.response!.data as Map<String, dynamic>;
      if (data.containsKey('error')) {
        return data['error'] as String;
      }
    }
    return e.message ?? 'An unexpected error occurred';
  }
}

class OtpSendResponse {
  final String message;
  final String? expiresAt;

  OtpSendResponse({required this.message, this.expiresAt});
}

class OtpVerifyResponse {
  final String message;
  final String? token;
  final UserData? user;

  OtpVerifyResponse({required this.message, this.token, this.user});

  bool get isSuccess => token != null && token!.isNotEmpty;
}

class UserData {
  final String id;
  final String username;
  final String email;
  final String phone;
  final String role;

  UserData({
    required this.id,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
  });

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'USER',
    );
  }
}

class AvailabilityResponse {
  final bool available;
  final bool usernameTaken;
  final bool phoneTaken;
  final bool emailTaken;

  AvailabilityResponse({
    required this.available,
    required this.usernameTaken,
    required this.phoneTaken,
    required this.emailTaken,
  });
}

class RestaurantApplicationResponse {
  final String message;
  final String? applicationId;
  final String status;

  RestaurantApplicationResponse({
    required this.message,
    this.applicationId,
    required this.status,
  });
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
