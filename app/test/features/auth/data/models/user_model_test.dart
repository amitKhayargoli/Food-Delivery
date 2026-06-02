import 'package:app/features/auth/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses top-level payload when user object is absent', () {
    final model = UserModel.fromJson({
      'id': 'u-1',
      'username': 'amit',
      'email': 'amit@example.com',
      'phone': '+9779800000000',
      'role': 'USER',
      'status': 'ACTIVE',
      'token': 'jwt-token',
    });

    expect(model.id, 'u-1');
    expect(model.username, 'amit');
    expect(model.phone, '+9779800000000');
    expect(model.token, 'jwt-token');
  });
}
