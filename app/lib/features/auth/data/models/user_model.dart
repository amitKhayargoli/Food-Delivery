import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.username,
    required super.email,
    required super.phone,
    required super.role,
    required super.status,
    super.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : <String, dynamic>{};

    return UserModel(
      id: (userJson['id'] ?? json['id'] ?? '').toString(),
      username: (userJson['username'] ?? json['username'] ?? '').toString(),
      email: (userJson['email'] ?? json['email'] ?? '').toString(),
      phone: (userJson['phone'] ?? json['phone'] ?? '').toString(),
      role: (userJson['role'] ?? json['role'] ?? 'USER').toString(),
      status: (userJson['status'] ?? json['status'] ?? 'ACTIVE').toString(),
      token: json['token'],
    );
  }

  factory UserModel.fromSupabaseProfile({
    required String authUserId,
    required String authEmail,
    required String? accessToken,
    required Map<String, dynamic>? profile,
  }) {
    final rawRole = (profile?['role'] ?? 'CUSTOMER').toString();
    final normalizedRole = rawRole == 'USER' ? 'CUSTOMER' : rawRole;

    return UserModel(
      id: authUserId,
      username: (profile?['username'] ?? authEmail.split('@').first).toString(),
      email: (profile?['email'] ?? authEmail).toString(),
      phone: (profile?['phone'] ?? '').toString(),
      role: normalizedRole,
      status: (profile?['status'] ?? 'ACTIVE').toString(),
      token: accessToken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'phone': phone,
      'role': role,
      'status': status,
      'token': token,
    };
  }
}
