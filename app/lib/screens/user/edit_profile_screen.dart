import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final authProvider = context.read<AuthProvider>();
    _nameController = TextEditingController(text: authProvider.username ?? '');
    _emailController = TextEditingController(text: authProvider.email ?? '');
    // Strip +977 prefix for display — only show the local number
    final rawPhone = authProvider.phone ?? '';
    final localNumber = rawPhone.startsWith('+977') ? rawPhone.substring(4) : rawPhone;
    _phoneController = TextEditingController(text: localNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return email.contains('@') && email.contains('.');
  }

  Future<void> _save() async {
    final newName = _nameController.text.trim();
    final newEmail = _emailController.text.trim();
    final newPhone = _phoneController.text.trim();

    // ── Validate name ──
    if (newName.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least 2 characters')),
      );
      return;
    }

    // ── Validate email ──
    if (newEmail.isNotEmpty && !_isValidEmail(newEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    // ── Validate phone ──
    if (newPhone.isNotEmpty && newPhone.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid phone number')),
      );
      return;
    }

    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    setState(() => _isSaving = true);

    try {
      final api = di.sl<ApiService>();
      final authProvider = context.read<AuthProvider>();

      // Build the update payload — only send what changed
      String? nameToSend = newName != (authProvider.username ?? '') ? newName : null;
      String? emailToSend = newEmail != (authProvider.email ?? '') ? newEmail : null;
      // Re-add +977 prefix for storage and API comparison
      final fullPhone = newPhone.isNotEmpty ? '+977$newPhone' : '';
      final phoneChanged = fullPhone != (authProvider.phone ?? '');
      String? phoneToSend = fullPhone.isNotEmpty && phoneChanged ? fullPhone : null;

      if (nameToSend == null && emailToSend == null && phoneToSend == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No changes to save')),
          );
        }
        return;
      }

      await api.updateProfile(
        username: nameToSend,
        email: emailToSend,
        phone: phoneToSend,
        token: token,
      );

      if (nameToSend != null) await authProvider.updateUsername(newName);
      if (emailToSend != null) await authProvider.updateEmail(newEmail);
      if (phoneToSend != null) await authProvider.updatePhone(fullPhone);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Profile updated!'),
              ],
            ),
            backgroundColor: Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.maybePop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Edit Profile',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFFBB0018))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Display Name ──
            _buildFieldLabel('Display Name', Icons.person_outline),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _nameController,
              hint: 'Enter your name',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 6),
            _buildHint('This is the name displayed on your profile and orders.'),

            const SizedBox(height: 24),

            // ── Email ──
            _buildFieldLabel('Email Address', Icons.email_outlined),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _emailController,
              hint: 'Enter your email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 6),
            _buildHint('Used for order confirmations and account notifications.'),

            const SizedBox(height: 24),

            // ── Phone Number ──
            _buildFieldLabel('Phone Number', Icons.phone_outlined),
            const SizedBox(height: 10),
            _buildPhoneField(),
            const SizedBox(height: 6),
            _buildHint('Your contact number for order updates and delivery.'),

            const SizedBox(height: 32),

            // ── Save Button ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFEFEDED),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable Widgets ──

  Widget _buildFieldLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF595959)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF262626),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFBFBFBF)),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        textInputAction: textInputAction ?? TextInputAction.done,
        onSubmitted: textInputAction == TextInputAction.done ? (_) => _save() : null,
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Row(
        children: [
          const Text(
            '🇳🇵 ',
            style: TextStyle(fontSize: 18),
          ),
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '98XXXXXXXX',
                hintStyle: TextStyle(color: Color(0xFFBFBFBF)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
    );
  }
}
