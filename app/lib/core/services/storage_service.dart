import 'dart:io';

import 'package:dio/dio.dart';

class StorageService {
  final Dio _dio;

  StorageService(this._dio);

  static const String _panBucket = 'pan-certificates';
  static const String _imagesBucket = 'restaurant-images';
  static const String _foodImagesBucket = 'food-images';

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

  /// Upload a file to a given bucket with a subfolder path.
  /// [bucket] — the Supabase storage bucket name.
  /// [folder] — optional subfolder within the bucket (e.g. 'logos', 'covers').
  Future<String> uploadFile({
    required String filePath,
    required String bucket,
    String? folder,
    required String userId,
    required String token,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileName = filePath.split('/').last;
    final remotePath = folder != null ? '$folder/$fileName' : fileName;
    final formData = FormData.fromMap({
      'bucket': bucket,
      'path': remotePath,
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
