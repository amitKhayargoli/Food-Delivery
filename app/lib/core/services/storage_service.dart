import 'dart:io';

import 'package:dio/dio.dart';

class StorageService {
  final Dio _dio;

  StorageService(this._dio);

  static const String _panBucket = 'pan-certificates';
  static const String _imagesBucket = 'restaurant-images';

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
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileName = filePath.split('/').last;
    final formData = FormData.fromMap({
      'bucket': _imagesBucket,
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
