import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';

class DeliveryProfileScreen extends StatefulWidget {
  const DeliveryProfileScreen({super.key});

  @override
  State<DeliveryProfileScreen> createState() => _DeliveryProfileScreenState();
}

class _DeliveryProfileScreenState extends State<DeliveryProfileScreen> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _fetchStats() async {
    final token = _token;
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = di.sl<ApiService>();
      final stats = await api.getRiderStats(token: token);
      if (mounted) setState(() { _stats = stats; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Pick an image from gallery/camera, upload to Supabase, and update the profile.
  Future<void> _pickAndUploadAvatar(AuthProvider authProvider) async {
    // Capture messenger before any async gaps
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();

    // Show bottom sheet to choose source
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Change Profile Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFFBB0018)),
                title: const Text('Take Photo'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFFBB0018)),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    // Show loading indicator
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Uploading profile photo...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      final token = authProvider.token;
      if (token == null) {
        if (mounted) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            const SnackBar(content: Text('Not authenticated')),
          );
        }
        return;
      }

      // Upload to avatar-images bucket
      final storage = di.sl<StorageService>();
      final avatarUrl = await storage.uploadProfilePicture(
        filePath: pickedFile.path,
        token: token,
      );

      // Save the URL on the backend
      final api = di.sl<ApiService>();
      await api.updateAvatarUrl(avatarUrl: avatarUrl, token: token);

      // Update AuthProvider state
      await authProvider.setAvatarUrl(avatarUrl);

      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
      ),
      body: _buildBody(auth),
    );
  }

  Widget _buildBody(AuthProvider auth) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading profile...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    final deliveries = (_stats['total_deliveries'] as num?)?.toInt() ?? 0;
    final earnings = (_stats['total_earnings'] as num?)?.toDouble() ?? 0.0;
    final distance = (_stats['estimated_distance_km'] as num?)?.toDouble() ?? 0.0;

    return RefreshIndicator(
      onRefresh: _fetchStats,
      color: const Color(0xFFBB0018),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profile Header with Avatar ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // Avatar with camera overlay
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    children: [
                      // Avatar image or letter fallback
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFFFF1F0),
                        child: _buildAvatarContent(auth),
                      ),
                      // Camera/edit icon overlay (tappable)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () => _pickAndUploadAvatar(auth),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: ShapeDecoration(
                              color: const Color(0xFFBB0018),
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(
                                  width: 2,
                                  color: Color(0xFFFAF9F9),
                                ),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                            ),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 10, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  auth.username ?? 'Delivery Rider',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F4EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Delivery Rider',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E8E3E),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Today's Stats ──
          const Text("Today's Performance",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C))),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.check_circle_rounded,
                  label: 'Deliveries',
                  value: '$deliveries',
                  color: const Color(0xFF1E8E3E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.route_rounded,
                  label: 'Distance',
                  value: '${distance.toStringAsFixed(1)} km',
                  color: const Color(0xFF1967D2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Today\'s Earnings',
            value: 'Rs. ${earnings.toStringAsFixed(0)}',
            color: const Color(0xFFBB0018),
            large: true,
          ),

          const SizedBox(height: 24),

          // ── Role Switching Info ──
          if (auth.availableRoles.length > 1) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: Color(0xFFF9A825)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Multi-Role Account',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: Color(0xFF795548))),
                        const SizedBox(height: 4),
                        Text(
                          'You also have access as: ${auth.availableRoles.where((r) => r != 'DELIVERY_BOY').map(_formatRole).join(', ')}',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF795548), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Logout ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmLogout(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Logout',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFBB0018),
                side: const BorderSide(color: Color(0xFFBB0018)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build avatar content — either the uploaded image or a letter fallback.
  Widget _buildAvatarContent(AuthProvider auth) {
    final avatarUrl = auth.avatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: Image.network(
          avatarUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildAvatarLetter(auth),
        ),
      );
    }

    return _buildAvatarLetter(auth);
  }

  Widget _buildAvatarLetter(AuthProvider auth) {
    return Text(
      (auth.username ?? 'R').substring(0, 1).toUpperCase(),
      style: const TextStyle(
        color: Color(0xFFBB0018),
        fontWeight: FontWeight.w700,
        fontSize: 28,
      ),
    );
  }

  String _formatRole(String raw) {
    return raw
        .split('_')
        .map((w) => w.isNotEmpty
            ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool large = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(large ? 20 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: large ? 22 : 20),
          ),
          SizedBox(height: large ? 16 : 12),
          Text(label,
              style: TextStyle(
                  fontSize: large ? 14 : 13,
                  color: const Color(0xFF8E8E93),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: large ? 28 : 22,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFBB0018)),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
