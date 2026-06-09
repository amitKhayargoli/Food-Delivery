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
  String? _selectedCuisine;

  // Restaurant Details Step
  String? _selectedCoverImagePath;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  String? _selectedFoodCategory;

  static const List<String> _foodCategoryOptions = [
    'All (Vegetarian & Non-Vegetarian)',
    'Vegetarian Only',
    'Non-Vegetarian Only',
    'Vegan',
    'Breakfast & Brunch',
    'Beverages & Desserts',
  ];

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

  // Per-field error states
  String? _ownerNameError;
  String? _emailError;
  String? _phoneError;
  String? _restaurantNameError;
  String? _addressError;
  String? _cuisineError;
  String? _panNumberError;
  String? _panFileError;
  String? _foodCategoryError;

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

    super.dispose();
  }

  void _goToStep(int step) {
    if (step < 0 || step > 2) return;

    // Validate current step before advancing
    if (step > _currentStep) {
      bool valid = true;

      switch (_currentStep) {
        case 0:
          setState(() {
            _ownerNameError = _ownerNameCtrl.text.trim().isEmpty
                ? 'Please enter your full name.'
                : null;
            _emailError = _emailCtrl.text.trim().isEmpty
                ? 'Please enter your email address.'
                : !_emailCtrl.text.contains('@')
                    ? 'Please enter a valid email address.'
                    : null;
            final phone = _phoneCtrl.text.trim();
            if (phone.isEmpty) {
              _phoneError = 'Please enter your phone number.';
            } else if (!RegExp(r'^9\d{9}$').hasMatch(phone)) {
              _phoneError = 'Please enter a valid phone number starting with 9.';
            } else {
              _phoneError = null;
            }
          });
          valid = _ownerNameError == null &&
              _emailError == null &&
              _phoneError == null;
          if (!valid) return;
          break;

        case 1:
          setState(() {
            _restaurantNameError = _restaurantNameCtrl.text.trim().isEmpty
                ? 'Please enter your restaurant name.'
                : null;
            _addressError = _addressCtrl.text.trim().isEmpty
                ? 'Please enter your restaurant address.'
                : null;
            _cuisineError = _selectedCuisine == null
                ? 'Please select your cuisine type.'
                : null;
            _panNumberError = _panNumberCtrl.text.trim().isEmpty
                ? 'Please enter your PAN number.'
                : null;
            _panFileError = _selectedPanFilePath == null
                ? 'Please upload your PAN certificate.'
                : null;
          });
          valid = _restaurantNameError == null &&
              _addressError == null &&
              _cuisineError == null &&
              _panNumberError == null &&
              _panFileError == null;
          if (!valid) return;
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
        _panFileError = null;
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
      final panCertificateUrl = await storage.uploadPanCertificate(
        filePath: _selectedPanFilePath!,
        userId: userId,
        token: token,
      );

      // Upload cover image (optional)
      String? coverImageUrl;
      if (_selectedCoverImagePath != null) {
        coverImageUrl = await storage.uploadCoverImage(
          filePath: _selectedCoverImagePath!,
          userId: userId,
          token: token,
        );
      }

      // Submit the application
      final api = di.sl<ApiService>();
      final response = await api.submitRestaurantApplication(
        restaurantName: _restaurantNameCtrl.text.trim(),
        ownerName: _ownerNameCtrl.text.trim(),
        phone: '+977${_phoneCtrl.text.trim()}',
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        panNumber: _panNumberCtrl.text.trim(),
        panCertificateUrl: panCertificateUrl,
        description: null,
        coverImageUrl: coverImageUrl,
        openTime:
            _openTime != null ? _toTimeString(_openTime!) : null,
        closeTime:
            _closeTime != null ? _toTimeString(_closeTime!) : null,
        cuisineType: _selectedCuisine,
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
      setState(() => _isLoading = false);
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
              child: _buildCurrentStep(),
            ),
          ),
          // Bottom action bar (hidden on steps with inline buttons)
          if (_currentStep == 0) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    // Only build the current step — avoids IndexedStack sizing issues
    // with double.infinity constraints inside SingleChildScrollView.
    switch (_currentStep) {
      case 0:
        return _buildContactStep();
      case 1:
        return _buildBusinessStep();
      case 2:
        return _buildRestaurantDetailsStep();
      default:
        return _buildContactStep();
    }
  }

  // ──────────────────────────────────────────────
  //  Step 0 — Contact
  // ──────────────────────────────────────────────

  Widget _buildContactStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
            _buildLogo(),
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
                errorText: _ownerNameError,
                onChanged: (_) {
                  if (_ownerNameError != null) {
                    setState(() => _ownerNameError = null);
                  }
                },
              ),
              const SizedBox(height: 24),
              // Business Email Address
              _stepTextField(
                label: 'Business Email Address',
                hint: 'jane@restaurant.com',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                onChanged: (_) {
                  if (_emailError != null) {
                    setState(() => _emailError = null);
                  }
                },
              ),
              const SizedBox(height: 24),
              // Mobile Number (with country code prefix)
              const SizedBox(
                width: double.infinity,
                child: Text(
                  'Mobile Number',
                  style: TextStyle(
                    color: Color(0xFF1A1C1C),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    height: 1.29,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      width: 1,
                      color: _phoneError != null
                          ? const Color(0xFFF5222D)
                          : const Color(0xFFE8E8E8),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  color: _phoneError != null
                      ? const Color(0xFFFFF1F0)
                      : Colors.transparent,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                        controller: _phoneCtrl,
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
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        // Extra space so the bottom bar doesn't overlap
        const SizedBox(height: 24),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Step 1 — Business (v2 with full design)
  // ──────────────────────────────────────────────

  Widget _buildBusinessStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        // Header row: back button + logo
        Row(
          children: [
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
            _buildLogo(),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 8),
        // Title
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Business Information',
            textAlign: TextAlign.center,
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
            'Tell us about your restaurant to set up your profile.',
            textAlign: TextAlign.center,
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
        _buildProgressIndicator(activeStep: 1),
        const SizedBox(height: 24),
        // Form card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          decoration: ShapeDecoration(
            color: const Color(0xFFFAF9F9),
            shape: RoundedRectangleBorder(
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
              const SizedBox(height: 8),
              // Restaurant Name
              _buildFieldLabel('Restaurant Name'),
              const SizedBox(height: 4),
              _businessTextField(
                controller: _restaurantNameCtrl,
                hint: 'e.g., The Spicy Skillet',
                errorText: _restaurantNameError,
                onChanged: (_) {
                  if (_restaurantNameError != null) {
                    setState(() => _restaurantNameError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              // Full Address
              _buildFieldLabel('Full Address'),
              const SizedBox(height: 4),
              _businessTextField(
                controller: _addressCtrl,
                hint: 'Full restaurant address',
                errorText: _addressError,
                onChanged: (_) {
                  if (_addressError != null) {
                    setState(() => _addressError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              // Cuisine Type
              _buildFieldLabel('Cuisine Type'),
              const SizedBox(height: 4),
              _buildCuisineDropdown(),
              if (_cuisineError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _cuisineError!,
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // PAN Certificate
              _buildBusinessPanSection(),
              if (_panFileError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _panFileError!,
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              // Action buttons
              _buildBusinessActionButtons(),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return SizedBox(
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
    );
  }

  Widget _businessTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: hasError
                ? const Color(0xFFFFF1F0)
                : const Color(0xFFF4F3F3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasError ? const Color(0xFFF5222D) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: const TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFF5C5C5C),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Color(0xFFF5222D),
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCuisineDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F3F3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCuisine,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF1A1C1C),
            size: 22,
          ),
          hint: const Text(
            'Select primary cuisine',
            style: TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          items: _cuisineOptions.map((cuisine) {
            return DropdownMenuItem<String>(
              value: cuisine,
              child: Text(
                cuisine,
                style: const TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCuisine = value;
              _cuisineError = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildBusinessPanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PAN Number + file hint row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildFieldLabel('PAN Certificate'),
            const Text(
              'Max 5MB (JPG, PNG)',
              style: TextStyle(
                color: Color(0xFF949494),
                fontSize: 10,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                height: 1.40,
                letterSpacing: 0.20,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // PAN Number text field
        _businessTextField(
          controller: _panNumberCtrl,
          hint: 'e.g. 123456789',
          errorText: _panNumberError,
          onChanged: (_) {
            if (_panNumberError != null) {
              setState(() => _panNumberError = null);
            }
          },
        ),
        const SizedBox(height: 12),
        // Drag & drop upload area
        _buildPanUploadArea(),
      ],
    );
  }

  Widget _buildPanUploadArea() {
    final hasFile = _selectedPanFilePath != null;
    return GestureDetector(
      onTap: _isLoading ? null : _pickPanCertificate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: hasFile
              ? const Color(0xFFF6FFED)
              : const Color(0xFFF4F3F3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF52C41A).withValues(alpha: 0.5)
                : const Color(0xFFE3E2E2),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasFile)
              const Icon(
                Icons.check_circle,
                size: 48,
                color: Color(0xFF52C41A),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9E8E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  size: 24,
                  color: Color(0xFF5C5C5C),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              hasFile
                  ? _selectedPanFilePath!.split('/').last
                  : 'Click to upload or drag and drop',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload High Quality Image for Review',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF949494),
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
                height: 1.33,
              ),
            ),
            if (hasFile) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => _selectedPanFilePath = null),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFF5222D),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessActionButtons() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Go Back
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () => _goToStep(0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Color(0xFFE3E2E2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    height: 1.29,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Continue to Menu
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () => _goToStep(2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEB1727),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE0E0E0),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shadowColor: const Color(0x0C000000),
                ),
                child: const Text(
                  'Continue to Menu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    height: 1.29,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final hasError = errorText != null;
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
            onChanged: onChanged,
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
              fillColor: hasError
                  ? const Color(0xFFFFF1F0)
                  : const Color(0xFFF4F3F3),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: hasError
                    ? const BorderSide(color: Color(0xFFF5222D), width: 1.5)
                    : BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: hasError
                    ? const BorderSide(color: Color(0xFFF5222D), width: 1.5)
                    : BorderSide.none,
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
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Color(0xFFF5222D),
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }



  // ──────────────────────────────────────────────
  //  Step 2 — Menu (full design)
  // ──────────────────────────────────────────────

  Widget _buildRestaurantDetailsStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        // Header row: back button + logo
        Row(
          children: [
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
            _buildLogo(),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 8),
        // Title
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Restaurant Details',
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
            'Step 3 of 3: Let customers know what you serve.',
            style: TextStyle(
              color: Color(0xFF949494),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        _buildProgressIndicator(activeStep: 2),
        const SizedBox(height: 24),
        // Form card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: const Color(0xFFFAF9F9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFE9E8E8)),
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
              // Primary Food Category
              _buildFieldLabel('Primary Food Category'),
              const SizedBox(height: 4),
              _buildFoodCategoryDropdown(),
              if (_foodCategoryError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _foodCategoryError!,
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Standard Operating Hours
              _buildFieldLabel('Standard Operating Hours'),
              const SizedBox(height: 4),
              _buildStep3TimePickers(),
              const SizedBox(height: 16),
              // Upload Menu or Logo
              _buildStep3UploadSection(),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Submit button + terms
        _buildStep3SubmitSection(),
        // Error
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
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
          ),
        const SizedBox(height: 24),
      ],
    );
  }



  Widget _buildFoodCategoryDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F3F3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFoodCategory,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF1A1C1C),
            size: 22,
          ),
          hint: const Text(
            'Select category...',
            style: TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          items: _foodCategoryOptions.map((category) {
            return DropdownMenuItem<String>(
              value: category,
              child: Text(
                category,
                style: const TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedFoodCategory = value;
              _foodCategoryError = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildStep3TimePickers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Opening Time
        _buildTimeLabel('Opening Time'),
        const SizedBox(height: 4),
        _buildTimeSlotButton(
          time: _openTime,
          onTap: _pickOpenTime,
          placeholder: '09:00 AM',
        ),
        const SizedBox(height: 12),
        // Closing Time
        _buildTimeLabel('Closing Time'),
        const SizedBox(height: 4),
        _buildTimeSlotButton(
          time: _closeTime,
          onTap: _pickCloseTime,
          placeholder: '10:00 PM',
        ),
      ],
    );
  }

  Widget _buildTimeLabel(String label) {
    return SizedBox(
      width: 156,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF949494),
          fontSize: 10,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          height: 1.40,
          letterSpacing: 0.20,
        ),
      ),
    );
  }

  Widget _buildTimeSlotButton({
    required TimeOfDay? time,
    required VoidCallback onTap,
    required String placeholder,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F3F3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, size: 18, color: Color(0xFF5C5C5C)),
            const SizedBox(width: 12),
            Text(
              time != null ? _formatTime(time) : placeholder,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
                height: 1.43,
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

  Widget _buildStep3UploadSection() {
    final hasFile = _selectedCoverImagePath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildFieldLabel('Upload Menu or Logo'),
            const Text(
              'Max 5MB (JPG, PNG)',
              style: TextStyle(
                color: Color(0xFF949494),
                fontSize: 10,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                height: 1.40,
                letterSpacing: 0.20,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _isLoading ? null : _pickCoverImage,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: hasFile
                  ? const Color(0xFFF6FFED)
                  : const Color(0xFFF4F3F3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFile
                    ? const Color(0xFF52C41A).withValues(alpha: 0.5)
                    : const Color(0xFFE3E2E2),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasFile)
                  const Icon(
                    Icons.check_circle,
                    size: 48,
                    color: Color(0xFF52C41A),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE9E8E8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.image_outlined,
                      size: 24,
                      color: Color(0xFF5C5C5C),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  hasFile
                      ? _selectedCoverImagePath!.split('/').last
                      : 'Click to upload or drag and drop',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF1A1C1C),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'High quality images help attract more\ncustomers',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF949494),
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    height: 1.33,
                  ),
                ),
                if (hasFile) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedCoverImagePath = null),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFF5222D),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3SubmitSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Go Back button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: () => _goToStep(1),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Color(0xFFE3E2E2)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text(
              'Go Back to Business',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                height: 1.29,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () {
                    // Validate required fields for final step
                    setState(() {
                      _error = null;
                      _foodCategoryError = _selectedFoodCategory == null
                          ? 'Please select a primary food category.'
                          : null;
                    });
                    if (_foodCategoryError != null) return;
                    _submit();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEB1727),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE0E0E0),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              shadowColor: const Color(0x0C000000),
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
                : const Text(
                    'Submit Application',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      height: 1.33,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: double.infinity,
          child: Text(
            "By submitting, you agree to Dailo's Partner Terms of Service.",
            textAlign: TextAlign.center,
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
    );
  }
  Widget _buildLogo() {
    return Image.asset(
      'assets/img/logo.png',
      width: 160,
      height: 89,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Container(
        width: 160,
        height: 89,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F3F3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.restaurant,
          color: Color(0xFF5C5C5C),
          size: 32,
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
      child: Row(
        children: [
          const Spacer(),
          _stepDot(
            number: '1',
            label: 'Contact',
            isActive: activeStep >= 0,
          ),
          Container(
            width: 48,
            height: 2,
            decoration: BoxDecoration(
              color: activeStep >= 1
                  ? const Color(0xFFEB1727)
                  : const Color(0xFFE3E2E2),
            ),
          ),
          _stepDot(
            number: '2',
            label: 'Business',
            isActive: activeStep >= 1,
            bold: activeStep == 1,
          ),
          Container(
            width: 48,
            height: 2,
            decoration: BoxDecoration(
              color: activeStep >= 2
                  ? const Color(0xFFEB1727)
                  : const Color(0xFFE3E2E2),
            ),
          ),
          _stepDot(
            number: '3',
            label: 'Menu',
            isActive: activeStep >= 2,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _stepDot({
    required String number,
    required String label,
    required bool isActive,
    bool bold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFFAF9F9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFFEB1727)
                  : const Color(0xFFE3E2E2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive
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
            label,
            style: TextStyle(
              color: isActive
                  ? const Color(0xFFEB1727)
                  : const Color(0xFF5C5C5C),
              fontSize: 10,
              fontFamily: 'Inter',
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              height: 1.40,
              letterSpacing: 0.20,
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
              onPressed: _isLoading ? null : () => _goToStep(1),
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
                  : const Text(
                      'Continue to Business Information',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
        child: child ?? const SizedBox.shrink(),
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
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) {
      setState(() => _closeTime = picked);
    }
  }
}
