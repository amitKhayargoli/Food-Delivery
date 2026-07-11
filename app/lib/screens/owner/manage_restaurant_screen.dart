import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

class ManageRestaurantScreen extends StatefulWidget {
  const ManageRestaurantScreen({super.key});

  @override
  State<ManageRestaurantScreen> createState() => _ManageRestaurantScreenState();
}

class _ManageRestaurantScreenState extends State<ManageRestaurantScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _successMessage;

  // Controllers for editable fields
  final _restaurantNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Dropdown / picker values
  String? _selectedCuisine;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  String? _selectedLogoPath;
  String? _selectedCoverImagePath;
  String? _currentLogoUrl;
  String? _currentCoverImageUrl;

  // Cuisine options (matching restaurant_application_screen)
  static const List<String> _cuisineOptions = [
    'Nepali',
    'Indian',
    'Chinese',
    'Italian',
    'Mexican',
    'Japanese',
    'Thai',
    'Continental',
    'Momo & Fast Food',
    'Newari',
    'South Indian',
    'Korean',
    'Turkish',
    'Bakery & Cafe',
  ];

  bool get _hasChanges {
    if (_profile == null) return false;

    final originalName = (_profile!['restaurant_name'] as String?) ?? '';
    final originalDesc = (_profile!['description'] as String?) ?? '';
    final originalAddr = (_profile!['address'] as String?) ?? '';
    final originalPhone = (_profile!['phone'] as String?) ?? '';
    final originalEmail = (_profile!['email'] as String?) ?? '';
    final originalCuisine = (_profile!['cuisine_type'] as String?) ?? '';
    final originalOpen = (_profile!['open_time'] as String?) ?? '';
    final originalClose = (_profile!['close_time'] as String?) ?? '';

    final nameChanged = _restaurantNameCtrl.text.trim() != originalName;
    final descChanged = _descriptionCtrl.text.trim() != originalDesc;
    final addrChanged = _addressCtrl.text.trim() != originalAddr;
    final phoneChanged = _phoneCtrl.text.trim() != originalPhone;
    final emailChanged = _emailCtrl.text.trim() != originalEmail;
    final cuisineChanged = _selectedCuisine != originalCuisine;
    final openChanged = _openTime != null && _toTimeString(_openTime!) != originalOpen;
    final closeChanged = _closeTime != null && _toTimeString(_closeTime!) != originalClose;
    final logoChanged = _selectedLogoPath != null;
    final coverChanged = _selectedCoverImagePath != null;

    return nameChanged || descChanged || addrChanged || phoneChanged ||
        emailChanged || cuisineChanged || openChanged || closeChanged ||
        logoChanged || coverChanged;
  }

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _restaurantNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _fetchProfile() async {
    final token = _token;
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Not authenticated. Please log in.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final profile = await api.getMyRestaurantProfile(token: token);

      if (!mounted) return;

      if (profile == null) {
        setState(() {
          _error = 'No approved restaurant found for your account.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _profile = profile;
        _restaurantNameCtrl.text = (profile['restaurant_name'] as String?) ?? '';
        _descriptionCtrl.text = (profile['description'] as String?) ?? '';
        _addressCtrl.text = (profile['address'] as String?) ?? '';
        _phoneCtrl.text = (profile['phone'] as String?) ?? '';
        _emailCtrl.text = (profile['email'] as String?) ?? '';
        _selectedCuisine = profile['cuisine_type'] as String?;
        _currentLogoUrl = profile['logo_url'] as String?;
        _currentCoverImageUrl = profile['cover_image_url'] as String?;

        final openStr = profile['open_time'] as String?;
        if (openStr != null && openStr.contains(':')) {
          final parts = openStr.split(':');
          _openTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
        final closeStr = profile['close_time'] as String?;
        if (closeStr != null && closeStr.contains(':')) {
          final parts = closeStr.split(':');
          _closeTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 21,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }

        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load restaurant profile. Check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage({required bool isLogo}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result == null) return;

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File size exceeds 5MB limit.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        if (isLogo) {
          _selectedLogoPath = filePath;
        } else {
          _selectedCoverImagePath = filePath;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not access gallery.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _save() async {
    final token = _token;
    if (token == null) return;

    if (!mounted) return;
    setState(() {
      _isSaving = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final storage = di.sl<StorageService>();
      final api = di.sl<ApiService>();

      // Upload new logo if selected
      String? logoUrl = _currentLogoUrl;
      if (_selectedLogoPath != null) {
        final userId = context.read<AuthProvider>().username ?? 'owner';
        logoUrl = await storage.uploadFile(
          filePath: _selectedLogoPath!,
          bucket: 'restaurant-images',
          folder: 'logos',
          userId: userId,
          token: token,
        );
      }

      // Upload new cover image if selected
      String? coverImageUrl = _currentCoverImageUrl;
      if (_selectedCoverImagePath != null) {
        final userId = context.read<AuthProvider>().username ?? 'owner';
        coverImageUrl = await storage.uploadFile(
          filePath: _selectedCoverImagePath!,
          bucket: 'restaurant-images',
          folder: 'covers',
          userId: userId,
          token: token,
        );
      }

      final updateData = <String, dynamic>{};
      updateData['restaurant_name'] = _restaurantNameCtrl.text.trim();
      updateData['description'] = _descriptionCtrl.text.trim();
      updateData['address'] = _addressCtrl.text.trim();
      updateData['phone'] = _phoneCtrl.text.trim();
      updateData['email'] = _emailCtrl.text.trim();
      updateData['cuisine_type'] = _selectedCuisine;
      if (_openTime != null) updateData['open_time'] = _toTimeString(_openTime!);
      if (_closeTime != null) updateData['close_time'] = _toTimeString(_closeTime!);
      updateData['logo_url'] = logoUrl;
      updateData['cover_image_url'] = coverImageUrl;

      await api.updateRestaurantProfile(data: updateData, token: token);

      if (!mounted) return;
      setState(() {
        _successMessage = 'Restaurant profile updated successfully!';
        _isSaving = false;
        _selectedLogoPath = null;
        _selectedCoverImagePath = null;
        _currentLogoUrl = logoUrl;
        _currentCoverImageUrl = coverImageUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restaurant profile updated successfully!'),
          backgroundColor: Color(0xFF1E8E3E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final message = _extractDioError(e);
      setState(() {
        _error = message;
        _isSaving = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'An unexpected error occurred.';
        _isSaving = false;
      });
    }
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFAF9F9),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(_hasChanges),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1A1C1C)),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Manage Restaurant',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                height: 1.33,
              ),
            ),
          ),
          if (_hasChanges && !_isSaving)
            GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFBB0018),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text(
              'Loading restaurant profile...',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null && _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchProfile,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover Image & Logo ──────────────────
          _buildImageSection(),
          const SizedBox(height: 24),

          // ── Restaurant Name ─────────────────────
          _buildSectionLabel('Restaurant Name'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _restaurantNameCtrl,
            hint: 'Your restaurant name',
          ),
          const SizedBox(height: 20),

          // ── Description ─────────────────────────
          _buildSectionLabel('Description'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _descriptionCtrl,
            hint: 'Describe your restaurant...',
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // ── Address ─────────────────────────────
          _buildSectionLabel('Address'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _addressCtrl,
            hint: 'Full restaurant address',
          ),
          const SizedBox(height: 20),

          // ── Phone & Email ───────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel('Phone'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _phoneCtrl,
                      hint: 'Phone number',
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel('Email'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _emailCtrl,
                      hint: 'Email address',
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Cuisine Type ────────────────────────
          _buildSectionLabel('Cuisine Type'),
          const SizedBox(height: 8),
          _buildCuisineDropdown(),
          const SizedBox(height: 20),

          // ── Operating Hours ─────────────────────
          _buildSectionLabel('Operating Hours'),
          const SizedBox(height: 8),
          _buildTimePickers(),
          const SizedBox(height: 32),

          // ── Error message ───────────────────────
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFF5222D).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFF5222D), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFF5222D), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Save Button ─────────────────────────
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving || !_hasChanges ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBB0018),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _hasChanges ? 'Save Changes' : 'No Changes',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.50,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Image Section ────────────────────────────

  Widget _buildImageSection() {
    final hasCover = _currentCoverImageUrl != null || _selectedCoverImagePath != null;
    final hasLogo = _currentLogoUrl != null || _selectedLogoPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Restaurant Images'),
        const SizedBox(height: 8),
        Row(
          children: [
            // Cover image
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () => _pickImage(isLogo: false),
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    image: hasCover
                        ? DecorationImage(
                            image: _selectedCoverImagePath != null
                                ? FileImage(File(_selectedCoverImagePath!))
                                : NetworkImage(_currentCoverImageUrl!) as ImageProvider,
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: hasCover
                      ? null
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined, size: 32, color: Color(0xFFBFBFBF)),
                              SizedBox(height: 4),
                              Text(
                                'Cover Image',
                                style: TextStyle(
                                  color: Color(0xFFBFBFBF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Logo
            GestureDetector(
              onTap: () => _pickImage(isLogo: true),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  image: hasLogo
                      ? DecorationImage(
                          image: _selectedLogoPath != null
                              ? FileImage(File(_selectedLogoPath!))
                              : NetworkImage(_currentLogoUrl!) as ImageProvider,
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: hasLogo
                    ? null
                    : const Center(
                        child: Icon(Icons.store_rounded, size: 32, color: Color(0xFFBFBFBF)),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap images to change them',
          style: TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ── Cuisine Dropdown ─────────────────────────

  Widget _buildCuisineDropdown() {
    return Container(
      width: double.infinity,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _cuisineOptions.contains(_selectedCuisine) ? _selectedCuisine : null,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1A1A1A), size: 22),
          hint: Text(
            _selectedCuisine ?? 'Select cuisine type',
            style: TextStyle(
              color: _selectedCuisine != null ? const Color(0xFF1A1A1A) : const Color(0xFFBFBFBF),
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          items: _cuisineOptions.map((cuisine) {
            return DropdownMenuItem<String>(
              value: cuisine,
              child: Text(
                cuisine,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedCuisine = value),
        ),
      ),
    );
  }

  // ── Time Pickers ─────────────────────────────

  Widget _buildTimePickers() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTimeSlot(
              label: 'Open',
              icon: Icons.wb_sunny_outlined,
              time: _openTime,
              onTap: () => _pickTime(isOpen: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: 24,
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFFBFBFBF),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Expanded(
            child: _buildTimeSlot(
              label: 'Close',
              icon: Icons.nightlight_outlined,
              time: _closeTime,
              onTap: () => _pickTime(isOpen: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlot({
    required String label,
    required IconData icon,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) {
    final isSelected = time != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF1F0) : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFF5222D).withValues(alpha: 0.3) : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isSelected ? const Color(0xFFF5222D) : const Color(0xFFBFBFBF)),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8C8C8C),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isSelected ? _formatTime(time) : 'Select',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF1A1A1A) : const Color(0xFFBFBFBF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final initial = isOpen ? (_openTime ?? const TimeOfDay(hour: 9, minute: 0)) : (_closeTime ?? const TimeOfDay(hour: 21, minute: 0));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFF5222D)),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) {
      setState(() {
        if (isOpen) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
      });
    }
  }

  // ── Helpers ──────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF262626),
        fontSize: 14,
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        height: 1.50,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(
          color: Color(0xFF1A1A1A),
          fontSize: 15,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFFBFBFBF),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute.toString().padLeft(2, '0');
    return '$hour12:$minuteStr $period';
  }

  String _toTimeString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _extractDioError(DioException e) {
    if (e.response?.data is Map<String, dynamic>) {
      final data = e.response!.data as Map<String, dynamic>;
      if (data.containsKey('error')) {
        return data['error'] as String;
      }
    }
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Please check your network.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Could not connect to the server.';
    }
    return 'Something went wrong. Please try again.';
  }
}
