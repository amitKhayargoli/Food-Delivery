import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/get_cached_user_usecase.dart';
import '../../domain/usecases/google_sign_in_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/register_usecase.dart';

class AuthViewModel extends ChangeNotifier {
  final LoginUseCase loginUseCase;
  final RegisterUseCase registerUseCase;
  final GoogleSignInUseCase googleSignInUseCase;
  final LogoutUseCase logoutUseCase;
  final GetCachedUserUseCase getCachedUserUseCase;
  final AuthRepository authRepository;

  StreamSubscription<User?>? _authSubscription;

  AuthViewModel({
    required this.loginUseCase,
    required this.registerUseCase,
    required this.googleSignInUseCase,
    required this.logoutUseCase,
    required this.getCachedUserUseCase,
    required this.authRepository,
  }) {
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    _authSubscription?.cancel();
    _authSubscription = authRepository.onAuthStateChanged.listen((user) {
      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
      } else {
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  User? _currentUser;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && _currentUser?.token != null;

  Future<void> init() async {
    final result = await getCachedUserUseCase();
    _currentUser = result.fold(
      (_) => null,
      (user) => user,
    );
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  Future<bool> login(String identifier, String password) async {
    _setLoading(true);
    _setError(null);

    final result = await loginUseCase(identifier, password);

    _setLoading(false);

    return result.fold(
      (failure) {
        _setError(failure.message);
        return false;
      },
      (user) {
        _currentUser = user;
        notifyListeners();
        return true;
      },
    );
  }

  Future<bool> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    _setLoading(true);
    _setError(null);

    final result = await registerUseCase(
      username: username,
      email: email,
      phone: phone,
      password: password,
    );

    _setLoading(false);

    return result.fold(
      (failure) {
        _setError(failure.message);
        return false;
      },
      (user) {
        _currentUser = user;
        notifyListeners();
        return true;
      },
    );
  }

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _setError(null);

    final result = await googleSignInUseCase();

    // Do NOT set loading to false here because the actual login 
    // will be caught by the _listenToAuthChanges stream.
    // If the launch fails, we set it to false.
    
    return result.fold(
      (failure) {
        _setLoading(false);
        _setError(failure.message);
        return false;
      },
      (user) {
        // If "pending", keep loading true until the stream fires
        if (user.id == 'pending') {
          return true;
        }
        _setLoading(false);
        _currentUser = user;
        notifyListeners();
        return true;
      },
    );
  }

  Future<void> logout() async {
    await logoutUseCase();
    _currentUser = null;
    notifyListeners();
  }
}
