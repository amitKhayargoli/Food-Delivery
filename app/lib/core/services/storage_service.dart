import 'dart:io';

import 'package:dio/dio.dart';

class StorageService {
  final Dio _dio;

  StorageService(this._dio);

  static const String _panBucket = 'pan-certificates';
  static const String _imagesBucket = 'restaurant-images';
  static const String _foodImagesBucket = 'food-images';
  static const String _avatarBucket = 'avatar-images';
  static const String _deliveryPhotoBucket = 'delivery-photos';
  static const String _reviewImagesBucket = 'review-images';
  static const String _riderDocumentsBucket = 'rider-documents';

  /// Upload a PAN certificate image through the backend proxy using multipart.
  /// Returns the public URL of the uploaded file.
  Future<String> uploadPanCertificate({
    required String filePath,
    required String userId,
    required String token,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileName = filePath.split('/').last;
    final formData = FormData.fromMap({
      'bucket': _panBucket,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final response = await _dio.post(
      '/upload',
      data: formData,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        // Don't set Content-Type manually — Dio sets multipart/form-data with boundary
      ),
    );

    final data = response.data as Map<String, dynamic>;
    return data['url'] as String;
  }

  /// Upload a restaurant cover image through the backend proxy using multipart.
  /// Returns the public URL of the uploaded file.
  Future<String> uploadCoverImage({
    required String filePath,
    required String userId,
    required String token,
  }) async {
    return _uploadToBucket(_imagesBucket, filePath, token);
  }

  /// Upload a food item image to the food-images bucket.
  /// Returns the public URL of the uploaded file.
  Future<String> uploadFoodImage({
    required String filePath,
    required String token,
  }) async {
    return _uploadToBucket(_foodImagesBucket, filePath, token);
  }

  /// Upload a profile/avatar image to the avatar-images bucket.
  /// Returns the public URL of the uploaded file.
  Future<String> uploadProfilePicture({
    required String filePath,
    required String token,
  }) async {
    return _uploadToBucket(_avatarBucket, filePath, token);
  }

  /// Upload a delivery photo to the delivery-photos bucket.
  Future<String> uploadDeliveryPhoto({
    required String filePath,
    required String token,
  }) async {
    return _uploadToBucket(_deliveryPhotoBucket, filePath, token);
  }

  /// Upload a review image to the review-images bucket.
  Future<String> uploadReviewImage({
    required String filePath,
    required String token,
  }) async {
    return _uploadToBucket(_reviewImagesBucket, filePath, token);
  }

  /// Upload a rider document (e.g. driver's license) to the rider-documents bucket.
  Future<String> uploadRiderDocument({
    required String filePath,
    required String token,
  }) async {
    return _uploadToBucket(_riderDocumentsBucket, filePath, token);
  }

  /// Generic upload to any allowed bucket.
  Future<String> _uploadToBucket(
    String bucket,
    String filePath,
    String token,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileName = filePath.split('/').last;
    final formData = FormData.fromMap({
      'bucket': bucket,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final response = await _dio.post(
      '/upload',
      data: formData,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
      ),
    );

    final data = response.data as Map<String, dynamic>;
    return data['url'] as String;
  }
}
