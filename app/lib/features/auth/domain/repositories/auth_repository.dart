import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  Future<Either<Failure, User>> loginWithCredentials(String identifier, String password);
  Future<Either<Failure, User>> registerWithCredentials({
    required String username,
    required String email,
    required String phone,
    required String password,
  });
  Future<Either<Failure, User>> signInWithGoogle();
  Future<Either<Failure, void>> logout();
  Future<Either<Failure, User?>> getCachedUser();
  Stream<User?> get onAuthStateChanged;
}
