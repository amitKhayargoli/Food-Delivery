import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

class ManageRestaurantScreen extends StatefulWidget {
  const ManageRestaurantScreen({super.key});

  @override
  State<ManageRestaurantScreen> createState() => _ManageRestaurantScreenState();
}

class _ManageRestaurantScreenState extends State<ManageRestaurantScreen> {
  // Controllers for editable fields
  final _restaurantNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  // Dropdown / selection state
  String? _selectedCuisine;
  String? _openTime;
  String? _closeTime;
  String? _logoUrl;
  String? _coverImageUrl;

  // Loading / error states
  bool _isLoadingInitial = true;
  bool _isSaving = false;
  String? _error;
  String? _initialDataHash; // Used for unsaved changes detection

  // Original snapshot of the application data for comparison
  Map<String, dynamic>? _originalApplication;

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

  @override
  void initState() {
    super.initState();
    _fetchApplication();
  }

  @override
  void dispose() {
    _restaurantNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────

  String? get _token => context.read<AuthProvider>().token;

  /// Compute a simple hash of the current form state to detect unsaved changes.
  String _computeFormHash() {
    return '${_restaurantNameCtrl.text}|${_ownerNameCtrl.text}|${_phoneCtrl.text}|'
        '${_emailCtrl.text}|${_addressCtrl.text}|${_descriptionCtrl.text}|'
        '$_selectedCuisine|$_openTime|$_closeTime|$_logoUrl|$_coverImageUrl';
  }

  bool get _hasUnsavedChanges => _computeFormHash() != _initialDataHash;

  // ── Data fetching ────────────────────────────

  Future<void> _fetchApplication() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _isLoadingInitial = false;
        _error = 'Not authenticated. Please log in.';
      });
      return;
    }

    setState(() {
      _isLoadingInitial = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final app = await api.getMyApplication(token: token);

      if (app == null) {
        setState(() {
          _error = 'No restaurant application found. Please submit an application first.';
          _isLoadingInitial = false;
        });
        return;
      }

      setState(() {
        // Populate fields
        _restaurantNameCtrl.text = (app['restaurant_name'] as String?) ?? '';
        _ownerNameCtrl.text = (app['owner_name'] as String?) ?? '';
        _phoneCtrl.text = (app['phone'] as String?) ?? '';
        _emailCtrl.text = (app['email'] as String?) ?? '';
        _addressCtrl.text = (app['address'] as String?) ?? '';
        _descriptionCtrl.text = (app['description'] as String?) ?? '';
        _selectedCuisine = app['cuisine_type'] as String?;
        _openTime = app['open_time'] as String?;
        _closeTime = app['close_time'] as String?;
        _logoUrl = app['logo_url'] as String?;
        _coverImageUrl = app['cover_image_url'] as String?;

        _originalApplication = app;
        _initialDataHash = _computeFormHash();
        _isLoadingInitial = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoadingInitial = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load restaurant data. Please try again.';
        _isLoadingInitial = false;
      });
    }
  }

  // ── Save ─────────────────────────────────────

  Future<void> _save() async {
    final token = _token;
    if (token == null) return;

    // Validate
    if (_restaurantNameCtrl.text.trim().isEmpty) {
      _showSnackBar('Restaurant name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final data = <String, dynamic>{};

      // Only include changed fields
      if (_restaurantNameCtrl.text != (_originalApplication?['restaurant_name'] as String? ?? '')) {
        data['restaurant_name'] = _restaurantNameCtrl.text.trim();
      }
      if (_ownerNameCtrl.text != (_originalApplication?['owner_name'] as String? ?? '')) {
        data['owner_name'] = _ownerNameCtrl.text.trim();
      }
      if (_phoneCtrl.text != (_originalApplication?['phone'] as String? ?? '')) {
        data['phone'] = _phoneCtrl.text.trim();
      }
      if (_emailCtrl.text != (_originalApplication?['email'] as String? ?? '')) {
        data['email'] = _emailCtrl.text.trim();
      }
      if (_addressCtrl.text != (_originalApplication?['address'] as String? ?? '')) {
        data['address'] = _addressCtrl.text.trim();
      }
      if (_descriptionCtrl.text != (_originalApplication?['description'] as String? ?? '')) {
        data['description'] = _descriptionCtrl.text.trim();
      }
      if (_selectedCuisine != (_originalApplication?['cuisine_type'] as String?)) {
        data['cuisine_type'] = _selectedCuisine;
      }
      if (_openTime != (_originalApplication?['open_time'] as String?)) {
        data['open_time'] = _openTime;
      }
      if (_closeTime != (_originalApplication?['close_time'] as String?)) {
        data['close_time'] = _closeTime;
      }
      if (_logoUrl != (_originalApplication?['logo_url'] as String?)) {
        data['logo_url'] = _logoUrl;
      }
      if (_coverImageUrl != (_originalApplication?['cover_image_url'] as String?)) {
        data['cover_image_url'] = _coverImageUrl;
      }

      if (data.isEmpty) {
        _showSnackBar('No changes to save.');
        setState(() => _isSaving = false);
        return;
      }

      await api.updateRestaurant(data: data, token: token);

      // Update the original snapshot to match saved state
      setState(() {
        _originalApplication = Map<String, dynamic>.from(_originalApplication ?? {})..addAll(data);
        _initialDataHash = _computeFormHash();
        _isSaving = false;
      });

      if (mounted) {
        _showSnackBar('Restaurant profile updated successfully!');
      }
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isSaving = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to save. Please try again.';
        _isSaving = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1E8E3E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Time picker helpers ──────────────────────

  Future<void> _pickTime(bool isOpen) async {
    final existing = isOpen ? _openTime : _closeTime;
    final parsed = existing != null ? _parseTimeString(existing) : null;
    final picked = await showTimePicker(
      context: context,
      initialTime: parsed ?? (isOpen ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 21, minute: 0)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFBB0018)),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) {
      setState(() {
        final hour = picked.hour.toString().padLeft(2, '0');
        final minute = picked.minute.toString().padLeft(2, '0');
        if (isOpen) {
          _openTime = '$hour:$minute';
        } else {
          _closeTime = '$hour:$minute';
        }
      });
    }
  }

  TimeOfDay _parseTimeString(String time) {
    final parts = time.split(':');
    final hour = int.tryParse(parts[0]) ?? 9;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeDisplay(String? time) {
    if (time == null) return 'Not set';
    final parsed = _parseTimeString(time);
    final hour = parsed.hour;
    final minute = parsed.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  // ── WillPopScope — unsaved changes warning ───

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Are you sure you want to leave?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFBB0018)),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF9F9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1C1C)),
            onPressed: () {
              if (_hasUnsavedChanges) {
                _onWillPop().then((shouldPop) {
                  if (shouldPop && mounted) Navigator.of(context).pop();
                });
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: const Text(
            'Manage Restaurant',
            style: TextStyle(
              color: Color(0xFF1A1C1C),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _save,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFBB0018),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFBB0018),
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingInitial) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text(
              'Loading restaurant data...',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null && _originalApplication == null) {
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
                onPressed: _fetchApplication,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          // Error banner (non-blocking — form is still editable)
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x4DF5222D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFF5222D), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFF5222D), fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          // ── Basic Info Section ──
          _buildSectionHeader('Basic Information'),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Restaurant Name',
            controller: _restaurantNameCtrl,
            required: true,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Owner Name',
            controller: _ownerNameCtrl,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Phone',
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Email',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Address',
            controller: _addressCtrl,
          ),

          const SizedBox(height: 32),

          // ── Cuisine Section ──
          _buildSectionHeader('Cuisine'),
          const SizedBox(height: 12),
          _buildCuisineDropdown(),

          const SizedBox(height: 32),

          // ── Operating Hours Section ──
          _buildSectionHeader('Operating Hours'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildTimeSlot('Open', _openTime, () => _pickTime(true))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, color: Color(0xFFBFBFBF), size: 18),
              ),
              Expanded(child: _buildTimeSlot('Close', _closeTime, () => _pickTime(false))),
            ],
          ),

          const SizedBox(height: 32),

          // ── Description Section ──
          _buildSectionHeader('Description'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              controller: _descriptionCtrl,
              maxLines: 4,
              style: const TextStyle(fontSize: 15, color: Color(0xFF1A1C1C)),
              decoration: const InputDecoration(
                hintText: 'Describe your restaurant, specialties, ambiance...',
                hintStyle: TextStyle(color: Color(0xFFBFBFBF), fontSize: 15),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Photos Section ──
          _buildSectionHeader('Photos'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildImageCard('Logo', _logoUrl, Icons.restaurant)),
              const SizedBox(width: 12),
              Expanded(child: _buildImageCard('Cover Image', _coverImageUrl, Icons.image_outlined)),
            ],
          ),

          const SizedBox(height: 40),

          // Save button at the bottom
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBB0018),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Section Header ───────────────────────────

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF1A1C1C),
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ── Text Field ───────────────────────────────

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF262626),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(color: Color(0xFFBB0018), fontSize: 14),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A1C1C)),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
              isDense: true,
            ),
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
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCuisine,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF8E8E93), size: 22),
          hint: const Text(
            'Select cuisine type',
            style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 15),
          ),
          style: const TextStyle(color: Color(0xFF1A1C1C), fontSize: 15),
          items: () {
            final items = _cuisineOptions.map((cuisine) {
              return DropdownMenuItem<String>(
                value: cuisine,
                child: Text(cuisine),
              );
            }).toList();
            // If the saved cuisine isn't in the predefined list, add it
            // to avoid Flutter's "exactly one item with value" error.
            if (_selectedCuisine != null &&
                !_cuisineOptions.contains(_selectedCuisine)) {
              items.insert(
                0,
                DropdownMenuItem<String>(
                  value: _selectedCuisine,
                  child: Text(_selectedCuisine!),
                ),
              );
            }
            return items;
          }(),
          onChanged: (value) => setState(() => _selectedCuisine = value),
        ),
      ),
    );
  }

  // ── Time Slot ────────────────────────────────

  Widget _buildTimeSlot(String label, String? time, VoidCallback onTap) {
    final isSet = time != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSet ? const Color(0xFFFFF1F0) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSet ? const Color(0x33BB0018) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          children: [
            Icon(
              label == 'Open' ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
              size: 20,
              color: isSet ? const Color(0xFFBB0018) : const Color(0xFFBFBFBF),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimeDisplay(time),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSet ? const Color(0xFF1A1C1C) : const Color(0xFFBFBFBF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Image Card ───────────────────────────────

  Widget _buildImageCard(String label, String? imageUrl, IconData fallbackIcon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF262626),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: imageUrl != null && imageUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildImagePlaceholder(fallbackIcon),
                  ),
                )
              : _buildImagePlaceholder(fallbackIcon),
        ),
      ],
    );
  }

  Widget _buildImagePlaceholder(IconData icon) {
    return Center(
      child: Icon(icon, size: 32, color: const Color(0xFFBFBFBF)),
    );
  }
}
