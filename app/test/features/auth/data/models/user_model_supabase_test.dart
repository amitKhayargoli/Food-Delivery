import 'package:app/features/auth/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromSupabaseProfile maps USER role to CUSTOMER', () {
    final model = UserModel.fromSupabaseProfile(
      authUserId: 'u-1',
      authEmail: 'user@example.com',
      accessToken: 'token-1',
      profile: {
        'username': 'amit',
        'phone': '+9779800000000',
        'role': 'USER',
        'status': 'ACTIVE',
      },
    );

    expect(model.id, 'u-1');
    expect(model.email, 'user@example.com');
    expect(model.role, 'CUSTOMER');
    expect(model.token, 'token-1');
  });
}
