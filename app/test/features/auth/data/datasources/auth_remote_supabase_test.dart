import 'dart:async';
import 'package:app/core/errors/failures.dart';
import 'package:app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:app/features/auth/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSupabaseRemoteDataSource extends AuthRemoteDataSource {
  @override
  Future<UserModel> login(String identifier, String password) async {
    return UserModel.fromSupabaseProfile(
      authUserId: 'user-1',
      authEmail: identifier,
      accessToken: 'access-token',
      profile: {
        'username': 'rider',
        'phone': '+9779800000000',
        'role': 'DELIVERY_BOY',
        'status': 'ACTIVE',
      },
    );
  }

  @override
  Future<UserModel> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    return UserModel.fromSupabaseProfile(
      authUserId: 'user-2',
      authEmail: email,
      accessToken: 'new-token',
      profile: {
        'username': username,
        'phone': phone,
        'role': 'CUSTOMER',
        'status': 'ACTIVE',
      },
    );
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    return UserModel.fromSupabaseProfile(
      authUserId: 'google-user',
      authEmail: 'google@example.com',
      accessToken: 'google-token',
      profile: {
        'username': 'google_user',
        'phone': '',
        'role': 'USER',
        'status': 'ACTIVE',
      },
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Stream<UserModel?> get onAuthStateChanged => const Stream.empty();
}

void main() {
  test('google sign in maps USER role to CUSTOMER', () async {
    final ds = _FakeSupabaseRemoteDataSource();
    final user = await ds.signInWithGoogle();

    expect(user.id, 'google-user');
    expect(user.role, 'CUSTOMER');
    expect(user.token, 'google-token');
  });

  test('login returns delivery role from supabase profile', () async {
    final ds = _FakeSupabaseRemoteDataSource();
    final user = await ds.login('rider@example.com', 'secret123');

    expect(user.role, 'DELIVERY_BOY');
    expect(user.email, 'rider@example.com');
  });

  test('register returns profile with customer role', () async {
    final ds = _FakeSupabaseRemoteDataSource();
    final user = await ds.register(
      username: 'newuser',
      email: 'new@example.com',
      phone: '+9779811111111',
      password: 'password123',
    );

    expect(user.username, 'newuser');
    expect(user.role, 'CUSTOMER');
  });

  test('throws failure type in invalid branch example', () {
    expect(const ValidationFailure('x'), isA<Failure>());
  });
}
