import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../widgets/primary_button.dart';
import '../../../../widgets/social_login_button.dart';
import '../../../../state_providers.dart';
import 'login_screen.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    final viewModel = ref.read(authViewModelProvider);
    
    final success = await viewModel.register(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      phone: '+977${_phoneController.text.trim()}',
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(viewModel.errorMessage ?? 'Signup failed')),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    final viewModel = ref.read(authViewModelProvider);
    final success = await viewModel.signInWithGoogle();

    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(viewModel.errorMessage ?? 'Google sign-in failed')),
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
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = ref.watch(authViewModelProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Text(
                  'Create an Account',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign up to get started',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 40),
                CustomTextField(
                  controller: _usernameController,
                  hintText: 'Username',
                  prefixIcon: Icons.person_outline,
                  validator: (value) => value!.isEmpty ? 'Username is required' : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _emailController,
                  hintText: 'Email Address',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'Email is required';
                    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                    if (!emailRegex.hasMatch(email)) return 'Please enter a valid email address';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Custom Phone Field with Nepal Flag Prefix

                CustomTextField(
                  controller: _phoneController,
                  hintText: 'Phone Number',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    final phone = value?.trim() ?? '';
                    if (phone.isEmpty) return 'Phone number is required';
                    if (phone.length != 10) return 'Phone number must be exactly 10 digits';
                    if (!RegExp(r'^9\d{9}$').hasMatch(phone)) {
                      return 'Phone number must start with 9 and contain only digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // TextFormField(
                //   controller: _phoneController,
                //   keyboardType: TextInputType.phone,
                //   decoration: InputDecoration(
                //     hintText: 'Phone Number',
                //     prefixIcon: Padding(
                //       padding: const EdgeInsets.symmetric(horizontal: 12.0),
                //       child: Row(
                //         mainAxisSize: MainAxisSize.min,
                //         children: [
                //           const Text('🇳🇵', style: TextStyle(fontSize: 24)),
                //           const SizedBox(width: 8),
                //           Text(
                //             '+977',
                //             style: theme.textTheme.bodyLarge?.copyWith(
                //               fontWeight: FontWeight.bold,
                //             ),
                //           ),
                //           const SizedBox(width: 8),
                //           Container(width: 1, height: 24, color: Colors.grey.shade300),
                //         ],
                //       ),
                //     ),
                //     // border: OutlineInputBorder(
                //     //   borderRadius: BorderRadius.circular(12),
                //     // ),
                //   ),
                //   validator: (value) {
                //     if (value == null || value.isEmpty) return 'Phone number is required';
                //     if (value.length < 10) return 'Enter a valid 10-digit number';
                //     return null;
                //   },
                // ),
                // const SizedBox(height: 16),
                CustomTextField(
                  controller: _passwordController,
                  hintText: 'Password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password is required';
                    if (value.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                viewModel.isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : PrimaryButton(
                        text: 'Sign Up',
                        onPressed: _signUp,
                      ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text('OR', style: theme.textTheme.bodySmall),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
                SocialLoginButton(
                  text: 'Continue with Google',
                  onPressed: _signInWithGoogle,
                  isLoading: viewModel.isLoading,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF8E8E93),
                      ),
                    ),
                    GestureDetector(
                      onTap: _navigateToLogin,
                      child: Text(
                        'Login',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
