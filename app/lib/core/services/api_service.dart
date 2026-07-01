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
          if (deliveryAddress != null) 'delivery_address': deliveryAddress,
          if (deliveryNotes != null) 'delivery_notes': deliveryNotes,
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

  /// Toggle whether the restaurant is accepting new orders
  Future<void> toggleAcceptingOrders({
    required bool isAccepting,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/restaurant-applications/my/accepting-orders',
        data: {'is_accepting_orders': isAccepting},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final message = _extractError(e);
      throw ApiException(message);
    }
  }

  /// Toggle automatic delivery boy assignment (auto-dispatch).
  /// When enabled, the nearest available rider is automatically assigned
  /// when an order is marked as Ready.
  Future<void> toggleAutoDispatch({
    required bool enabled,
    required String token,
  }) async {
    try {
      await _dio.patch(
        '/restaurant-applications/my/auto-dispatch',
        data: {'auto_dispatch_enabled': enabled},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
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
          if (deliveryPhotoUrl != null) 'delivery_photo_url': deliveryPhotoUrl,
          if (deliveryLat != null) 'delivery_lat': deliveryLat,
          if (deliveryLng != null) 'delivery_lng': deliveryLng,
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
  //  Profile Avatar API
  // ──────────────────────────────────────────────

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
          if (heading != null) 'heading': heading,
          if (speed != null) 'speed': speed,
          if (accuracy != null) 'accuracy': accuracy,
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
          if (comment != null) 'comment': comment,
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
          if (email != null) 'email': email,
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

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
