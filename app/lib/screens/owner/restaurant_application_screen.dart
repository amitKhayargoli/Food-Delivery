import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../widgets/step_progress_indicator.dart';
import '../../injection_container.dart' as di;

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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result == null) return;

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        setState(
          () => _error = 'File size exceeds 5MB limit. Please choose a smaller file.',
        );
        return;
      }

      setState(() {
        _selectedPanFilePath = filePath;
        _panFileError = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not access gallery. Please try again.');
    }
  }

  Future<void> _pickCoverImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result == null) return;

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        setState(
          () => _error = 'Cover image exceeds 5MB limit. Please choose a smaller file.',
        );
        return;
      }

      setState(() {
        _selectedCoverImagePath = filePath;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not access gallery. Please try again.');
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Read the token from secure storage first — this is the backend-issued
      // JWT (signed with JWT_SECRET).  The custom backend at 192.168.1.81:5000
      // verifies tokens with its own JWT_SECRET, so the Supabase access token
      // (signed by Supabase) would be rejected with 401.
      //
      // Token sources in order:
      // 1. FlutterSecureStorage 'jwt_token'  — set by AuthProvider.login() after
      //    OTP sign-in OR Google Sign-In (now exchanges the Google idToken for
      //    a backend-signed JWT via POST /api/auth/google).
      // 2. Supabase currentSession?.accessToken — fallback (Supabase JWT, may
      //    not be recognized by the custom backend).
      // 3. FlutterSecureStorage 'supabase_access_token' — last resort.
      const secureStorage = FlutterSecureStorage();

      String token = '';
      String userId = '';

      token = await secureStorage.read(key: 'jwt_token') ?? '';

      if (token.isEmpty) {
        // Fallback: try Supabase session accessToken directly
        final accessToken = SupabaseClientService
            .client.auth.currentSession?.accessToken;
        if (accessToken != null && accessToken.isNotEmpty) {
          token = accessToken;
          userId = SupabaseClientService
                  .client.auth.currentUser?.id ??
              '';
        }
        if (token.isEmpty) {
          // Last resort: try the other storage key
          token = await secureStorage.read(key: 'supabase_access_token') ?? '';
        }
      }

      if (token.isEmpty) {
        setState(() {
          _error = 'Please log in first.';
          _isLoading = false;
        });
        return;
      }

      // Try to get userId from Supabase auth if not set above
      if (userId.isEmpty) {
        userId = SupabaseClientService.client.auth.currentUser?.id ?? 'anon';
      }
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
    } on DioException catch (e) {
      // Handle token expiration / auth errors with a friendly message
      if (e.response?.statusCode == 401) {
        setState(() {
          _error = 'Your session has expired. Please log in again and retry.';
        });
      } else {
        final message = _extractDioError(e);
        setState(() => _error = message);
      }
    } on ApiException catch (e) {
      // The ApiService wraps DioExceptions into ApiException,
      // so check the message for auth-related keywords too.
      final isAuthError = [
        'auth', '401', 'unauthorized', 'token', 'expired',
      ].any((kw) => e.message.toLowerCase().contains(kw));

      setState(() {
        _error = isAuthError
            ? 'Your session has expired. Please log in again and retry.'
            : e.message;
      });
    } catch (e) {
      setState(() => _error = 'An unexpected error occurred. Please try again.');
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
      backgroundColor: Colors.white,
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
                  color: Color(0xFF1A1A1A),
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
              color: Color(0xFF1A1A1A),
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
              color: Color(0xFF595959),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        const StepProgressIndicator(
          currentStep: 0,
          steps: [
            StepInfo(number: '1', label: 'Contact'),
            StepInfo(number: '2', label: 'Business'),
            StepInfo(number: '3', label: 'Menu'),
          ],
        ),
        const SizedBox(height: 24),
        // Form card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
              borderRadius: BorderRadius.circular(8),
            ),
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
                    color: Color(0xFF262626),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.50,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      width: 1,
                      color: _phoneError != null
                          ? Color(0xFFF5222D)
                          : Color(0xFFE8E8E8),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  color: _phoneError != null
                      ? Color(0xFFFFF1F0)
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
                      color: Color(0xFFE8E8E8),
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
                  fontSize: 13,
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
                  color: Color(0xFF1A1A1A),
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
              color: Color(0xFF1A1A1A),
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
              color: Color(0xFF595959),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        const StepProgressIndicator(
          currentStep: 1,
          steps: [
            StepInfo(number: '1', label: 'Contact'),
            StepInfo(number: '2', label: 'Business'),
            StepInfo(number: '3', label: 'Menu'),
          ],
        ),
        const SizedBox(height: 24),
        // Form card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Restaurant Name
              _buildFieldLabel('Restaurant Name'),
              const SizedBox(height: 4),
              _buildBusinessTextField(
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
              _buildBusinessTextField(
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
                      fontSize: 13,
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
                  fontSize: 13,
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
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF262626),
        fontSize: 16,
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        height: 1.50,
      ),
    );
  }

  Widget _buildCuisineDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey('cuisine_dropdown'),
          value: _selectedCuisine,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF1A1A1A),
            size: 22,
          ),
          hint: const Text(
            'Select primary cuisine',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
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
                  color: Color(0xFF1A1A1A),
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
                color: Color(0xFF8C8C8C),
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
        _buildBusinessTextField(
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
              ? Color(0xFFF6FFED)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile
                ? Color(0xFF52C41A).withValues(alpha: 0.5)
                : Color(0xFFE8E8E8),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasFile)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_selectedPanFilePath!),
                  width: 120,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Color(0xFFBFBFBF),
                  ),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8E8E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  size: 24,
                  color: Color(0xFFBFBFBF),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              hasFile
                  ? _selectedPanFilePath!.split('/').last
                  : 'Click to upload or drag and drop',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
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
                color: Color(0xFF8C8C8C),
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
                  foregroundColor: Color(0xFFF5222D),
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
              height: 56,
              child: OutlinedButton(
                onPressed: () => _goToStep(0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Color(0xFFD9D9D9)),
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
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () => _goToStep(2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFF5222D),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Color(0xFFE0E0E0),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shadowColor: const Color(0x0C000000),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.50,
                  ),
                ),
                child: const Text(
                  'Continue to Menu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.50,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF262626),
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              height: 1.50,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _buildBusinessTextField(
          controller: controller,
          hint: hint,
          keyboardType: keyboardType,
          errorText: errorText,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildBusinessTextField({
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
        SizedBox(
          height: 48,
          width: double.infinity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: hasError
                  ? Color(0xFFFFF1F0)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasError
                    ? Color(0xFFF5222D)
                    : Color(0xFFE8E8E8),
                width: hasError ? 1.5 : 1,
              ),
            ),
            child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
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
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText,
              style: const TextStyle(
                color: Color(0xFFF5222D),
                fontSize: 13,
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
                  color: Color(0xFF1A1A1A),
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
              color: Color(0xFF1A1A1A),
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
              color: Color(0xFF8C8C8C),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        const StepProgressIndicator(
          currentStep: 2,
          steps: [
            StepInfo(number: '1', label: 'Contact'),
            StepInfo(number: '2', label: 'Business'),
            StepInfo(number: '3', label: 'Menu'),
          ],
        ),
        const SizedBox(height: 24),
        // Form card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
              borderRadius: BorderRadius.circular(8),
            ),
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
                    fontSize: 13,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                ),
              const SizedBox(height: 16),
              // Operating Hours (inline header in _buildStep3TimePickers)
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
                color: Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Color(0xFFF5222D).withValues(alpha: 0.3),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFoodCategory,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF1A1A1A),
            size: 22,
          ),
          hint: const Text(
            'Select category...',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
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
                  color: Color(0xFF1A1A1A),
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

  int _timeToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool get _isCloseBeforeOpen =>
      _openTime != null && _closeTime != null && _timeToMinutes(_closeTime!) <= _timeToMinutes(_openTime!);

  Widget _buildStep3TimePickers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Opening Hours',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF262626),
                fontFamily: 'Inter',
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
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Open / Close time slots side by side
        Row(
          children: [
            Expanded(
              child: _buildTimeSlot(
                label: 'Open',
                icon: Icons.wb_sunny_outlined,
                time: _openTime,
                onTap: _isLoading ? null : _pickOpenTime,
                defaultText: 'Select',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
                onTap: _isLoading ? null : _pickCloseTime,
                defaultText: 'Select',
              ),
            ),
          ],
        ),
        if (_openTime != null && _closeTime != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  _isCloseBeforeOpen ? Icons.warning_amber_rounded : Icons.schedule,
                  size: 14,
                  color: _isCloseBeforeOpen ? const Color(0xFFF57C00) : const Color(0xFF8C8C8C),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_formatTime(_openTime!)} - ${_formatTime(_closeTime!)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: _isCloseBeforeOpen ? const Color(0xFFF57C00) : const Color(0xFF52C41A),
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        if (_isCloseBeforeOpen)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFF57C00)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Closes after midnight? Make sure this is correct.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF795548),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeSlot({
    required String label,
    required IconData icon,
    required TimeOfDay? time,
    required VoidCallback? onTap,
    required String defaultText,
  }) {
    final isSelected = time != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isSelected ? _formatTime(time) : defaultText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF1A1A1A) : const Color(0xFFBFBFBF),
                fontFamily: 'Inter',
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
                color: Color(0xFF8C8C8C),
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
                  ? Color(0xFFF6FFED)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFile
                    ? Color(0xFF52C41A).withValues(alpha: 0.5)
                    : Color(0xFFE8E8E8),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasFile)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_selectedCoverImagePath!),
                      width: 200,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image,
                        size: 48,
                        color: Color(0xFFBFBFBF),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8E8E8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.image_outlined,
                      size: 24,
                      color: Color(0xFFBFBFBF),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  hasFile
                      ? _selectedCoverImagePath!.split('/').last
                      : 'Click to upload or drag and drop',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
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
                    color: Color(0xFF8C8C8C),
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
                      foregroundColor: Color(0xFFF5222D),
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
          height: 56,
          child: OutlinedButton(
            onPressed: () => _goToStep(1),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Color(0xFFD9D9D9)),
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
          height: 56,
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
              backgroundColor: Color(0xFFF5222D),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Color(0xFFE0E0E0),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              shadowColor: const Color(0x0C000000),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.50,
              ),
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
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      height: 1.50,
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
              color: Color(0xFF8C8C8C),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.restaurant,
          color: Color(0xFFBFBFBF),
          size: 32,
        ),
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
        color: Colors.white,
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
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _goToStep(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFF5222D),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Color(0xFFE0E0E0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.50,
                ),
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
                        height: 1.50,
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
                    color: Color(0xFF595959),
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
                      color: Color(0xFFF5222D),
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
                color: Color(0xFF1A1A1A),
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _successMessage ?? 'Your application is pending admin review.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF595959),
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFFFE082)),
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
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFF5222D),
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

  /// Extract a user-friendly message from a DioException.
  String _extractDioError(DioException e) {
    if (e.response?.data is Map<String, dynamic>) {
      final data = e.response!.data as Map<String, dynamic>;
      if (data.containsKey('error')) {
        return data['error'] as String;
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Please check your network and try again.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Could not connect to the server. Please check your internet connection.';
    }
    return 'Something went wrong. Please try again.';
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
