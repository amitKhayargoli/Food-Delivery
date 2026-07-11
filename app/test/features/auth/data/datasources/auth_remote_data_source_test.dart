import 'package:app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:app/features/auth/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

class _FakeRemoteDataSource extends AuthRemoteDataSource {
  @override
  Future<UserModel> login(String identifier, String password) async {
    return UserModel.fromJson({
      'token': 'jwt-login',
      'user': {
        'id': '1',
        'username': 'amit',
        'email': 'amit@example.com',
        'phone': '+9779800000000',
        'role': 'USER',
      }
    });
  }

  @override
  Future<UserModel> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    return UserModel.fromJson({
      'token': 'jwt-register',
      'user': {
        'id': '2',
        'username': username,
        'email': email,
        'phone': phone,
        'role': 'USER',
      }
    });
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    return UserModel.fromJson({
      'token': 'jwt-google',
      'user': {
        'id': '3',
        'username': 'google-user',
        'email': 'google@example.com',
        'phone': '',
        'role': 'USER',
      }
    });
  }

  @override
  Future<void> logout() async {}

  @override
  Stream<UserModel?> get onAuthStateChanged => const Stream.empty();
}

void main() {
  test('login response contains user id string', () async {
    final ds = _FakeRemoteDataSource();
    final result = await ds.login('amit@example.com', 'secret123');

    expect(result.id, isA<String>());
    expect(result.id, isNotEmpty);
  });

  test('register response contains user id string', () async {
    final ds = _FakeRemoteDataSource();
    final result = await ds.register(
      username: 'amit',
      email: 'amit@example.com',
      phone: '+9779800000000',
      password: 'secret123',
    );

    expect(result.id, isA<String>());
    expect(result.id, isNotEmpty);
  });
}
