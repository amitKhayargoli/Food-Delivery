import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:baato_maps/baato_maps.dart';
// ignore: implementation_imports
import 'package:baato_maps/src/map_core/implementation/baato_map_controller_impl.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'owner_coupon_management_screen.dart';

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

  // Restaurant location (lat/lng set via Baato map picker)
  double? _restaurantLat;
  double? _restaurantLng;
  String _restaurantAddress = '';
  bool _isPickingLocation = false;

  // Baato map state
  final BaatoMapController _mapController = BaatoMapControllerImpl();
  final TextEditingController _searchController = TextEditingController();
  List<BaatoSearchPlace> _searchResults = [];
  bool _showSearchResults = false;
  bool _isSearching = false;
  bool _isMapLoading = true;
  Timer? _searchDebounce;
  Timer? _mapReadyTimer;

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
    _searchController.dispose();
    _searchDebounce?.cancel();
    _mapReadyTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────

  String? get _token => context.read<AuthProvider>().token;

  /// Compute a simple hash of the current form state to detect unsaved changes.
  String _computeFormHash() {
    return '${_restaurantNameCtrl.text}|${_ownerNameCtrl.text}|${_phoneCtrl.text}|'
        '${_emailCtrl.text}|${_addressCtrl.text}|${_descriptionCtrl.text}|'
        '$_selectedCuisine|$_openTime|$_closeTime|$_logoUrl|$_coverImageUrl|'
        '$_restaurantLat|$_restaurantLng|$_restaurantAddress';
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

        // Restaurant location
        _restaurantLat = (app['latitude'] as num?)?.toDouble();
        _restaurantLng = (app['longitude'] as num?)?.toDouble();
        _restaurantAddress = (app['address'] as String?) ?? '';

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
    final messenger = ScaffoldMessenger.of(context);

    // Validate
    if (_restaurantNameCtrl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Restaurant name is required.'),
          backgroundColor: Color(0xFF1E8E3E),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      // Always include lat/lng if they've been set via the map picker
      if (_restaurantLat != (_originalApplication?['latitude'] as num?)?.toDouble()) {
        data['latitude'] = _restaurantLat;
      }
      if (_restaurantLng != (_originalApplication?['longitude'] as num?)?.toDouble()) {
        data['longitude'] = _restaurantLng;
      }

      if (data.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No changes to save.'),
            backgroundColor: Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Restaurant profile updated successfully!'),
            backgroundColor: Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
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

    // ignore: use_build_context_synchronously
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Are you sure you want to leave?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
        final nav = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          nav.pop();
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

          // ── Restaurant Location Section ──
          _buildSectionHeader('Restaurant Location'),
          const SizedBox(height: 12),
          _buildRestaurantLocationSection(),

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

          // ── Coupons Section ──
          _buildSectionHeader('Promotions & Coupons'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const OwnerCouponManagementScreen(),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      size: 24,
                      color: Color(0xFFF9A825),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Coupons',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1C1C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Create and manage discount codes',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFFBFBFBF), size: 24),
                ],
              ),
            ),
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

  // ── Restaurant Location Section ───────────────

  Widget _buildRestaurantLocationSection() {
    final hasLocation = _restaurantLat != null && _restaurantLng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Location info card ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasLocation ? const Color(0xFFE6F4EA) : const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasLocation ? Icons.location_on_rounded : Icons.location_off_rounded,
                  size: 22,
                  color: hasLocation ? const Color(0xFF1E8E3E) : const Color(0xFFBB0018),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLocation
                          ? '${_restaurantLat!.toStringAsFixed(5)}, ${_restaurantLng!.toStringAsFixed(5)}'
                          : 'No location set',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    if (_restaurantAddress.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _restaurantAddress,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: TextButton(
                  onPressed: () {
                    final wasPicking = _isPickingLocation;
                    setState(() => _isPickingLocation = !_isPickingLocation);
                    // Auto-init GPS when opening the map for the first time
                    if (!wasPicking && _restaurantLat == null) {
                      _initMapLocation();
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFBB0018),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _isPickingLocation ? 'Collapse' : (hasLocation ? 'Change' : 'Set'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Map picker (collapsible) ──
        if (_isPickingLocation) ...[
          const SizedBox(height: 12),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Baato Map
                BaatoMap(
                  controller: _mapController,
                  style: BaatoMapStyle.breeze,
                  initialPosition: hasLocation
                      ? BaatoCoordinate(latitude: _restaurantLat!, longitude: _restaurantLng!)
                      : BaatoCoordinate(latitude: 27.7172, longitude: 85.3240),
                  initialZoom: 15.0,
                  myLocationEnabled: true,
                  onMapCreated: (_) {
                    _mapReadyTimer = Timer(const Duration(milliseconds: 1200), () {
                      if (mounted) setState(() => _isMapLoading = false);
                    });
                  },
                  onMapClick: (point, coordinate, features) {
                    _onMapTapped(coordinate);
                  },
                ),

                // Map loading overlay
                if (_isMapLoading)
                  Container(
                    color: Colors.white.withValues(alpha: 0.85),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFBB0018)),
                          SizedBox(height: 8),
                          Text('Loading map...',
                              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
                        ],
                      ),
                    ),
                  ),

                // Center pin
                if (!_isMapLoading)
                  const IgnorePointer(
                    child: Align(
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Color(0xFFBB0018),
                            size: 36,
                          ),
                          SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ),

                // Search bar at top
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(10),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search location...',
                            hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8E8E93)),
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFBB0018), width: 1.5),
                            ),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),

                      // Search results
                      if (_showSearchResults)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final place = _searchResults[index];
                                return InkWell(
                                  onTap: () => _onSearchResultTapped(place),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined,
                                            size: 16, color: Color(0xFF8E8E93)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(place.name,
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                                              if (place.address.isNotEmpty)
                                                Text(place.address,
                                                    style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the map or search to set your restaurant\'s location. Used to find nearby riders.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
        ],
      ],
    );
  }

  // ── Baato Search & Map Handlers ──────────────

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final coord = BaatoCoordinate(
        latitude: _restaurantLat ?? 27.7172,
        longitude: _restaurantLng ?? 85.3240,
      );
      final response = await Baato.api.place.search(query, currentCoordinate: coord, limit: 5);
      final results = response.data ?? [];
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _showSearchResults = results.isNotEmpty;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _onSearchResultTapped(BaatoSearchPlace place) async {
    setState(() {
      _showSearchResults = false;
      _isSearching = true;
    });
    _searchController.text = place.name;
    try {
      final detailResponse = await Baato.api.place.getDetail(place.placeId);
      if (!mounted) return;
      final detailData = detailResponse.data;
      if (detailData != null && detailData.isNotEmpty) {
        final detail = detailData.first;
        final coord = BaatoCoordinate(
          latitude: detail.centroid.latitude,
          longitude: detail.centroid.longitude,
        );
        _mapController.cameraManager.moveTo(coord, zoom: 16.0, animate: true);
        await _updateLocation(coord, label: detail.name.isNotEmpty ? detail.name : detail.address);
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearching = false);
  }

  void _onMapTapped(BaatoCoordinate coordinate) {
    _searchController.clear();
    setState(() => _showSearchResults = false);
    _mapController.cameraManager.moveTo(coordinate, zoom: 15.0, animate: true);
    _updateLocation(coordinate);
  }

  Future<void> _updateLocation(BaatoCoordinate coordinate, {String? label}) async {
    setState(() {
      _restaurantLat = coordinate.latitude;
      _restaurantLng = coordinate.longitude;
      _restaurantAddress = label ?? '';
    });

    if (label != null) return;

    // Reverse geocode for address
    try {
      final response = await Baato.api.place.reverseGeocode(coordinate, limit: 1);
      if (!mounted) return;
      final places = response.data;
      if (places != null && places.isNotEmpty) {
        final first = places.first;
        setState(() {
          _restaurantAddress = first.name.isNotEmpty ? first.name : first.address;
        });
      }
    } catch (_) {}
  }

  Future<void> _initMapLocation() async {
    // If no location is set yet, try GPS
    if (_restaurantLat != null) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted || _restaurantLat != null) return;
      final coord = BaatoCoordinate(latitude: position.latitude, longitude: position.longitude);
      await _updateLocation(coord);
    } catch (_) {}
  }

}
