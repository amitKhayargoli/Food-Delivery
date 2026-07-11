import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'login_screen.dart';
import 'otp_screen.dart';
import 'complete_profile_screen.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../../navigation/app_navigation.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _nameError;
  String? _phoneError;
  String? _nameSuccess;
  String? _phoneSuccess;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  Timer? _nameDebounce;
  Timer? _phoneDebounce;
  final ApiService _apiService = di.sl<ApiService>();

  bool _validateName() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _nameError = 'Full name is required');
      return false;
    }

    setState(() => _nameError = null);
    return true;
  }

  bool _validatePhone() {
    final phone = _phoneController.text.trim();
    final phoneRegex = RegExp(r'^9\d{9}$');

    if (phone.isEmpty) {
      setState(() => _phoneError = 'Phone number is required');
      return false;
    }

    if (phone.length != 10) {
      setState(() => _phoneError = 'Phone number must be exactly 10 digits');
      return false;
    }

    if (!phoneRegex.hasMatch(phone)) {
      setState(() => _phoneError = 'Phone number must start with 9 and contain only digits');
      return false;
    }

    setState(() => _phoneError = null);
    return true;
  }


  void _debounceAvailabilityCheck(String field, String value) {
    if (value.isEmpty) return;

    // Skip if format is invalid
    if (field == 'phone') {
      final phoneRegex = RegExp(r'^9\d{9}$');
      if (value.length != 10 || !phoneRegex.hasMatch(value)) return;
    } else if (field == 'name') {
      if (value.length < 2) return;
    }

    _apiService.checkAvailability(
      username: field == 'name' ? value : null,
      phone: field == 'phone' ? value : null,
      email: field == 'email' ? value : null,
    ).then((availability) {
      if (!mounted) return;
      setState(() {
        if (field == 'name') {
          if (availability.usernameTaken) {
            _nameError = 'This username is already taken';
            _nameSuccess = null;
          } else {
            _nameError = null;
            _nameSuccess = 'Username "$value" is available';
          }
        } else if (field == 'phone') {
          if (availability.phoneTaken) {
            _phoneError = 'This phone number is already registered';
            _phoneSuccess = null;
          } else {
            _phoneError = null;
            _phoneSuccess = '$value is available';
          }

        }
      });
    }).catchError((_) {});
  }

  Future<void> _checkAndContinue() async {
    // Cancel any pending debounce checks
    _nameDebounce?.cancel();
    _phoneDebounce?.cancel();

    if (!_validateName() || !_validatePhone()) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      final availability = await _apiService.checkAvailability(
        username: name,
        phone: phone,
      );

      if (!mounted) return;

      if (availability.usernameTaken || availability.phoneTaken) {
        setState(() {
          _isLoading = false;
          if (availability.usernameTaken) _nameError = 'This username is already taken';
          if (availability.phoneTaken) _phoneError = 'This phone number is already registered';
        });
        return;
      }

      // All fields available — proceed to OTP
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: phone,
            purpose: 'SIGNUP',
            username: name,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final result = await authProvider.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    if (result['success'] == true) {
      if (result['requires_profile_completion'] == true) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CompleteProfileScreen(
              initialName: result['name'] ?? '',
              googleToken: result['token'] ?? '',
              tempToken: result['temp_token'] as String?,
            ),
          ),
        );
      } else if (authProvider.isAuthenticated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const AppNavigation(role: 'USER'),
          ),
        );
      }
    } else {
      final error = result['error'] ?? 'Sign in failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _phoneDebounce?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 320),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 117, bottom: 75),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFF5222D), // 0%
                      Color(0xFFFFFFFF), // 100%
                    ],
                    stops: [0.0, 1.0],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/img/logo.png',
                      width: 200,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Create an account',
                      style: TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        height: 1.50,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sign up with your details',
                      style: TextStyle(
                        color: Color(0xFF595959),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.50,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your Full Name',
                    style: TextStyle(
                      color: Color(0xFF262626),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: ShapeDecoration(
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: TextField(
                      controller: _nameController,
                      onChanged: (value) {
                        setState(() {
                          _nameError = null;
                          _nameSuccess = null;
                        });
                        _nameDebounce?.cancel();
                        _nameDebounce = Timer(
                          const Duration(milliseconds: 1500),
                          () => _debounceAvailabilityCheck('name', value.trim()),
                        );
                      },
                      decoration: const InputDecoration(
                        hintText: 'Full Name',
                        hintStyle: TextStyle(
                          color: Color(0xFFBFBFBF),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_nameSuccess != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: Color(0xFF52C41A)),
                          const SizedBox(width: 4),
                          Text(
                            _nameSuccess!,
                            style: const TextStyle(
                              color: Color(0xFF52C41A),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_nameError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _nameError!,
                        style: const TextStyle(
                          color: Color(0xFFF5222D),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your Phone Number',
                    style: TextStyle(
                      color: Color(0xFF262626),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: ShapeDecoration(
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🇳🇵', style: TextStyle(fontSize: 20)),
                        const Text(
                          '+977',
                          style: TextStyle(
                            color: Color(0xFF595959),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.50,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: const Color(0xFFE8E8E8),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            onChanged: (value) {
                              setState(() {
                                _phoneError = null;
                                _phoneSuccess = null;
                              });
                              _phoneDebounce?.cancel();
                              _phoneDebounce = Timer(
                                const Duration(milliseconds: 1500),
                                () => _debounceAvailabilityCheck('phone', value.trim()),
                              );
                            },
                            decoration: const InputDecoration(
                              hintText: '98XXXXXXXX',
                              hintStyle: TextStyle(
                                color: Color(0xFFBFBFBF),
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_phoneSuccess != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: Color(0xFF52C41A)),
                          const SizedBox(width: 4),
                          Text(
                            _phoneSuccess!,
                            style: const TextStyle(
                              color: Color(0xFF52C41A),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_phoneError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _phoneError!,
                        style: const TextStyle(
                          color: Color(0xFFF5222D),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _checkAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5222D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.50,
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFFE8E8E8))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Or',
                      style: TextStyle(
                        color: const Color(0xFF8C8C8C),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.50,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFFE8E8E8))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: InkWell(
                onTap: _isGoogleLoading ? null : _signInWithGoogle,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(width: 1, color: Color(0xFFD9D9D9)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isGoogleLoading
                      ? const Center(
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/img/google.png',
                              width: 20,
                              height: 20,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Continue with Google',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF262626),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 1.50,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 20),
              child: GestureDetector(
                onTap: _navigateToLogin,
                child: Text.rich(
                  textAlign: TextAlign.center,
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Already have an Account? ',
                        style: TextStyle(color: Color(0xFF8C8C8C), fontSize: 12),
                      ),
                      TextSpan(
                        text: 'Login ',
                        style: const TextStyle(color: Color(0xFFF5222D), fontSize: 12),
                        recognizer: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
