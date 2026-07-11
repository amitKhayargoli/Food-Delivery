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

class DeliveryApplicationScreen extends ConsumerStatefulWidget {
  const DeliveryApplicationScreen({super.key});

  @override
  ConsumerState<DeliveryApplicationScreen> createState() =>
      _DeliveryApplicationScreenState();
}

class _DeliveryApplicationScreenState
    extends ConsumerState<DeliveryApplicationScreen> {
  int _currentStep = 0;

  // Personal Info Step
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Vehicle & Documents Step
  String? _selectedVehicleType;
  final _vehicleNumberCtrl = TextEditingController();
  String? _selectedLicenseFilePath;
  String? _selectedProfileImagePath;

  // Terms
  bool _agreedToTerms = false;

  // Per-field error states
  String? _fullNameError;
  String? _emailError;
  String? _phoneError;
  String? _vehicleTypeError;
  String? _vehicleNumberError;
  String? _licenseFileError;

  bool _isLoading = false;
  bool _submitted = false;
  String? _error;
  String? _successMessage;

  static const List<String> _vehicleTypeOptions = [
    'Bicycle',
    'Motorcycle / Scooter',
    'Car',
    'Scooter (Electric)',
    'On Foot',
  ];

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleNumberCtrl.dispose();
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
            _fullNameError = _fullNameCtrl.text.trim().isEmpty
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
          valid = _fullNameError == null &&
              _emailError == null &&
              _phoneError == null;
          if (!valid) return;
          break;

        case 1:
          setState(() {
            _vehicleTypeError = _selectedVehicleType == null
                ? 'Please select your vehicle type.'
                : null;
            _vehicleNumberError = _vehicleNumberCtrl.text.trim().isEmpty
                ? 'Please enter your vehicle number.'
                : null;
            _licenseFileError = _selectedLicenseFilePath == null
                ? 'Please upload your drivers license.'
                : null;
          });
          valid = _vehicleTypeError == null &&
              _vehicleNumberError == null &&
              _licenseFileError == null;
          if (!valid) return;
          break;
      }
    }

    setState(() {
      _currentStep = step;
      _error = null;
    });
  }

  Future<void> _pickLicenseImage() async {
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
        _selectedLicenseFilePath = filePath;
        _licenseFileError = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not access gallery. Please try again.');
    }
  }

  Future<void> _pickProfileImage() async {
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
          () => _error = 'Profile image exceeds 5MB limit. Please choose a smaller file.',
        );
        return;
      }

      setState(() {
        _selectedProfileImagePath = filePath;
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
      const secureStorage = FlutterSecureStorage();

      String token = '';
      String userId = '';

      token = await secureStorage.read(key: 'jwt_token') ?? '';

      if (token.isEmpty) {
        final accessToken = SupabaseClientService
            .client.auth.currentSession?.accessToken;
        if (accessToken != null && accessToken.isNotEmpty) {
          token = accessToken;
          userId = SupabaseClientService
                  .client.auth.currentUser?.id ?? '';
        }
        if (token.isEmpty) {
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

      if (userId.isEmpty) {
        userId = SupabaseClientService.client.auth.currentUser?.id ?? 'anon';
      }

      final storage = di.sl<StorageService>();

      // Upload driver's license
      final licenseUrl = await storage.uploadRiderDocument(
        filePath: _selectedLicenseFilePath!,
        token: token,
      );

      // Upload profile image (optional)
      String? profileImageUrl;
      if (_selectedProfileImagePath != null) {
        profileImageUrl = await storage.uploadProfilePicture(
          filePath: _selectedProfileImagePath!,
          token: token,
        );
      }

      // Submit the application
      final api = di.sl<ApiService>();
      final response = await api.submitRiderApplication(
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: '+977${_phoneCtrl.text.trim()}',
        vehicleType: _selectedVehicleType!,
        vehicleNumber: _vehicleNumberCtrl.text.trim().toUpperCase(),
        licenseUrl: licenseUrl,
        profileImageUrl: profileImageUrl,
        token: token,
      );

      setState(() {
        _submitted = true;
        _successMessage = response.message;
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        setState(() {
          _error = 'Your session has expired. Please log in again and retry.';
        });
      } else {
        final message = _extractDioError(e);
        setState(() => _error = message);
      }
    } on ApiException catch (e) {
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
          if (_currentStep == 0) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildPersonalInfoStep();
      case 1:
        return _buildVehicleDocumentsStep();
      case 2:
        return _buildReviewSubmitStep();
      default:
        return _buildPersonalInfoStep();
    }
  }

  // ──────────────────────────────────────────────
  //  Step 0 — Personal Info
  // ──────────────────────────────────────────────

  Widget _buildPersonalInfoStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
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
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Become a Delivery Partner',
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
            'Start with your personal details.\nThis helps us verify your identity and set up your account.',
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
        const StepProgressIndicator(
          currentStep: 0,
          steps: [
            StepInfo(number: '1', label: 'Personal'),
            StepInfo(number: '2', label: 'Vehicle'),
            StepInfo(number: '3', label: 'Submit'),
          ],
        ),
        const SizedBox(height: 24),
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
              _buildFieldLabel("Full Name"),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _fullNameCtrl,
                hint: 'e.g. Ram Sharma',
                errorText: _fullNameError,
                onChanged: (_) {
                  if (_fullNameError != null) {
                    setState(() => _fullNameError = null);
                  }
                },
              ),
              const SizedBox(height: 24),
              _buildFieldLabel('Email Address'),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _emailCtrl,
                hint: 'ram@example.com',
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                onChanged: (_) {
                  if (_emailError != null) {
                    setState(() => _emailError = null);
                  }
                },
              ),
              const SizedBox(height: 24),
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
        const SizedBox(height: 24),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Step 1 — Vehicle & Documents
  // ──────────────────────────────────────────────

  Widget _buildVehicleDocumentsStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            GestureDetector(
              onTap: () => _goToStep(0),
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
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Vehicle & Documents',
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
            'Tell us about your vehicle and upload required documents.',
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
        const StepProgressIndicator(
          currentStep: 1,
          steps: [
            StepInfo(number: '1', label: 'Personal'),
            StepInfo(number: '2', label: 'Vehicle'),
            StepInfo(number: '3', label: 'Submit'),
          ],
        ),
        const SizedBox(height: 24),
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
              // Vehicle Type
              _buildFieldLabel('Vehicle Type'),
              const SizedBox(height: 4),
              _buildVehicleTypeDropdown(),
              if (_vehicleTypeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _vehicleTypeError!,
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 13,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Vehicle Number
              _buildFieldLabel('Vehicle Number'),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _vehicleNumberCtrl,
                hint: 'e.g. BA 1 PA 1234',
                textCapitalization: TextCapitalization.characters,
                errorText: _vehicleNumberError,
                onChanged: (_) {
                  if (_vehicleNumberError != null) {
                    setState(() => _vehicleNumberError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              // Driver's License Upload
              _buildFieldLabel("Driver's License"),
              const SizedBox(height: 4),
              _buildLicenseUploadArea(),
              if (_licenseFileError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _licenseFileError!,
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 13,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Profile Photo Upload (optional)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildFieldLabel('Profile Photo'),
                  const Text(
                    'Optional',
                    style: TextStyle(
                      color: Color(0xFF8C8C8C),
                      fontSize: 11,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _buildProfileUploadArea(),
              const SizedBox(height: 24),
              // Action buttons
              _buildVehicleActionButtons(),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildVehicleTypeDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey('vehicle_type_dropdown'),
          value: _selectedVehicleType,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF1A1A1A),
            size: 22,
          ),
          hint: const Text(
            'Select vehicle type',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          items: _vehicleTypeOptions.map((type) {
            return DropdownMenuItem<String>(
              value: type,
              child: Row(
                children: [
                  Icon(
                    _vehicleIconFor(type),
                    size: 20,
                    color: const Color(0xFF595959),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    type,
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedVehicleType = value;
              _vehicleTypeError = null;
            });
          },
        ),
      ),
    );
  }

  IconData _vehicleIconFor(String type) {
    switch (type) {
      case 'Bicycle':
        return Icons.directions_bike;
      case 'Motorcycle / Scooter':
        return Icons.motorcycle;
      case 'Car':
        return Icons.directions_car;
      case 'Scooter (Electric)':
        return Icons.electric_scooter;
      case 'On Foot':
        return Icons.directions_walk;
      default:
        return Icons.directions_bike;
    }
  }

  Widget _buildLicenseUploadArea() {
    final hasFile = _selectedLicenseFilePath != null;
    return GestureDetector(
      onTap: _isLoading ? null : _pickLicenseImage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: hasFile ? const Color(0xFFF6FFED) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF52C41A).withValues(alpha: 0.5)
                : const Color(0xFFE8E8E8),
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
                  File(_selectedLicenseFilePath!),
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
                  Icons.perm_identity_outlined,
                  size: 24,
                  color: Color(0xFFBFBFBF),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              hasFile
                  ? _selectedLicenseFilePath!.split('/').last
                  : 'Click to upload',
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
              'Upload a clear photo of your drivers license\nJPG, PNG \u2022 Max 5MB',
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
                onPressed: () => setState(() => _selectedLicenseFilePath = null),
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

  Widget _buildProfileUploadArea() {
    final hasFile = _selectedProfileImagePath != null;
    return GestureDetector(
      onTap: _isLoading ? null : _pickProfileImage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: hasFile ? const Color(0xFFF6FFED) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF52C41A).withValues(alpha: 0.5)
                : const Color(0xFFE8E8E8),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasFile)
              CircleAvatar(
                radius: 40,
                backgroundImage: FileImage(File(_selectedProfileImagePath!)),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
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
                  Icons.camera_alt_outlined,
                  size: 24,
                  color: Color(0xFFBFBFBF),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              hasFile ? 'Tap to change' : 'Tap to upload a profile photo',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            if (hasFile) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() => _selectedProfileImagePath = null),
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

  Widget _buildVehicleActionButtons() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () => _goToStep(2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5222D),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE0E0E0),
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
                  'Review & Submit',
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

  // ──────────────────────────────────────────────
  //  Step 2 — Review & Submit
  // ──────────────────────────────────────────────

  Widget _buildReviewSubmitStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            GestureDetector(
              onTap: () => _goToStep(1),
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
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Review & Submit',
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
            'Step 3 of 3: Please review your information before submitting.',
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
        const StepProgressIndicator(
          currentStep: 2,
          steps: [
            StepInfo(number: '1', label: 'Personal'),
            StepInfo(number: '2', label: 'Vehicle'),
            StepInfo(number: '3', label: 'Submit'),
          ],
        ),
        const SizedBox(height: 24),
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
              // Summary card
              _buildReviewRow(Icons.person_outline, 'Full Name', _fullNameCtrl.text.trim()),
              const Divider(height: 20),
              _buildReviewRow(Icons.email_outlined, 'Email', _emailCtrl.text.trim()),
              const Divider(height: 20),
              _buildReviewRow(Icons.phone_outlined, 'Phone', '+977 ${_phoneCtrl.text.trim()}'),
              const Divider(height: 20),
              _buildReviewRow(
                _vehicleIconFor(_selectedVehicleType ?? ''),
                'Vehicle Type',
                _selectedVehicleType ?? '',
              ),
              const Divider(height: 20),
              _buildReviewRow(Icons.directions_car_outlined, 'Vehicle Number', _vehicleNumberCtrl.text.trim().toUpperCase()),
              const Divider(height: 20),
              _buildReviewRow(Icons.badge_outlined, "Driver's License", 'Uploaded ✓'),
              if (_selectedProfileImagePath != null) ...[
                const Divider(height: 20),
                _buildReviewRow(Icons.photo_camera_outlined, 'Profile Photo', 'Uploaded ✓'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Terms checkbox
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _agreedToTerms,
                  onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                  activeColor: const Color(0xFFF5222D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "I agree to Dailo's Delivery Partner Terms of Service and confirm that all information provided is accurate.",
                  style: TextStyle(
                    color: Color(0xFF595959),
                    fontSize: 13,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    height: 1.40,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Error message
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
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
        // Action buttons
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
              'Go Back to Vehicle',
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
            onPressed: _isLoading || !_agreedToTerms
                ? null
                : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5222D),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE0E0E0),
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
            "By submitting, you agree to Dailo's Delivery Partner Terms of Service.",
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
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildReviewRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF595959)),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8C8C8C),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
                      "Your driver's license will be reviewed by the admin. "
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
  //  Shared Widgets
  // ──────────────────────────────────────────────

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
          Icons.moped,
          color: Color(0xFFBFBFBF),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return SizedBox(
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
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
              color: hasError ? const Color(0xFFFFF1F0) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasError ? const Color(0xFFF5222D) : const Color(0xFFE8E8E8),
                width: hasError ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
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
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _goToStep(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5222D),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
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
                      'Continue to Vehicle & Documents',
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
  //  Helpers
  // ──────────────────────────────────────────────

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
}
