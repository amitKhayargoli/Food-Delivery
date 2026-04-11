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

  const CompleteProfileScreen({
    super.key,
    required this.initialName,
    required this.googleToken,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  late TextEditingController _usernameController;
  final _phoneController = TextEditingController();

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
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();

    if (phone.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out all fields.')),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.completeProfile(
      phone: phone,
      username: username,
      token: widget.googleToken,
    );

    if (authProvider.isAuthenticated && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AppNavigation(role: 'USER'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Using PopScope (replacement for WillPopScope) to prevent back navigation
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Text(
                  'Complete Profile',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please provide a few more details to finish setting up your account.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 40),
                CustomTextField(
                  controller: _usernameController,
                  hintText: 'Username',
                  prefixIcon: Icons.person_outline,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _phoneController,
                  hintText: 'Phone Number',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 32),
                PrimaryButton(
                  text: 'Complete Profile',
                  onPressed: _submitProfile,
                ),
                const SizedBox(height: 24),
                // Optional logic to allow returning to LoginScreen explicitly:
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Return to Login screen
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
