import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/social_login_button.dart';
import '../../navigation/app_navigation.dart';
import 'signup_screen.dart';

import 'complete_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  void _login(String role) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AppNavigation(role: role),
      ),
    );
  }

  void _loginWithGoogle() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final result = await authProvider.signInWithGoogle();
    
    if (result['success'] == true && mounted) {
      if (result['requires_profile_completion'] == true) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CompleteProfileScreen(
              initialName: result['name'] ?? '',
              googleToken: result['token'] ?? '',
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
    } else if (result['success'] == false && mounted) {
      final error = result['error'] ?? 'Sign in failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  void _navigateToSignUp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const SignUpScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Center(
                child: Icon(
                  Icons.fastfood,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Welcome back!',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your details to continue',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 48),
              CustomTextField(
                controller: _identifierController,
                hintText: 'Email or Phone Number',
                prefixIcon: Icons.person_outline,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _passwordController,
                hintText: 'Password',
                prefixIcon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // TODO: Implement Forgot Password logic
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                  ),
                  child: const Text('Forgot Password?'),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                text: 'Login',
                onPressed: () => _login('USER'),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'OR',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 32),
              SocialLoginButton(
                text: 'Continue with Google',
                onPressed: _loginWithGoogle,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF8E8E93),
                    ),
                  ),
                  GestureDetector(
                    onTap: _navigateToSignUp,
                    child: Text(
                      'Sign Up',
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
    );
  }
}
