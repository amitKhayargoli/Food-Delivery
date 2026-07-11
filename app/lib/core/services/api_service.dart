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
        'username': ?username,
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
        'username': ?username,
        'phone': ?phone,
        'email': ?email,
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
          'description': ?description,
          'logo_url': ?logoUrl,
          'cover_image_url': ?coverImageUrl,
          'open_time': ?openTime,
          'close_time': ?closeTime,
          'cuisine_type': ?cuisineType,
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
          'estimated_prep_time': ?estimatedPrepTime,
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
          'reason': ?reason,
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

  /// Cancel an order (customer action).
  /// If a rider is assigned, releases them and sends push notifications
  /// to both the rider and the restaurant owner.
  Future<void> cancelOrder({
    required String orderId,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/orders/$orderId/cancel',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Decline an assigned order (rider action).
  /// Clears the assignment, resets is_on_delivery, and notifies the owner.
  Future<void> declineOrder({
    required String orderId,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/orders/$orderId/decline',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
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
  //  Restaurants API
  // ──────────────────────────────────────────────

  /// Fetch all approved restaurants with their menu items
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

  // ──────────────────────────────────────────────
  //  Customer Orders API
  // ──────────────────────────────────────────────

  /// Create a new order from the customer's cart
  Future<Map<String, dynamic>> createOrder({
    required String restaurantId,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double deliveryFee,
    required double total,
    Map<String, dynamic>? deliveryAddress,
    String? deliveryNotes,
    required String paymentMethod,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/orders',
        data: {
          'restaurant_id': restaurantId,
          'items': items,
          'subtotal': subtotal,
          'delivery_fee': deliveryFee,
          'total': total,
          'delivery_address': ?deliveryAddress,
          'delivery_notes': ?deliveryNotes,
          'payment_method': paymentMethod,
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

  /// Fetch a single order by ID for the authenticated user
  Future<Map<String, dynamic>?> getOrderById({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/orders/$orderId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['order'] as Map<String, dynamic>?;
    } on DioException {
      return null;
    }
  }

  /// Fetch orders for the authenticated customer
  Future<List<Map<String, dynamic>>> getMyOrders({required String token}) async {
    try {
      final response = await _dio.get(
        '/orders/my',
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

  /// Fetch completed/cancelled order history for the authenticated customer
  Future<OrderHistoryResponse> getOrderHistory({
    required String token,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        '/orders/history',
        queryParameters: {'limit': limit, 'offset': offset},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final orders = (data['orders'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final total = (data['total'] as num?)?.toInt() ?? orders.length;
      return OrderHistoryResponse(orders: orders, total: total);
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Search orders by order number (owner-facing)
  Future<List<Map<String, dynamic>>> searchOrders({required String query, required String token}) async {
    try {
      final response = await _dio.get(
        '/orders/search',
        queryParameters: {'q': query},
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

  /// Fetch assigned delivery jobs for the authenticated delivery boy
  Future<List<Map<String, dynamic>>> getMyDeliveryJobs({required String token}) async {
    try {
      final response = await _dio.get(
        '/orders/delivery/my',
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

  /// Mark an order as picked up
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
  //  Restaurant Management API
  // ──────────────────────────────────────────────

  /// Update the authenticated owner's restaurant profile
  Future<Map<String, dynamic>> updateRestaurant({
    required Map<String, dynamic> data,
    required String token,
  }) async {
    try {
      final response = await _dio.put(
        '/restaurant-applications/my',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final result = response.data as Map<String, dynamic>;
      if (result['application'] != null) {
        return result['application'] as Map<String, dynamic>;
      }
      return result;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch all orders (admin only). Returns delivered orders with
  /// restaurant names, rider info, and delivery photo status.
  Future<List<Map<String, dynamic>>> getAllOrders({required String token}) async {
    try {
      final response = await _dio.get(
        '/orders/admin/all',
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

  /// Mark an order as delivered by the delivery boy.
  /// Optionally captures GPS snapshot + delivery photo as proof.
  Future<Map<String, dynamic>> markOrderAsDelivered({
    required String orderId,
    required String token,
    String? deliveryPhotoUrl,
    double? deliveryLat,
    double? deliveryLng,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/deliver',
        data: {
          'delivery_photo_url': ?deliveryPhotoUrl,
          'delivery_lat': ?deliveryLat,
          'delivery_lng': ?deliveryLng,
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

  /// Fetch delivery earnings summary for the authenticated rider.
  Future<Map<String, dynamic>> getRiderStats({required String token}) async {
    try {
      final response = await _dio.get(
        '/orders/delivery/stats',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['stats'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Add a rider note to an order (delivery boy -> customer)
  Future<void> addRiderNote({
    required String orderId,
    required String note,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/orders/$orderId/rider-note',
        data: {'rider_note': note},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Delivery Location Sync API
  // ──────────────────────────────────────────────

  /// Save the user's pinned delivery location to the backend profile.
  Future<void> saveDeliveryLocation({
    required String address,
    required double latitude,
    required double longitude,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/profile/delivery-location',
        data: {
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch the user's delivery location from the backend profile.
  /// Returns null if none has been saved yet.
  Future<Map<String, dynamic>?> fetchDeliveryLocation({
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/profile/delivery-location',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['delivery_location'] as Map<String, dynamic>?;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Profile API
  // ──────────────────────────────────────────────

  /// Update the user's profile (username, email, phone).
  Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? email,
    String? phone,
    required String token,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;

      final response = await _dio.patch(
        '/profile',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['user'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Update the user's avatar URL on the backend profile.
  Future<void> updateAvatarUrl({
    required String avatarUrl,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/profile/avatar',
        data: {'avatar_url': avatarUrl},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Rider Location API
  // ──────────────────────────────────────────────

  /// Ping the rider's current GPS location to the backend.
  Future<void> updateRiderLocation({
    required double latitude,
    required double longitude,
    double? heading,
    double? speed,
    double? accuracy,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/location/ping',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'heading': ?heading,
          'speed': ?speed,
          'accuracy': ?accuracy,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Mark the rider as offline.
  Future<void> updateRiderOffline({required String token}) async {
    try {
      await _dio.patch(
        '/location/offline',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch nearby online riders within a radius (used by owner dashboard).
  Future<List<Map<String, dynamic>>> getNearbyRiders({
    required double latitude,
    required double longitude,
    int limit = 5,
    double radiusKm = 10,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/location/nearby',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          'limit': limit,
          'radius_km': radiusKm,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final riders = data['riders'] as List<dynamic>? ?? [];
      return riders.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch a specific rider's current location.
  Future<Map<String, dynamic>?> getRiderLocation({
    required String riderId,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/location/rider/$riderId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['location'] as Map<String, dynamic>?;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Rider Ratings API
  // ──────────────────────────────────────────────

  /// Submit a rating for a rider after delivery.
  Future<void> submitRiderRating({
    required String orderId,
    required String riderId,
    required int rating,
    String? comment,
    required String token,
  }) async {
    try {
      await _dio.post(
        '/ratings',
        data: {
          'order_id': orderId,
          'rider_id': riderId,
          'rating': rating,
          'comment': ?comment,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch the authenticated user's ratings.
  Future<List<Map<String, dynamic>>> getMyRatings({required String token}) async {
    try {
      final response = await _dio.get(
        '/ratings/my',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final ratings = data['ratings'] as List<dynamic>? ?? [];
      return ratings.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Dispatch Analytics & Admin Rider Management API
  // ──────────────────────────────────────────────

  /// Get dispatch analytics for the authenticated owner's restaurant.
  /// Returns avg_dispatch_time_s, avg_arrival_time_s, avg_rider_rating, etc.
  Future<Map<String, dynamic>> getDispatchAnalytics({required String token}) async {
    try {
      final response = await _dio.get(
        '/dispatch/analytics',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['analytics'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Get all delivery riders with performance stats (admin only).
  Future<List<Map<String, dynamic>>> getAllRiders({required String token}) async {
    try {
      final response = await _dio.get(
        '/dispatch/admin/riders',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final riders = data['riders'] as List<dynamic>? ?? [];
      return riders.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Create a new delivery boy account (admin only).
  Future<Map<String, dynamic>> createRider({
    required String username,
    String? email,
    required String phone,
    required String password,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/dispatch/admin/riders',
        data: {
          'username': username,
          'email': ?email,
          'phone': phone,
          'password': password,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['rider'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Get rider leaderboard by deliveries completed (admin only).
  Future<List<Map<String, dynamic>>> getRiderPerformance({required String token}) async {
    try {
      final response = await _dio.get(
        '/dispatch/admin/performance',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final leaderboard = data['leaderboard'] as List<dynamic>? ?? [];
      return leaderboard.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch dispatch log entries for a specific order.
  Future<List<Map<String, dynamic>>> getDispatchLogForOrder({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/dispatch/log/$orderId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final logs = data['logs'] as List<dynamic>? ?? [];
      return logs.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Coupons & Promotions API
  // ──────────────────────────────────────────────

  /// Validate a coupon code and get discount info.
  Future<CouponValidateResponse> validateCoupon({
    required String code,
    required double orderTotal,
    String? restaurantId,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/coupons/validate',
        data: {
          'code': code,
          'order_total': orderTotal,
          'restaurant_id': ?restaurantId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return CouponValidateResponse.fromJson(data);
    } on DioException catch (e) {
      final message = _extractError(e);
      return CouponValidateResponse(
        valid: false,
        error: message,
      );
    }
  }

  /// Fetch coupons for the authenticated owner's restaurant (or all for admin).
  Future<List<Map<String, dynamic>>> getMyCoupons({required String token}) async {
    try {
      final response = await _dio.get(
        '/coupons/my',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final coupons = data['coupons'] as List<dynamic>? ?? [];
      return coupons.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Create a new coupon.
  Future<Map<String, dynamic>> createCoupon({
    required String code,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    double? maxDiscountCap,
    int? usageLimit,
    String? expiresAt,
    String? description,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/coupons',
        data: {
          'code': code,
          'discount_type': discountType,
          'discount_value': discountValue,
          'min_order_amount': ?minOrderAmount,
          'max_discount_cap': ?maxDiscountCap,
          'usage_limit': ?usageLimit,
          'expires_at': ?expiresAt,
          'description': ?description,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['coupon'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Delete a coupon.
  Future<void> deleteCoupon({
    required String couponId,
    required String token,
  }) async {
    try {
      await _dio.delete(
        '/coupons/$couponId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch available (active, non-expired) coupons for a customer's cart.
  /// Returns coupons scoped to [restaurantId] + global coupons.
  Future<List<Map<String, dynamic>>> getAvailableCoupons({
    required String restaurantId,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/coupons/available',
        queryParameters: {'restaurant_id': restaurantId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final coupons = data['coupons'] as List<dynamic>? ?? [];
      return coupons.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Apply a coupon (increment usage count after successful order).
  Future<void> applyCoupon({
    required String couponId,
    required String token,
  }) async {
    try {
      await _dio.post(
        '/coupons/$couponId/apply',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Home Suggestions API
  // ──────────────────────────────────────────────

  /// Fetch time-of-day curated home screen data.
  /// Returns restaurants filtered by meal type, greeting, and favorite cuisines.
  Future<HomeSuggestionsResponse> getHomeSuggestions({
    String? timeOfDay,
    String? token,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (timeOfDay != null) queryParams['time_of_day'] = timeOfDay;

      final options = Options(
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      final response = await _dio.get(
        '/home/suggestions',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        options: options,
      );
      final data = response.data as Map<String, dynamic>;
      return HomeSuggestionsResponse.fromJson(data);
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Order Problem / Refund API
  // ──────────────────────────────────────────────

  /// Submit a problem report for an order.
  Future<Map<String, dynamic>> submitProblem({
    required String orderId,
    required String issueType,
    String? description,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/problems',
        data: {
          'order_id': orderId,
          'issue_type': issueType,
          'description': ?description,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['problem'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch problem reports for the authenticated user.
  Future<List<Map<String, dynamic>>> getMyProblems({required String token}) async {
    try {
      final response = await _dio.get(
        '/problems/my',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final problems = data['problems'] as List<dynamic>? ?? [];
      return problems.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch problem report for a specific order.
  Future<Map<String, dynamic>?> getProblemByOrder({
    required String orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/problems/order/$orderId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['problem'] as Map<String, dynamic>?;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch problem reports for the owner's restaurant.
  Future<List<Map<String, dynamic>>> getRestaurantProblems({required String token}) async {
    try {
      final response = await _dio.get(
        '/problems/restaurant',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final problems = data['problems'] as List<dynamic>? ?? [];
      return problems.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Update a problem report's status (APPROVED / REJECTED).
  Future<void> updateProblemStatus({
    required String problemId,
    required String status,
    String? adminNote,
    double? refundAmount,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/problems/$problemId/status',
        data: {
          'status': status,
          'admin_note': ?adminNote,
          'refund_amount': ?refundAmount,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Personalized Suggestions API
  // ──────────────────────────────────────────────

  /// Fetch personalized home-screen data based on the user's order history.
  /// Returns favorite restaurants, recent restaurants, and most ordered items.
  Future<Map<String, dynamic>> getPersonalizedSuggestions({required String token}) async {
    try {
      final response = await _dio.get(
        '/home/personalized',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Surprise Me API
  // ──────────────────────────────────────────────

  /// Fetch a random restaurant the user hasn't ordered from yet.
  /// Returns the restaurant (or null if none available) and whether
  /// the user has tried every restaurant.
  Future<Map<String, dynamic>> getSurpriseMe({required String token}) async {
    try {
      final response = await _dio.get(
        '/home/surprise-me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Token Refresh API
  // ──────────────────────────────────────────────

  /// Exchange the current (possibly expired) token for a fresh JWT.
  /// The backend verifies the user still exists and is active before issuing
  /// a new token.
  Future<String?> refreshToken(String currentToken) async {
    try {
      final response = await _dio.post('/auth/refresh', data: {
        'token': currentToken,
      });
      final data = response.data as Map<String, dynamic>;
      return data['token'] as String?;
    } on DioException {
      return null;
    }
  }

  // ──────────────────────────────────────────────
  //  Customer Support Chat API
  // ──────────────────────────────────────────────

  /// Create a new support conversation.
  Future<Map<String, dynamic>> createSupportConversation({
    required String subject,
    String? orderId,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/support/conversations',
        data: {
          'subject': subject,
          'order_id': ?orderId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['conversation'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch support conversations for the authenticated user.
  Future<List<Map<String, dynamic>>> getMySupportConversations({required String token}) async {
    try {
      final response = await _dio.get(
        '/support/conversations',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final conversations = data['conversations'] as List<dynamic>? ?? [];
      return conversations.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch all support conversations (admin only).
  Future<List<Map<String, dynamic>>> getAllSupportConversations({
    required String token,
    String? status,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (status != null) queryParams['status'] = status;

      final response = await _dio.get(
        '/support/conversations/admin/all',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final conversations = data['conversations'] as List<dynamic>? ?? [];
      return conversations.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Fetch messages for a support conversation.
  Future<List<Map<String, dynamic>>> getSupportMessages({
    required String conversationId,
    required String token,
  }) async {
    try {
      final response = await _dio.get(
        '/support/conversations/$conversationId/messages',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final messages = data['messages'] as List<dynamic>? ?? [];
      return messages.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Send a message in a support conversation.
  Future<Map<String, dynamic>> sendSupportMessage({
    required String conversationId,
    required String message,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/support/conversations/$conversationId/messages',
        data: {'message': message},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['msg'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Close a support conversation.
  Future<void> closeSupportConversation({
    required String conversationId,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/support/conversations/$conversationId/close',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  In-App Notifications API
  // ──────────────────────────────────────────────

  /// Fetch in-app notifications for the authenticated user.
  /// Optionally filter by `role` so users with multiple roles only see
  /// notifications relevant to their currently active role.
  Future<Map<String, dynamic>> getNotifications({
    required String token,
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
    String? role,
  }) async {
    try {
      final response = await _dio.get(
        '/notifications',
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (unreadOnly) 'unread': 'true',
          'role': ?role,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Mark a single notification as read.
  Future<void> markNotificationAsRead({
    required String notificationId,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/notifications/$notificationId/read',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Mark all notifications as read.
  Future<void> markAllNotificationsAsRead({required String token}) async {
    try {
      await _dio.post(
        '/notifications/read-all',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Restaurant Reviews API
  // ──────────────────────────────────────────────

  /// Submit a review for a restaurant.
  Future<Map<String, dynamic>> submitRestaurantReview({
    required String restaurantId,
    required int rating,
    String? comment,
    List<String>? images,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/reviews',
        data: {
          'restaurant_id': restaurantId,
          'rating': rating,
          'comment': ?comment,
          if (images != null && images.isNotEmpty) 'images': images,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['review'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Get all reviews for a restaurant.
  Future<List<Map<String, dynamic>>> getRestaurantReviews({
    required String restaurantId,
  }) async {
    try {
      final response = await _dio.get('/reviews/restaurant/$restaurantId');
      final data = response.data as Map<String, dynamic>;
      final reviews = data['reviews'] as List<dynamic>? ?? [];
      return reviews.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Get reviews submitted by the authenticated user.
  Future<List<Map<String, dynamic>>> getMyRestaurantReviews({required String token}) async {
    try {
      final response = await _dio.get(
        '/reviews/my',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      final reviews = data['reviews'] as List<dynamic>? ?? [];
      return reviews.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Get reviews for the owner's restaurant.
  Future<Map<String, dynamic>> getOwnerRestaurantReviews({required String token}) async {
    try {
      final response = await _dio.get(
        '/reviews/owner',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Update a review.
  Future<Map<String, dynamic>> updateRestaurantReview({
    required String reviewId,
    int? rating,
    String? comment,
    List<String>? images,
    required String token,
  }) async {
    try {
      final response = await _dio.put(
        '/reviews/$reviewId',
        data: {
          'rating': ?rating,
          'comment': ?comment,
          'images': ?images,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as Map<String, dynamic>;
      return data['review'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Delete a review.
  Future<void> deleteRestaurantReview({
    required String reviewId,
    required String token,
  }) async {
    try {
      await _dio.delete(
        '/reviews/$reviewId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Rider Application API
  // ──────────────────────────────────────────────

  /// Submit a delivery partner (rider) application.
  Future<RiderApplicationResponse> submitRiderApplication({
    required String fullName,
    required String email,
    required String phone,
    required String vehicleType,
    required String vehicleNumber,
    required String licenseUrl,
    String? profileImageUrl,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/riders/apply',
        data: {
          'full_name': fullName,
          'email': email,
          'phone': phone,
          'vehicle_type': vehicleType,
          'vehicle_number': vehicleNumber,
          'license_url': licenseUrl,
          'profile_image_url': ?profileImageUrl,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final data = response.data as Map<String, dynamic>;
      final app = data['application'] as Map<String, dynamic>?;
      return RiderApplicationResponse(
        message: data['message'] as String? ?? '',
        applicationId: app?['id'] as String?,
        status: app?['status'] as String? ?? 'PENDING',
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  // ──────────────────────────────────────────────
  //  Rider Application Admin API
  // ──────────────────────────────────────────────

  /// Get all rider applications (admin only).
  Future<List<Map<String, dynamic>>> getAllRiderApplications({required String token}) async {
    try {
      final response = await _dio.get(
        '/riders/apply',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data as List<dynamic>? ?? [];
      return data.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Update a rider application's status (APPROVED / REJECTED).
  Future<void> updateRiderApplicationStatus({
    required String applicationId,
    required String status,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/riders/apply/$applicationId/status',
        data: {'status': status},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
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

class OrderHistoryResponse {
  final List<Map<String, dynamic>> orders;
  final int total;

  OrderHistoryResponse({required this.orders, required this.total});
}

/// Response from POST /api/coupons/validate
class CouponValidateResponse {
  final bool valid;
  final String? error;
  final String? couponId;
  final String? code;
  final String? discountType;
  final double? discountValue;
  final double? discountAmount;
  final double? maxDiscountCap;
  final String? description;

  CouponValidateResponse({
    required this.valid,
    this.error,
    this.couponId,
    this.code,
    this.discountType,
    this.discountValue,
    this.discountAmount,
    this.maxDiscountCap,
    this.description,
  });

  factory CouponValidateResponse.fromJson(Map<String, dynamic> json) {
    if (json['valid'] != true) {
      return CouponValidateResponse(
        valid: false,
        error: json['error'] as String? ?? 'Invalid coupon',
      );
    }
    final c = json['coupon'] as Map<String, dynamic>? ?? {};
    return CouponValidateResponse(
      valid: true,
      couponId: c['id'] as String?,
      code: c['code'] as String?,
      discountType: c['discount_type'] as String?,
      discountValue: (c['discount_value'] as num?)?.toDouble(),
      discountAmount: (c['discount_amount'] as num?)?.toDouble(),
      maxDiscountCap: (c['max_discount_cap'] as num?)?.toDouble(),
      description: c['description'] as String?,
    );
  }
}

class RiderApplicationResponse {
  final String message;
  final String? applicationId;
  final String status;

  RiderApplicationResponse({
    required this.message,
    this.applicationId,
    required this.status,
  });
}

/// Response from GET /api/home/suggestions
class HomeSuggestionsResponse {
  final String timeOfDay;
  final String greeting;
  final List<Map<String, dynamic>> suggestedRestaurants;
  final List<Map<String, dynamic>> allRestaurants;
  final List<String> favoriteCuisines;

  HomeSuggestionsResponse({
    required this.timeOfDay,
    required this.greeting,
    required this.suggestedRestaurants,
    required this.allRestaurants,
    required this.favoriteCuisines,
  });

  factory HomeSuggestionsResponse.fromJson(Map<String, dynamic> json) {
    return HomeSuggestionsResponse(
      timeOfDay: json['time_of_day'] as String? ?? 'afternoon',
      greeting: json['greeting'] as String? ?? 'Hello! 👋',
      suggestedRestaurants: (json['suggested_restaurants'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>(),
      allRestaurants: (json['all_restaurants'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>(),
      favoriteCuisines: (json['favorite_cuisines'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
