import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'otp_screen.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _nameSuccess;
  String? _phoneSuccess;
  String? _emailSuccess;
  bool _isLoading = false;
  Timer? _nameDebounce;
  Timer? _phoneDebounce;
  Timer? _emailDebounce;
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

  bool _validateEmail() {
    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

    if (email.isNotEmpty && !emailRegex.hasMatch(email)) {
      setState(() => _emailError = 'Please enter a valid email address');
      return false;
    }

    setState(() => _emailError = null);
    return true;
  }

  void _debounceAvailabilityCheck(String field, String value) {
    if (value.isEmpty) return;

    // Skip if format is invalid
    if (field == 'phone') {
      final phoneRegex = RegExp(r'^9\d{9}$');
      if (value.length != 10 || !phoneRegex.hasMatch(value)) return;
    } else if (field == 'email') {
      if (value.length < 5) return;
      final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      if (!emailRegex.hasMatch(value)) return;
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
        } else if (field == 'email') {
          if (availability.emailTaken) {
            _emailError = 'This email is already registered';
            _emailSuccess = null;
          } else {
            _emailError = null;
            _emailSuccess = '$value is available';
          }
        }
      });
    }).catchError((_) {});
  }

  Future<void> _checkAndContinue() async {
    // Cancel any pending debounce checks
    _nameDebounce?.cancel();
    _phoneDebounce?.cancel();
    _emailDebounce?.cancel();

    if (!_validateName() || !_validatePhone() || !_validateEmail()) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      final availability = await _apiService.checkAvailability(
        username: name,
        phone: phone,
        email: email.isNotEmpty ? email : null,
      );

      if (!mounted) return;

      if (availability.usernameTaken || availability.phoneTaken || availability.emailTaken) {
        setState(() {
          _isLoading = false;
          if (availability.usernameTaken) _nameError = 'This username is already taken';
          if (availability.phoneTaken) _phoneError = 'This phone number is already registered';
          if (availability.emailTaken) _emailError = 'This email is already registered';
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

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _phoneDebounce?.cancel();
    _emailDebounce?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
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
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter Your Email (optional)',
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
                    ),                      child: TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (value) {
                        setState(() {
                          _emailError = null;
                          _emailSuccess = null;
                        });
                        _emailDebounce?.cancel();
                        _emailDebounce = Timer(
                          const Duration(milliseconds: 1500),
                          () => _debounceAvailabilityCheck('email', value.trim()),
                        );
                      },
                      decoration: const InputDecoration(
                        hintText: 'johndoe@gmail.com',
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
                  if (_emailSuccess != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: Color(0xFF52C41A)),
                          const SizedBox(width: 4),
                          Text(
                            _emailSuccess!,
                            style: const TextStyle(
                              color: Color(0xFF52C41A),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_emailError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _emailError!,
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
