import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheUser(UserModel userToCache);
  Future<UserModel?> getLastUser();
  Future<void> clearCache();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final SharedPreferences sharedPreferences;
  final FlutterSecureStorage secureStorage;

  AuthLocalDataSourceImpl({
    required this.sharedPreferences,
    required this.secureStorage,
  });

  @override
  Future<void> cacheUser(UserModel user) async {
    final userJsonString = json.encode(user.toJson());
    await sharedPreferences.setString('CACHED_USER', userJsonString);
    if (user.token != null) {
      await secureStorage.write(key: 'supabase_access_token', value: user.token);
    }
  }

  @override
  Future<UserModel?> getLastUser() async {
    final jsonString = sharedPreferences.getString('CACHED_USER');
    if (jsonString != null) {
      final token = await secureStorage.read(key: 'supabase_access_token');
      final map = json.decode(jsonString);
      map['token'] = token;
      return UserModel.fromJson(map);
    }
    return null;
  }

  @override
  Future<void> clearCache() async {
    await sharedPreferences.remove('CACHED_USER');
    await secureStorage.delete(key: 'supabase_access_token');
  }
}
