import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/auth_local_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Either<Failure, User>> loginWithCredentials(String identifier, String password) async {
    try {
      final userModel = await remoteDataSource.login(identifier, password);
      await localDataSource.cacheUser(userModel);
      return Right(userModel);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> registerWithCredentials({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final userModel = await remoteDataSource.register(
        username: username,
        email: email,
        phone: phone,
        password: password,
      );
      await localDataSource.cacheUser(userModel);
      return Right(userModel);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> signInWithGoogle() async {
    try {
      final userModel = await remoteDataSource.signInWithGoogle();
      await localDataSource.cacheUser(userModel);
      return Right(userModel);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await remoteDataSource.logout();
      await localDataSource.clearCache();
      return const Right(null);
    } catch (e) {
      return const Left(CacheFailure('Failed to clear cache'));
    }
  }

  @override
  Future<Either<Failure, User?>> getCachedUser() async {
    try {
      final user = await localDataSource.getLastUser();
      return Right(user);
    } catch (e) {
      return const Left(CacheFailure('Failed to get cached user'));
    }
  }

  @override
  Stream<User?> get onAuthStateChanged {
    return remoteDataSource.onAuthStateChanged.map((userModel) {
      if (userModel != null) {
        localDataSource.cacheUser(userModel);
      } else {
        localDataSource.clearCache();
      }
      return userModel;
    });
  }
}
