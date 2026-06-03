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
  ConsumerState<RestaurantApplicationScreen> createState() => _RestaurantApplicationScreenState();
}

class _RestaurantApplicationScreenState extends ConsumerState<RestaurantApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _restaurantNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _panNumberCtrl = TextEditingController();
  String? _selectedPanFilePath;
  bool _isPanUploading = false;
  String? _selectedCoverImagePath;
  bool _isCoverImageUploading = false;
  final _descriptionCtrl = TextEditingController();
  final _cuisineTypeCtrl = TextEditingController();

  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  bool _isLoading = false;
  bool _submitted = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _restaurantNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _panNumberCtrl.dispose();

    _descriptionCtrl.dispose();
    _cuisineTypeCtrl.dispose();
    super.dispose();
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
      // Validate file size (max 5MB)
      final file = File(pickedFile.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        setState(() => _error = 'File size exceeds 5MB limit. Please choose a smaller file.');
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
      // Validate file size (max 5MB)
      final file = File(pickedFile.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        setState(() => _error = 'Cover image exceeds 5MB limit. Please choose a smaller file.');
        return;
      }

      setState(() {
        _selectedCoverImagePath = pickedFile.path;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPanFilePath == null) {
      setState(() => _error = 'Please upload your PAN certificate.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authVm = ref.read(authViewModelProvider);
      final token = authVm.currentUser?.token ?? '';

      if (token.isEmpty) {
        setState(() => _error = 'Please log in first.');
        setState(() => _isLoading = false);
        return;
      }

      final userId = authVm.currentUser?.id ?? 'anon';

      final storage = di.sl<StorageService>();

      // Step 1: Upload PAN certificate to Supabase Storage
      setState(() => _isPanUploading = true);

      final panCertificateUrl = await storage.uploadPanCertificate(
        filePath: _selectedPanFilePath!,
        userId: userId,
        token: token,
      );

      setState(() => _isPanUploading = false);

      // Step 2: Upload cover image (if selected)
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

      // Step 3: Submit the application with the uploaded URLs
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
        openTime: _openTime != null ? _toTimeString(_openTime!) : null,
        closeTime: _closeTime != null ? _toTimeString(_closeTime!) : null,
        cuisineType:
            _cuisineTypeCtrl.text.trim().isEmpty ? null : _cuisineTypeCtrl.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1C1C)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Restaurant Registration',
          style: TextStyle(
            color: Color(0xFF1A1C1C),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
      ),
      body: _submitted ? _buildSuccessView() : _buildForm(),
    );
  }

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

  Widget _buildForm() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mandatory Section Header
              _buildSectionHeader('Mandatory Fields', isRequired: true),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _restaurantNameCtrl,
                label: 'Restaurant Name',
                hint: 'e.g. Dailo Kitchen',
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _ownerNameCtrl,
                label: 'Owner Name',
                hint: 'Your full name',
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _phoneCtrl,
                label: 'Phone Number',
                hint: 'e.g. 98XXXXXXXX',
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v?.trim().isEmpty == true) return 'Required';
                  if (v!.length < 10) return 'Enter a valid phone number';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _emailCtrl,
                label: 'Email Address',
                hint: 'your@email.com',
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v?.trim().isEmpty == true) return 'Required';
                  if (!v!.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _addressCtrl,
                label: 'Address',
                hint: 'Full restaurant address',
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _panNumberCtrl,
                label: 'PAN Number',
                hint: 'e.g. 123456789',
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // PAN Certificate Upload
              _buildPanUploadSection(),
              const SizedBox(height: 24),

              // Optional Section Header
              _buildSectionHeader('Optional Fields', isRequired: false),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _descriptionCtrl,
                label: 'Restaurant Description',
                hint: 'Tell customers about your restaurant',
                maxLines: 3,
              ),
              const SizedBox(height: 12),

              _buildCoverImageUploadSection(),
              const SizedBox(height: 12),

              _buildTimeRangePicker(),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _cuisineTypeCtrl,
                label: 'Cuisine Type',
                hint: 'e.g. Nepali, Indian, Chinese',
              ),
              const SizedBox(height: 32),

              // Error
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF5222D).withValues(alpha: 0.3)),
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

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5222D),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE0E0E0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
                      : Text(
                          _isPanUploading
                              ? 'Uploading PAN Certificate...'
                              : _isCoverImageUploading
                                  ? 'Uploading Cover Image...'
                                  : 'Submit Application',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Color(0xFF757575)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your PAN certificate will be reviewed by the admin. '
                        'You will be notified once approved.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF757575),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String text, {required bool isRequired}) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1C1C),
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isRequired
                ? const Color(0xFFFFF1F0)
                : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isRequired ? 'Required' : 'Optional',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isRequired ? const Color(0xFFF5222D) : const Color(0xFF757575),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PAN Certificate',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF262626),
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        // Upload area
        GestureDetector(
          onTap: _isLoading ? null : _pickPanCertificate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: _selectedPanFilePath != null
                  ? const Color(0xFFF6FFED)
                  : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _selectedPanFilePath != null
                    ? const Color(0xFF52C41A)
                    : const Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
            child: _selectedPanFilePath != null
                ? Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(_selectedPanFilePath!),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.description,
                              color: Color(0xFF8C8C8C),
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PAN Certificate Selected',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1C1C),
                                fontFamily: 'Inter',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectedPanFilePath!.split('/').last,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8C8C8C),
                                fontFamily: 'Inter',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _selectedPanFilePath = null);
                        },
                        icon: const Icon(Icons.close, size: 18, color: Color(0xFF8C8C8C)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.cloud_upload_outlined,
                          color: Color(0xFFF5222D),
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap to upload PAN certificate',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF262626),
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Supports JPG, PNG • Max 5MB',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFBFBFBF),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverImageUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cover Image',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF262626),
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _isLoading ? null : _pickCoverImage,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: _selectedCoverImagePath != null
                  ? const Color(0xFFFFF8E1)
                  : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _selectedCoverImagePath != null
                    ? const Color(0xFFFFC53D)
                    : const Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
            child: _selectedCoverImagePath != null
                ? Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(_selectedCoverImagePath!),
                          width: 64,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 64,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.image,
                              color: Color(0xFF8C8C8C),
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cover Image Selected',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1C1C),
                                fontFamily: 'Inter',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectedCoverImagePath!.split('/').last,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8C8C8C),
                                fontFamily: 'Inter',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _selectedCoverImagePath = null);
                        },
                        icon: const Icon(Icons.close, size: 18, color: Color(0xFF8C8C8C)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.image_outlined,
                          color: Color(0xFFF5222D),
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap to upload cover image',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF262626),
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Optional • Recommended 1200×400 • JPG, PNG',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFBFBFBF),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  int _timeToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool get _isCloseBeforeOpen =>
      _openTime != null && _closeTime != null && _timeToMinutes(_closeTime!) <= _timeToMinutes(_openTime!);

  /// Format TimeOfDay for display (e.g., "9:00 AM")
  String _formatTime(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute.toString().padLeft(2, '0');
    return '$hour12:$minuteStr $period';
  }

  /// Format TimeOfDay for the API (24-hour, e.g., "09:00")
  String _toTimeString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickOpenTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _openTime ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Select opening time',
      cancelText: 'Cancel',
      confirmText: 'Confirm',
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
      helpText: 'Select closing time',
      cancelText: 'Cancel',
      confirmText: 'Confirm',
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

  Widget _buildTimeRangePicker() {
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
        // Open Time
        Row(
          children: [
            // Open time selector
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
            // Close time selector
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
              isSelected ? _formatTime(time!) : defaultText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF1A1C1C) : const Color(0xFFBFBFBF),
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF262626),
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: const TextStyle(fontSize: 14, fontFamily: 'Inter'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: const Color(0xFFBFBFBF),
              fontSize: 14,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFF5222D), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFF5222D)),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
