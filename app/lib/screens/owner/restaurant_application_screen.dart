import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../injection_container.dart' as di;
import '../../state_providers.dart';

class RestaurantApplicationScreen extends ConsumerStatefulWidget {
  const RestaurantApplicationScreen({super.key});

  @override
  ConsumerState<RestaurantApplicationScreen> createState() =>
      _RestaurantApplicationScreenState();
}

class _RestaurantApplicationScreenState
    extends ConsumerState<RestaurantApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  // Contact Step
  final _ownerNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Business Step
  final _restaurantNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _panNumberCtrl = TextEditingController();
  String? _selectedPanFilePath;
  bool _isPanUploading = false;

  // Restaurant Details Step
  final _descriptionCtrl = TextEditingController();
  final _cuisineTypeCtrl = TextEditingController();
  String? _selectedCoverImagePath;
  bool _isCoverImageUploading = false;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  bool _isLoading = false;
  bool _submitted = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _ownerNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _restaurantNameCtrl.dispose();
    _addressCtrl.dispose();
    _panNumberCtrl.dispose();
    _descriptionCtrl.dispose();
    _cuisineTypeCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (step < 0 || step > 2) return;

    // Validate current step before advancing
    if (step > _currentStep) {
      switch (_currentStep) {
        case 0:
          if (_ownerNameCtrl.text.trim().isEmpty) {
            setState(() => _error = 'Please enter your full name.');
            return;
          }
          if (_emailCtrl.text.trim().isEmpty || !_emailCtrl.text.contains('@')) {
            setState(() => _error = 'Please enter a valid email address.');
            return;
          }
          if (_phoneCtrl.text.trim().length < 10) {
            setState(() => _error = 'Please enter a valid phone number.');
            return;
          }
          break;
        case 1:
          if (_restaurantNameCtrl.text.trim().isEmpty) {
            setState(() => _error = 'Please enter your restaurant name.');
            return;
          }
          if (_addressCtrl.text.trim().isEmpty) {
            setState(() => _error = 'Please enter your restaurant address.');
            return;
          }
          if (_panNumberCtrl.text.trim().isEmpty) {
            setState(() => _error = 'Please enter your PAN number.');
            return;
          }
          if (_selectedPanFilePath == null) {
            setState(() => _error = 'Please upload your PAN certificate.');
            return;
          }
          break;
      }
    }

    setState(() {
      _currentStep = step;
      _error = null;
    });
  }

  Future<void> _pickPanCertificate() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        setState(
          () => _error = 'File size exceeds 5MB limit. Please choose a smaller file.',
        );
        return;
      }

      setState(() {
        _selectedPanFilePath = pickedFile.path;
        _error = null;
      });
    }
  }

  Future<void> _pickCoverImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        setState(
          () => _error = 'Cover image exceeds 5MB limit. Please choose a smaller file.',
        );
        return;
      }

      setState(() {
        _selectedCoverImagePath = pickedFile.path;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authVm = ref.read(authViewModelProvider);
      final token = authVm.currentUser?.token ?? '';

      if (token.isEmpty) {
        setState(() {
          _error = 'Please log in first.';
          _isLoading = false;
        });
        return;
      }

      final userId = authVm.currentUser?.id ?? 'anon';
      final storage = di.sl<StorageService>();

      // Upload PAN certificate
      setState(() => _isPanUploading = true);
      final panCertificateUrl = await storage.uploadPanCertificate(
        filePath: _selectedPanFilePath!,
        userId: userId,
        token: token,
      );
      setState(() => _isPanUploading = false);

      // Upload cover image (optional)
      String? coverImageUrl;
      if (_selectedCoverImagePath != null) {
        setState(() => _isCoverImageUploading = true);
        coverImageUrl = await storage.uploadCoverImage(
          filePath: _selectedCoverImagePath!,
          userId: userId,
          token: token,
        );
        setState(() => _isCoverImageUploading = false);
      }

      // Submit the application
      final api = di.sl<ApiService>();
      final response = await api.submitRestaurantApplication(
        restaurantName: _restaurantNameCtrl.text.trim(),
        ownerName: _ownerNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        panNumber: _panNumberCtrl.text.trim(),
        panCertificateUrl: panCertificateUrl,
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        coverImageUrl: coverImageUrl,
        openTime:
            _openTime != null ? _toTimeString(_openTime!) : null,
        closeTime:
            _closeTime != null ? _toTimeString(_closeTime!) : null,
        cuisineType: _cuisineTypeCtrl.text.trim().isEmpty
            ? null
            : _cuisineTypeCtrl.text.trim(),
        token: token,
      );

      setState(() {
        _submitted = true;
        _successMessage = response.message;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'An unexpected error occurred: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _isPanUploading = false;
        _isCoverImageUploading = false;
      });
    }
  }

  // ──────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      body: _submitted ? _buildSuccessView() : _buildStepContent(),
    );
  }

  Widget _buildStepContent() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Form(
                key: _formKey,
                child: IndexedStack(
                  index: _currentStep,
                  children: [
                    _buildContactStep(),
                    _buildBusinessStep(),
                    _buildRestaurantDetailsStep(),
                  ],
                ),
              ),
            ),
          ),
          // Bottom action bar
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Step 0 — Contact
  // ──────────────────────────────────────────────

  Widget _buildContactStep() {
    return Column(
      children: [
        const SizedBox(height: 24),
        // Header row: back button + logo
        Row(
          children: [
            // Back button circle
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x1A000000),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF1A1C1C),
                  size: 20,
                ),
              ),
            ),
            const Spacer(),
            // Logo
            Image.asset(
              'assets/img/logo.png',
              width: 160,
              height: 89,
              fit: BoxFit.contain,
            ),
            const Spacer(),
            // Spacer to balance the back button width
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 8),
        // Heading
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Partner with us',
            style: TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 24,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(
          width: double.infinity,
          child: Text(
            "Let's start with your contact details. This helps us\nverify your account.",
            style: TextStyle(
              color: Color(0xFF5E3F3C),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        _buildProgressIndicator(activeStep: 0),
        const SizedBox(height: 24),
        // Form card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: ShapeDecoration(
            color: const Color(0xFFFAF9F9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            shadows: [
              BoxShadow(
                color: const Color(0x141B1C1C),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Owner's Full Name
              _stepTextField(
                label: "Owner's Full Name",
                hint: 'e.g. Jane Doe',
                controller: _ownerNameCtrl,
              ),
              const SizedBox(height: 24),
              // Business Email Address
              _stepTextField(
                label: 'Business Email Address',
                hint: 'jane@restaurant.com',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),
              // Mobile Number
              _stepTextField(
                label: 'Mobile Number',
                hint: '+977 98XXXXXXXX',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 4),
              const SizedBox(
                width: double.infinity,
                child: Text(
                  "We'll send a verification code to this number.",
                  style: TextStyle(
                    color: Color(0xFF949494),
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    height: 1.33,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Extra space so the bottom bar doesn't overlap
        const SizedBox(height: 24),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Step 1 — Business (simplified layout)
  // ──────────────────────────────────────────────

  Widget _buildBusinessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Progress indicator
        _buildProgressIndicator(activeStep: 1),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: ShapeDecoration(
            color: const Color(0xFFFAF9F9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            shadows: [
              BoxShadow(
                color: const Color(0x141B1C1C),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Business Information',
                style: TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 18,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tell us about your restaurant.',
                style: TextStyle(
                  color: Color(0xFF5E3F3C),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              _stepTextField(
                label: 'Restaurant Name',
                hint: 'e.g. Dailo Kitchen',
                controller: _restaurantNameCtrl,
              ),
              const SizedBox(height: 20),
              _stepTextField(
                label: 'Address',
                hint: 'Full restaurant address',
                controller: _addressCtrl,
              ),
              const SizedBox(height: 20),
              _stepTextField(
                label: 'PAN Number',
                hint: 'e.g. 123456789',
                controller: _panNumberCtrl,
              ),
              const SizedBox(height: 20),
              // PAN Upload
              _buildMiniUploadSection(),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stepTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              height: 1.29,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'Inter',
              color: Color(0xFF1A1C1C),
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFF5C5C5C),
                fontSize: 14,
                fontFamily: 'Inter',
              ),
              filled: true,
              fillColor: const Color(0xFFF4F3F3),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFFEB1727),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAN Certificate',
          style: TextStyle(
            color: Color(0xFF1A1C1C),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
            height: 1.29,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _isLoading ? null : _pickPanCertificate,
          child: Container(
            width: double.infinity,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _selectedPanFilePath != null
                  ? const Color(0xFFF6FFED)
                  : const Color(0xFFF4F3F3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedPanFilePath != null
                      ? Icons.check_circle
                      : Icons.cloud_upload_outlined,
                  size: 20,
                  color: _selectedPanFilePath != null
                      ? const Color(0xFF52C41A)
                      : const Color(0xFF5C5C5C),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedPanFilePath != null
                        ? _selectedPanFilePath!.split('/').last
                        : 'Tap to upload PAN certificate',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedPanFilePath != null
                          ? const Color(0xFF1A1C1C)
                          : const Color(0xFF5C5C5C),
                      fontFamily: 'Inter',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedPanFilePath != null)
                  GestureDetector(
                    onTap: () => setState(() => _selectedPanFilePath = null),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF8C8C8C),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Step 2 — Restaurant Details (simplified layout)
  // ──────────────────────────────────────────────

  Widget _buildRestaurantDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Progress indicator
        _buildProgressIndicator(activeStep: 2),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: ShapeDecoration(
            color: const Color(0xFFFAF9F9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            shadows: [
              BoxShadow(
                color: const Color(0x141B1C1C),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Restaurant Details',
                style: TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 18,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Help customers discover your restaurant.',
                style: TextStyle(
                  color: Color(0xFF5E3F3C),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              _stepTextField(
                label: 'Restaurant Description (optional)',
                hint: 'Tell customers about your restaurant',
                controller: _descriptionCtrl,
              ),
              const SizedBox(height: 20),
              // Cover image upload
              _buildMiniCoverUpload(),
              const SizedBox(height: 20),
              // Opening Hours
              _buildSimpleTimePicker(),
              const SizedBox(height: 20),
              _stepTextField(
                label: 'Cuisine Type (optional)',
                hint: 'e.g. Nepali, Indian, Chinese',
                controller: _cuisineTypeCtrl,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Error
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
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
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildMiniCoverUpload() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Cover Image',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                height: 1.29,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Optional',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF757575),
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _isLoading ? null : _pickCoverImage,
          child: Container(
            width: double.infinity,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _selectedCoverImagePath != null
                  ? const Color(0xFFFFF8E1)
                  : const Color(0xFFF4F3F3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedCoverImagePath != null
                      ? Icons.check_circle
                      : Icons.image_outlined,
                  size: 20,
                  color: _selectedCoverImagePath != null
                      ? const Color(0xFFF57C00)
                      : const Color(0xFF5C5C5C),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedCoverImagePath != null
                        ? _selectedCoverImagePath!.split('/').last
                        : 'Tap to upload cover image',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedCoverImagePath != null
                          ? const Color(0xFF1A1C1C)
                          : const Color(0xFF5C5C5C),
                      fontFamily: 'Inter',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedCoverImagePath != null)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _selectedCoverImagePath = null),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF8C8C8C),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleTimePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Opening Hours',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                height: 1.29,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Optional',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF757575),
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _miniTimeSlot(
                label: 'Open',
                icon: Icons.wb_sunny_outlined,
                time: _openTime,
                onTap: _pickOpenTime,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniTimeSlot(
                label: 'Close',
                icon: Icons.nightlight_outlined,
                time: _closeTime,
                onTap: _pickCloseTime,
              ),
            ),
          ],
        ),
        if (_openTime != null && _closeTime != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_formatTime(_openTime!)} - ${_formatTime(_closeTime!)}',
              style: TextStyle(
                fontSize: 13,
                color: _isCloseBeforeOpen
                    ? const Color(0xFFF57C00)
                    : const Color(0xFF52C41A),
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _miniTimeSlot({
    required String label,
    required IconData icon,
    required TimeOfDay? time,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: time != null ? const Color(0xFFFFF1F0) : const Color(0xFFF4F3F3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF5C5C5C)),
            const SizedBox(width: 8),
            Text(
              time != null ? _formatTime(time) : label,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Inter',
                color: time != null
                    ? const Color(0xFF1A1C1C)
                    : const Color(0xFF5C5C5C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Progress Indicator
  // ──────────────────────────────────────────────

  Widget _buildProgressIndicator({required int activeStep}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Stack(
        children: [
          // Connecting lines
          Positioned(
            left: 103.30,
            top: 24,
            child: Container(
              width: 48.19,
              height: 2,
              decoration: BoxDecoration(
                color: activeStep >= 1
                    ? const Color(0xFFEB1727)
                    : const Color(0xFFE3E2E2),
              ),
            ),
          ),
          Positioned(
            left: 213.63,
            top: 24,
            child: Container(
              width: 48.19,
              height: 2,
              decoration: BoxDecoration(
                color: activeStep >= 2
                    ? const Color(0xFFEB1727)
                    : const Color(0xFFE3E2E2),
              ),
            ),
          ),
          // Step 1 — Contact
          Positioned(
            left: 48.19,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: const Color(0xFFFAF9F9),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: activeStep >= 0
                          ? const Color(0xFFEB1727)
                          : const Color(0xFFE3E2E2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '1',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: activeStep >= 0
                              ? Colors.white
                              : const Color(0xFF5C5C5C),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          height: 1.29,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Contact',
                    style: TextStyle(
                      color: activeStep >= 0
                          ? const Color(0xFFEB1727)
                          : const Color(0xFF5C5C5C),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      height: 1.40,
                      letterSpacing: 0.20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Step 2 — Business
          Positioned(
            left: 151.48,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: const Color(0xFFFAF9F9),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: activeStep >= 1
                          ? const Color(0xFFEB1727)
                          : const Color(0xFFE3E2E2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '2',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: activeStep >= 1
                              ? Colors.white
                              : const Color(0xFF5C5C5C),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          height: 1.29,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Business',
                    style: TextStyle(
                      color: activeStep >= 1
                          ? const Color(0xFFEB1727)
                          : const Color(0xFF5C5C5C),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      height: 1.40,
                      letterSpacing: 0.20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Step 3 — Menu
          Positioned(
            left: 261.81,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: const Color(0xFFFAF9F9),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: activeStep >= 2
                          ? const Color(0xFFEB1727)
                          : const Color(0xFFE3E2E2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '3',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: activeStep >= 2
                              ? Colors.white
                              : const Color(0xFF5C5C5C),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          height: 1.29,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Menu',
                    style: TextStyle(
                      color: activeStep >= 2
                          ? const Color(0xFFEB1727)
                          : const Color(0xFF5C5C5C),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      height: 1.40,
                      letterSpacing: 0.20,
                    ),
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
  //  Bottom Action Bar
  // ──────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFFAF9F9),
        border: Border(
          top: BorderSide(width: 1, color: Colors.white),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      if (_currentStep < 2) {
                        _goToStep(_currentStep + 1);
                      } else {
                        _submit();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEB1727),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _currentStep == 0
                          ? 'Continue to Business Details'
                          : _currentStep == 1
                              ? 'Continue to Restaurant Details'
                              : _isPanUploading
                                  ? 'Uploading PAN Certificate...'
                                  : _isCoverImageUploading
                                      ? 'Uploading Cover Image...'
                                      : 'Submit Application',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (_currentStep > 0)
            SizedBox(
              width: double.infinity,
              height: 36,
              child: TextButton(
                onPressed: () => _goToStep(_currentStep - 1),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFBB0018),
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  'Back',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.20,
                  ),
                ),
              ),
            ),
          // "Already have an account?" link (only on step 0)
          if (_currentStep == 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Already have an account? ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF5E3F3C),
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    height: 1.33,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Log In',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFBB0018),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.20,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Success View
  // ──────────────────────────────────────────────

  Widget _buildSuccessView() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.check_circle, size: 80, color: Color(0xFF4CAF50)),
            const SizedBox(height: 24),
            const Text(
              'Application Submitted!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1C1C),
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _successMessage ?? 'Your application is pending admin review.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF757575),
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFF57C00), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your PAN certificate will be reviewed by the admin. '
                      'You will be notified once your application is approved.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF795548)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5222D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Back to Profile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────────────

  int _timeToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool get _isCloseBeforeOpen =>
      _openTime != null &&
      _closeTime != null &&
      _timeToMinutes(_closeTime!) <= _timeToMinutes(_openTime!);

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

  Future<void> _pickOpenTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _openTime ?? const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFF5222D),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _openTime = picked);
    }
  }

  Future<void> _pickCloseTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _closeTime ?? const TimeOfDay(hour: 21, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFF5222D),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _closeTime = picked);
    }
  }
}
