import 'package:app/core/errors/failures.dart';
import 'package:app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGoogleSignIn implements GoogleSignIn {
  _FakeGoogleSignIn({this.account});

  final GoogleSignInAccount? account;

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const <String>[],
  }) async => account!;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignInNoAccount implements GoogleSignIn {
  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const <String>[],
  }) async {
    throw PlatformException(
      code: 'sign_in_canceled',
      message: 'Google sign-in was cancelled',
    );
  }

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignInAccount implements GoogleSignInAccount {
  _FakeGoogleSignInAccount(this._authentication);

  final GoogleSignInAuthentication _authentication;

  @override
  GoogleSignInAuthentication get authentication => _authentication;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignInAuthentication implements GoogleSignInAuthentication {
  _FakeGoogleSignInAuthentication({required this.idToken, this.accessToken});

  @override
  final String? idToken;

  @override
  final String? accessToken;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('signInWithGoogle throws when Google account selection is canceled', () async {
    final dataSource = AuthRemoteDataSourceImpl(
      () => throw UnimplementedError('client should not be used in this test'),
      _FakeGoogleSignInNoAccount(),
      configuredCheck: () => true,
    );

    await expectLater(
      () => dataSource.signInWithGoogle(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          'Google sign-in was cancelled',
        ),
      ),
    );
  });

  test('signInWithGoogle exchanges Google idToken with Supabase via signInWithIdToken', () async {
    String? capturedIdToken;
    String? capturedAccessToken;
    Map<String, dynamic>? capturedUpsert;

    final authUser = User(
      id: 'google-user-id',
      appMetadata: const {},
      userMetadata: const {'name': 'Google User'},
      aud: 'authenticated',
      createdAt: '2024-01-01T00:00:00.000Z',
      email: 'user@example.com',
      phone: null,
    );

    final authResponse = AuthResponse(
      user: authUser,
      session: Session(
        accessToken: 'supabase-access-token',
        tokenType: 'bearer',
        user: authUser,
      ),
    );

    final dataSource = AuthRemoteDataSourceImpl(
      () => throw UnimplementedError('client should not be used in this test'),
      _FakeGoogleSignIn(
        account: _FakeGoogleSignInAccount(
          _FakeGoogleSignInAuthentication(
            idToken: 'google-id-token',
            accessToken: 'google-access-token',
          ),
        ),
      ),
      configuredCheck: () => true,
      signInWithIdToken: ({required idToken, String? accessToken}) async {
        capturedIdToken = idToken;
        capturedAccessToken = accessToken;
        return authResponse;
      },
      getProfileByUserId: (userId) async {
        if (capturedUpsert == null) {
          return null;
        }

        return {
          'id': userId,
          'username': 'google_user',
          'email': 'user@example.com',
          'phone': '',
          'role': 'CUSTOMER',
          'status': 'ACTIVE',
        };
      },
      upsertProfile: (profile) async {
        capturedUpsert = profile;
      },
    );

    final user = await dataSource.signInWithGoogle();

    expect(capturedIdToken, 'google-id-token');
    // The accessToken is not passed to _exchangeGoogleToken in production
    expect(capturedAccessToken, isNull);
    expect(capturedUpsert, isNotNull);
    expect(capturedUpsert?['id'], 'google-user-id');
    expect(user.email, 'user@example.com');
    expect(user.token, 'supabase-access-token');
  });
}
