import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class RegisterUseCase {
  final AuthRepository repository;

  RegisterUseCase(this.repository);

  Future<Either<Failure, User>> call({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) {
    // Add domain validation logic if necessary, otherwise delegate to repo
    if (phone.length < 10) {
      return Future.value(const Left(ValidationFailure('Invalid phone number length')));
    }
    
    return repository.registerWithCredentials(
      username: username,
      email: email,
      phone: phone,
      password: password,
    );
  }
}
