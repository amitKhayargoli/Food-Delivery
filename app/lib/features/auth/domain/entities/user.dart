import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String username;
  final String email;
  final String phone;
  final String role;
  final String status;
  final String? token;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    this.token,
  });

  @override
  List<Object?> get props => [id, username, email, phone, role, status, token];
}
