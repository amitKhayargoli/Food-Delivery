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

  /// Authenticate with Google via the backend — exchanges a Google idToken
  /// for a backend-issued JWT signed with JWT_SECRET.
  Future<GoogleAuthResponse> googleAuth({
    required String idToken,
  }) async {
    try {
      final response = await _dio.post('/auth/google', data: {
        'idToken': idToken,
      });

      final data = response.data as Map<String, dynamic>;
      return GoogleAuthResponse(
        token: data['token'] as String? ?? '',
        tempToken: data['temp_token'] as String?,
        user: data['user'] != null
            ? UserData.fromJson(data['user'] as Map<String, dynamic>)
            : null,
        requiresProfileCompletion:
            data['requires_profile_completion'] as bool? ?? false,
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Complete the Google-linked user profile with phone/username,
  /// exchanging the temp_token for a full backend JWT.
  Future<GoogleCompleteProfileResponse> completeGoogleProfile({
    required String tempToken,
    required String phone,
    required String username,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/complete-profile',
        data: {
          'phone': phone,
          'username': username,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $tempToken'},
        ),
      );

      final data = response.data as Map<String, dynamic>;
      return GoogleCompleteProfileResponse(
        token: data['token'] as String? ?? '',
        user: data['user'] != null
            ? UserData.fromJson(data['user'] as Map<String, dynamic>)
            : null,
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

  // ──────────────────────────────────────────────
  //  Orders API
  // ──────────────────────────────────────────────

  /// Fetch all orders for the authenticated owner's restaurant
  Future<List<Map<String, dynamic>>> getRestaurantOrders({required String token}) async {
    try {
      final response = await _dio.get(
        '/orders/restaurant',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final orders = data['orders'] as List<dynamic>? ?? [];
      return orders.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Accept a pending order
  Future<Map<String, dynamic>> acceptOrder({
    required String orderId,
    required String token,
    int? estimatedPrepTime,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/accept',
        data: {
          if (estimatedPrepTime != null) 'estimated_prep_time': estimatedPrepTime,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Reject a pending order
  Future<Map<String, dynamic>> rejectOrder({
    required String orderId,
    required String token,
    String? reason,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/reject',
        data: {
          if (reason != null) 'reason': reason,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Mark an order as being prepared
  Future<Map<String, dynamic>> markOrderAsPreparing({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/preparing',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Mark an order as ready for pickup/delivery
  Future<Map<String, dynamic>> markOrderAsReady({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/ready',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Get all available delivery boys
  Future<List<Map<String, dynamic>>> getDeliveryBoys({required String token}) async {
    try {
      final response = await _dio.get(
        '/orders/delivery-boys',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final boys = data['delivery_boys'] as List<dynamic>? ?? [];
      return boys.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Menu Items API
  // ──────────────────────────────────────────────

  /// Fetch all menu items for the authenticated owner's restaurant
  Future<List<Map<String, dynamic>>> getMenuItems({required String token}) async {
    try {
      final response = await _dio.get(
        '/menu',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      return items.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Create a new menu item
  Future<Map<String, dynamic>> createMenuItem({
    required Map<String, dynamic> data,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/menu',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final result = response.data as Map<String, dynamic>;
      return result['item'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Update an existing menu item
  Future<Map<String, dynamic>> updateMenuItem({
    required String itemId,
    required Map<String, dynamic> data,
    required String token,
  }) async {
    try {
      final response = await _dio.put(
        '/menu/$itemId',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final result = response.data as Map<String, dynamic>;
      return result['item'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Delete a menu item
  Future<void> deleteMenuItem({
    required String itemId,
    required String token,
  }) async {
    try {
      await _dio.delete(
        '/menu/$itemId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Toggle menu item availability
  Future<Map<String, dynamic>> toggleMenuItemAvailability({
    required String itemId,
    required bool isAvailable,
    required String token,
  }) async {
    try {
      final response = await _dio.patch(
        '/menu/$itemId/availability',
        data: {'is_available': isAvailable},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final result = response.data as Map<String, dynamic>;
      return result['item'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Mark an order as picked up / out for delivery
  Future<Map<String, dynamic>> markOrderAsPickedUp({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/picked-up',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Mark an order as delivered
  Future<Map<String, dynamic>> markOrderAsDelivered({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/delivered',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch a single order by ID
  Future<Map<String, dynamic>> getOrderById({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/orders/$orderId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Assign a delivery boy to an order
  Future<Map<String, dynamic>> assignDeliveryBoy({
    required String orderId,
    required String deliveryBoyId,
    required String token,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/assign',
        data: {'delivery_boy_id': deliveryBoyId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Restaurant Profile API (Owner Manage Restaurant)
  // ──────────────────────────────────────────────

  /// Fetch the current owner's approved restaurant profile
  Future<Map<String, dynamic>?> getMyRestaurantProfile({required String token}) async {
    try {
      final response = await _dio.get(
        '/restaurant-applications/my/profile',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['restaurant'] as Map<String, dynamic>?;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Update the owner's restaurant profile
  Future<Map<String, dynamic>> updateRestaurantProfile({
    required Map<String, dynamic> data,
    required String token,
  }) async {
    try {
      final response = await _dio.put(
        '/restaurant-applications/my/profile',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final result = response.data as Map<String, dynamic>;
      return result['restaurant'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Toggle whether the restaurant is accepting orders
  Future<bool> toggleAcceptingOrders({
    required bool isAccepting,
    required String token,
  }) async {
    try {
      final response = await _dio.patch(
        '/restaurant-applications/my/accepting-orders',
        data: {'is_accepting_orders': isAccepting},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['is_accepting_orders'] as bool? ?? isAccepting;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Public Restaurants API
  // ──────────────────────────────────────────────

  /// Fetch all approved restaurants (public, no auth needed)
  Future<List<Map<String, dynamic>>> getRestaurants() async {
    try {
      final response = await _dio.get('/restaurants');
      final data = response.data as Map<String, dynamic>;
      final restaurants = data['restaurants'] as List<dynamic>? ?? [];
      return restaurants.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch menu items for a specific restaurant (public, no auth needed)
  Future<List<Map<String, dynamic>>> getRestaurantMenu(String restaurantId) async {
    try {
      final response = await _dio.get('/restaurants/$restaurantId/menu');
      final data = response.data as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      return items.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch a single restaurant by ID (public, no auth needed)
  Future<Map<String, dynamic>?> getRestaurantById(String restaurantId) async {
    try {
      final response = await _dio.get('/restaurants/$restaurantId');
      final data = response.data as Map<String, dynamic>;
      return data['restaurant'] as Map<String, dynamic>?;
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

class GoogleAuthResponse {
  final String token;
  final String? tempToken;
  final UserData? user;
  final bool requiresProfileCompletion;

  GoogleAuthResponse({
    required this.token,
    this.tempToken,
    this.user,
    required this.requiresProfileCompletion,
  });
}

class GoogleCompleteProfileResponse {
  final String token;
  final UserData? user;

  GoogleCompleteProfileResponse({
    required this.token,
    this.user,
  });
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
