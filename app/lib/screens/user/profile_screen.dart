import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/models.dart';
import '../../state_providers.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../injection_container.dart' as di;
import 'restaurant_menu_screen.dart';
import 'customize_feed_screen.dart';
import 'support_conversation_list_screen.dart';
import 'my_reports_screen.dart';
import '../owner/restaurant_application_screen.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authViewModel = ref.watch(authViewModelProvider);
    final favorites = ref.watch(favoritesProvider);

    // Use restaurants from the API provider; show favorites or top 3 as default
    final allRestaurants = ref.watch(restaurantsProvider).state.restaurants;
    final favoriteRestaurants = allRestaurants
        .where((r) => favorites.favoriteRestaurantIds.contains(r.id))
        .toList();

    final userName = authViewModel.currentUser?.username ?? 'Amit Khayargoli';
    final userEmail = authViewModel.currentUser?.email ?? 'khayargoliamit99@gmail.com';

    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App Bar
              _buildAppBar(context),
              // Profile Header
              _buildProfileHeader(context, userName, userEmail, authProvider),
              // Your Roles (multi-role info)
              _buildRolesSection(context, authProvider),
              // Favorite Restaurants
              _buildFavoriteRestaurantsSection(context, ref, favoriteRestaurants),
              // Customize Feed (Settings)
              _buildPreferencesSection(context),

          // Support
          _buildSupportSection(context),

          // Business & Partnerships
          _buildBusinessSection(context),
              // Logout Button
              _buildLogoutButton(context, ref),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // App Bar
  // ──────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFE5E7EB)),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 2,
            offset: Offset(0, 1),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.settings_outlined, color: Color(0xFF8C8C8C)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Profile Header — Avatar + Name + Email
  // ──────────────────────────────────────────────

  Widget _buildProfileHeader(BuildContext context, String userName, String userEmail, AuthProvider authProvider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar with edit overlay
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              children: [
                // Avatar image or fallback
                Container(
                  width: 96,
                  height: 96,
                  decoration: ShapeDecoration(
                    color: Colors.white.withValues(alpha: 0),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(
                        width: 4,
                        color: Color(0x19BB0018),
                      ),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    shadows: const [
                      BoxShadow(
                        color: Color(0x19000000),
                        blurRadius: 6,
                        offset: Offset(0, 4),
                        spreadRadius: -4,
                      ),
                      BoxShadow(
                        color: Color(0x19000000),
                        blurRadius: 15,
                        offset: Offset(0, 10),
                        spreadRadius: -3,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9999),
                    child: _buildAvatarContent(context, authProvider),
                  ),
                ),
                // Camera/edit icon overlay (tappable)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => _pickAndUploadAvatar(context, authProvider),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: ShapeDecoration(
                        color: const Color(0xFFF5222D),
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(
                            width: 2,
                            color: Color(0xFFFAF9F9),
                          ),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x19000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                              spreadRadius: -2,
                            ),
                            BoxShadow(
                              color: Color(0x19000000),
                              blurRadius: 6,
                              offset: Offset(0, 4),
                              spreadRadius: -1,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Name
          SizedBox(
            width: double.infinity,
            child: Text(
              userName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.33,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Email
          SizedBox(
            width: double.infinity,
            child: Text(
              userEmail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF595959),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.43,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Avatar Content
  // ──────────────────────────────────────────────

  Widget _buildAvatarContent(BuildContext context, AuthProvider authProvider) {
    final avatarUrl = authProvider.avatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Image.network(
        avatarUrl,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildAvatarFallback(),
      );
    }

    return _buildAvatarFallback();
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: const Color(0xFFFFF1F0),
      child: const Icon(
        Icons.person,
        size: 44,
        color: Color(0xFFF5222D),
      ),
    );
  }

  /// Pick an image from gallery/camera, upload to Supabase, and update the profile.
  Future<void> _pickAndUploadAvatar(
      BuildContext context, AuthProvider authProvider) async {
    final picker = ImagePicker();
    // Capture messenger before any async gaps
    final messenger = ScaffoldMessenger.of(context);

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
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFFF5222D)),
                title: const Text('Take Photo'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFFF5222D)),
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
        if (context.mounted) {
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

      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    }
  }

  // ──────────────────────────────────────────────
  // Your Roles Section
  // ──────────────────────────────────────────────

  Widget _buildRolesSection(BuildContext context, AuthProvider authProvider) {
    final roles = authProvider.availableRoles;
    final activeRole = authProvider.activeRole;
    final hasMultipleRoles = roles.length > 1;

    String formatRole(String raw) {
      return raw
          .split('_')
          .map((w) => w.isNotEmpty
              ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
              : '')
          .join(' ');
    }

    IconData roleIcon(String role) {
      switch (role) {
        case 'RESTAURANT_OWNER': return Icons.store_rounded;
        case 'DELIVERY_BOY': return Icons.moped_rounded;
        default: return Icons.person_rounded;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFF1A1A1A)),
              const SizedBox(width: 8),
              const Text(
                'Your Account',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.33,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Active role badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(roleIcon(activeRole),
                          color: const Color(0xFFBB0018), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Currently viewing as',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF8E8E93)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatRole(activeRole),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1C1C),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFBB0018).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Active',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFBB0018),
                        ),
                      ),
                    ),
                  ],
                ),

                if (hasMultipleRoles) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 12),

                  // Other available roles
                  const Text('Other Roles',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: Color(0xFF8E8E93))),
                  const SizedBox(height: 8),
                  ...roles
                      .where((r) => r != activeRole)
                      .map((role) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () {
                                authProvider.switchActiveRole(role);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFE5E7EB)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(roleIcon(role),
                                        color: const Color(0xFF8E8E93),
                                        size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            formatRole(role),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1A1C1C),
                                            ),
                                          ),
                                          Text(
                                            role == 'RESTAURANT_OWNER'
                                                ? 'Manage your restaurant'
                                                : 'Accept delivery jobs',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF8E8E93),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded,
                                        size: 14, color: Color(0xFFBFBFBF)),
                                  ],
                                ),
                              ),
                            ),
                          )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Favorite Restaurants Section
  // ──────────────────────────────────────────────

  Widget _buildFavoriteRestaurantsSection(
    BuildContext context,
    WidgetRef ref,
    List<Restaurant> restaurants,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Favorite Restaurants',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.33,
                ),
              ),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('View all favorites')),
                  );
                },
                child: const Text(
                  'View All',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF5222D),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Restaurant Cards
          if (restaurants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.favorite_border_rounded,
                        size: 40, color: const Color(0xFFD9D9D9)),
                    const SizedBox(height: 8),
                    const Text(
                      'No favorite restaurants yet',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap the heart icon on a restaurant to add it',
                      style: TextStyle(
                        color: Color(0xFFBFBFBF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...restaurants.map(
              (restaurant) => _buildRestaurantCard(context, ref, restaurant),
            ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(BuildContext context, WidgetRef ref, Restaurant restaurant) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RestaurantMenuScreen(restaurant: restaurant),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          height: 112,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(8),
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x0C000000),
                blurRadius: 2,
                offset: Offset(0, 1),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Restaurant image
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  restaurant.bannerUrl,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.restaurant, color: Color(0xFFBFBFBF), size: 28),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                    const SizedBox(height: 6),
                    Text(
                      '${restaurant.rating} (120+) • ${restaurant.deliveryTimeMinutes} mins',
                      style: const TextStyle(
                        color: Color(0xFF595959),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.33,
                      ),
                    ),
                  ],
                ),
              ),
              // Favorite toggle
              GestureDetector(
                onTap: () {
                  ref.read(favoritesProvider.notifier).toggleRestaurant(restaurant.id);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ref
                            .read(favoritesProvider)
                            .isRestaurantFavorite(restaurant.id)
                        ? const Color(0xFFFFF1F0)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ref.read(favoritesProvider).isRestaurantFavorite(restaurant.id)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 22,
                    color: ref.read(favoritesProvider).isRestaurantFavorite(restaurant.id)
                        ? const Color(0xFFF5222D)
                        : const Color(0xFF8C8C8C),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Preferences Section
  // ──────────────────────────────────────────────

  Widget _buildPreferencesSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preferences',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
          const SizedBox(height: 8),
          _buildPreferenceCard(
            context,
            icon: Icons.tune_rounded,
            iconColor: const Color(0xFF9C27B0),
            title: 'Customize Feed',
            subtitle: 'Toggle home screen features like time-of-day greeting and personalized suggestions',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CustomizeFeedScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 28, color: iconColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.33,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF8C8C8C), size: 20),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Support Section
  // ──────────────────────────────────────────────

  Widget _buildSupportSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Support',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
          const SizedBox(height: 8),
          _buildPreferenceCard(
            context,
            icon: Icons.headset_mic_rounded,
            iconColor: const Color(0xFF1967D2),
            title: 'Contact Support',
            subtitle: 'Get help with your orders or report an issue',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SupportConversationListScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildPreferenceCard(
            context,
            icon: Icons.flag_outlined,
            iconColor: const Color(0xFFF9A825),
            title: 'My Reports',
            subtitle: 'View all your submitted problem reports and their statuses',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyReportsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Business & Partnerships Section
  // ──────────────────────────────────────────────

  Widget _buildBusinessSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Business & Partnerships',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
          const SizedBox(height: 8),
          // Register as Restaurant Owner
          _buildBusinessCard(
            context,
            imagePath: 'assets/img/Profile/Restaurantowner.png',
            title: 'Register as Restaurant Owner',
            subtitle: 'List your store and reach more customers',
            onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RestaurantApplicationScreen(),
              ),
            );
          },
          ),
          const SizedBox(height: 8),
          // Become a Delivery Partner
          _buildBusinessCard(
            context,
            imagePath: 'assets/img/Profile/delivery.png',
            title: 'Become a Delivery Partner',
            subtitle: 'Earn on your own schedule',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Delivery partner registration coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessCard(
    BuildContext context, {
    required String imagePath,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      imagePath,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.33,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF8C8C8C), size: 20),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Logout Button
  // ──────────────────────────────────────────────

  Widget _buildLogoutButton(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Logout'),
                content: const Text('Are you sure you want to logout?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      // Capture what we need before any async gap
                      final authProvider = context.read<AuthProvider>();
                      final dialogNavigator = Navigator.of(ctx);
                      final mainNavigator = Navigator.of(context);

                      // Clear the Riverpod auth state + Supabase session
                      ref.read(authViewModelProvider.notifier).logout();
                      // Clear the Provider auth state (JWT token, SharedPreferences, etc.)
                      await authProvider.logout();
                      // Pop the dialog
                      dialogNavigator.pop();
                      // Navigate to login screen, clearing the nav stack
                      mainNavigator.pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                        (route) => false,
                      );
                    },
                    child: const Text(
                      'Logout',
                      style: TextStyle(color: Color(0xFFF5222D)),
                    ),
                  ),
                ],
              ),
            );
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFF5222D)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Logout',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFF5222D),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}
