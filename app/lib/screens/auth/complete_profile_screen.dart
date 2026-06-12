import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';
import '../../navigation/app_navigation.dart';
import 'login_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  final String initialName;
  final String googleToken;
  final String? tempToken;

  const CompleteProfileScreen({
    super.key,
    required this.initialName,
    required this.googleToken,
    this.tempToken,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  final _phoneController = TextEditingController();
  String? _phoneError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submitProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();

    if (phone.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out all fields.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.completeProfile(
      phone: phone,
      username: username,
      token: widget.googleToken,
      tempToken: widget.tempToken,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (authProvider.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AppNavigation(role: 'USER'),
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    // Using PopScope (replacement for WillPopScope) to prevent back navigation
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Red gradient header with logo
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 300),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 60, bottom: 60),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFF5222D),
                        Color(0xFFFFFFFF),
                      ],
                      stops: [0.0, 1.0],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/img/logo.png',
                        width: 180,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.restaurant,
                          size: 64,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Almost there!',
                        style: TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          height: 1.50,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Just a few more details',
                        style: TextStyle(
                          color: Color(0xFF595959),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          height: 1.50,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Form section
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomTextField(
                        controller: _usernameController,
                        hintText: 'Username',
                        prefixIcon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username is required';
                          }
                          if (value.trim().length < 3) {
                            return 'Username must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Phone number with Nepal flag prefix
                      const SizedBox(
                        width: double.infinity,
                        child: Text(
                          'Phone Number',
                          style: TextStyle(
                            color: Color(0xFF262626),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              width: 1,
                              color: _phoneError != null
                                  ? const Color(0xFFF5222D)
                                  : const Color(0xFFE8E8E8),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: _phoneError != null
                              ? const Color(0xFFFFF1F0)
                              : const Color(0xFFF7F8FA),
                        ),
                        child: Row(
                          children: [
                            const Text('🇳🇵', style: TextStyle(fontSize: 20)),
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text(
                                '+977',
                                style: TextStyle(
                                  color: Color(0xFF595959),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.50,
                                ),
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
                                onChanged: (_) {
                                  if (_phoneError != null) {
                                    setState(() => _phoneError = null);
                                  }
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
                      if (_phoneError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _phoneError!,
                            style: const TextStyle(
                              color: Color(0xFFF5222D),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : PrimaryButton(
                                text: 'Complete Profile',
                                onPressed: () {
                                  if (!_validatePhone()) return;
                                  _submitProfile();
                                },
                              ),
                      ),
                      const SizedBox(height: 20),
                      // Link to return to Login
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF8E8E93),
                          ),
                          child: const Text('Cancel and Return to Login'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
