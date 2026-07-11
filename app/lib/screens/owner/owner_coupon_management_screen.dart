import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

/// Owner-facing screen for managing restaurant coupons.
/// Shows all coupons for the restaurant and lets owners create new ones.
class OwnerCouponManagementScreen extends ConsumerStatefulWidget {
  const OwnerCouponManagementScreen({super.key});

  @override
  ConsumerState<OwnerCouponManagementScreen> createState() =>
      _OwnerCouponManagementScreenState();
}

class _OwnerCouponManagementScreenState
    extends ConsumerState<OwnerCouponManagementScreen> {
  List<Map<String, dynamic>> _coupons = [];
  bool _isLoading = true;
  String? _error;

  String? get _token => context.read<AuthProvider>().token;

  @override
  void initState() {
    super.initState();
    _fetchCoupons();
  }

  Future<void> _fetchCoupons() async {
    final token = _token;
    if (token == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final coupons = await api.getMyCoupons(token: token);
      if (mounted) {
        setState(() {
          _coupons = coupons;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load coupons.'; _isLoading = false; });
    }
  }

  Future<void> _deleteCoupon(String id) async {
    final token = _token;
    if (token == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Coupon'),
        content: const Text('Are you sure you want to delete this coupon?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFF5222D)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final api = di.sl<ApiService>();
      await api.deleteCoupon(couponId: id, token: token);
      _fetchCoupons();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coupon deleted'), behavior: SnackBarBehavior.floating),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showCreateCouponSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _CreateCouponSheet(),
    );

    if (result != null) {
      // Coupon was created — refresh the list
      _fetchCoupons();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coupon created successfully!'),
            backgroundColor: Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1C1C)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Manage Coupons',
          style: TextStyle(
            color: Color(0xFF1A1C1C),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _showCreateCouponSheet,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBB0018),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: _buildBody(),
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
            Text('Loading coupons...', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchCoupons,
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

    if (_coupons.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.local_offer_rounded, size: 36, color: Color(0xFFF9A825)),
            ),
            const SizedBox(height: 16),
            const Text('No coupons yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1A1C1C))),
            const SizedBox(height: 8),
            const Text('Create your first coupon to attract more customers',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showCreateCouponSheet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Coupon'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBB0018),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCoupons,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _coupons.length,
        itemBuilder: (context, index) => _buildCouponCard(_coupons[index]),
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon) {
    final id = coupon['id'] as String? ?? '';
    final code = coupon['code'] as String? ?? '';
    final discountType = coupon['discount_type'] as String? ?? 'PERCENTAGE';
    final discountValue = (coupon['discount_value'] as num?)?.toDouble() ?? 0;
    final usedCount = (coupon['used_count'] as num?)?.toInt() ?? 0;
    final usageLimit = coupon['usage_limit'] as int?;
    final isActive = coupon['is_active'] as bool? ?? true;
    final expiresAt = coupon['expires_at'] as String?;
    final description = coupon['description'] as String?;
    final minOrder = (coupon['min_order_amount'] as num?)?.toDouble();
    final maxCap = (coupon['max_discount_cap'] as num?)?.toDouble();
    final isGlobal = coupon['restaurant_id'] == null;

    final discountLabel = discountType == 'PERCENTAGE'
        ? '${discountValue.toStringAsFixed(0)}% OFF'
        : 'Rs. ${discountValue.toStringAsFixed(0)} OFF';
    final expiryLabel = expiresAt != null
        ? 'Expires ${_formatDate(expiresAt)}'
        : 'No expiry';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? const Color(0xFFE5E7EB) : const Color(0xFFFFF1F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Code + Discount badge ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFBB0018),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F4EA),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  discountLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E8E3E),
                  ),
                ),
              ),
              if (!isActive) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEDED),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Inactive',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF5E3F3C)),
                  ),
                ),
              ],
              if (isGlobal) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Global',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1967D2)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // ── Description ──
          if (description != null && description.isNotEmpty) ...[
            Text(
              description,
              style: const TextStyle(fontSize: 13, color: Color(0xFF5C5C5C)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
          ],

          // ── Details ──
          Row(
            children: [
              _buildDetailChip(Icons.checklist_rounded, '$usedCount${usageLimit != null ? '/$usageLimit' : ''} used'),
              if (minOrder != null) ...[
                const SizedBox(width: 12),
                _buildDetailChip(Icons.monetization_on_outlined, 'Min: Rs. ${minOrder.toStringAsFixed(0)}'),
              ],
              if (maxCap != null && discountType == 'PERCENTAGE') ...[
                const SizedBox(width: 12),
                _buildDetailChip(Icons.arrow_upward_rounded, 'Max: Rs. ${maxCap.toStringAsFixed(0)}'),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // ── Expiry + Delete ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                expiryLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
              GestureDetector(
                onTap: () => _deleteCoupon(id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFBB0018)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF8E8E93)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
      ],
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ──────────────────────────────────────────────
//  Create Coupon Bottom Sheet
// ──────────────────────────────────────────────

class _CreateCouponSheet extends StatefulWidget {
  const _CreateCouponSheet();

  @override
  State<_CreateCouponSheet> createState() => _CreateCouponSheetState();
}

class _CreateCouponSheetState extends State<_CreateCouponSheet> {
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _maxCapCtrl = TextEditingController();
  final _usageLimitCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  String _discountType = 'PERCENTAGE';
  DateTime? _expiryDate;
  bool _isCreating = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _minOrderCtrl.dispose();
    _maxCapCtrl.dispose();
    _usageLimitCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _create() async {
    final token = _token;
    if (token == null) return;

    // Validate
    if (_codeCtrl.text.trim().isEmpty || _valueCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code and discount value are required.'), backgroundColor: Colors.red),
      );
      return;
    }

    final discountValue = double.tryParse(_valueCtrl.text.trim());
    if (discountValue == null || discountValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid discount value.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final api = di.sl<ApiService>();
      await api.createCoupon(
        code: _codeCtrl.text.trim(),
        discountType: _discountType,
        discountValue: discountValue,
        minOrderAmount: double.tryParse(_minOrderCtrl.text.trim()),
        maxDiscountCap: double.tryParse(_maxCapCtrl.text.trim()),
        usageLimit: int.tryParse(_usageLimitCtrl.text.trim()),
        expiresAt: _expiryDate?.toIso8601String(),
        description: _descriptionCtrl.text.trim().isNotEmpty
            ? _descriptionCtrl.text.trim()
            : null,
        token: token,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Signal success
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create coupon.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('Create Coupon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 1),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code
                  _buildLabel('Coupon Code'),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _codeCtrl,
                    hint: 'e.g. SAVE20',
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),

                  // Discount type + value
                  _buildLabel('Discount Type'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTypeChip('PERCENTAGE', 'Percentage %'),
                      const SizedBox(width: 10),
                      _buildTypeChip('FIXED', 'Fixed Amount'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Discount Value'),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _valueCtrl,
                    hint: _discountType == 'PERCENTAGE' ? 'e.g. 20' : 'e.g. 100',
                    keyboardType: TextInputType.number,
                    prefix: _discountType == 'PERCENTAGE' ? null : 'Rs. ',
                    suffix: _discountType == 'PERCENTAGE' ? '%' : null,
                  ),
                  const SizedBox(height: 16),

                  // Min order
                  _buildLabel('Minimum Order Amount (optional)'),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _minOrderCtrl,
                    hint: 'e.g. 500',
                    keyboardType: TextInputType.number,
                    prefix: 'Rs. ',
                  ),
                  const SizedBox(height: 16),

                  // Max cap (for percentage)
                  if (_discountType == 'PERCENTAGE') ...[
                    _buildLabel('Maximum Discount Cap (optional)'),
                    const SizedBox(height: 6),
                    _buildTextField(
                      controller: _maxCapCtrl,
                      hint: 'e.g. 200',
                      keyboardType: TextInputType.number,
                      prefix: 'Rs. ',
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Usage limit
                  _buildLabel('Usage Limit (optional)'),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _usageLimitCtrl,
                    hint: 'e.g. 100',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),

                  // Expiry
                  _buildLabel('Expiry Date (optional)'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 18, color: _expiryDate != null
                              ? const Color(0xFFBB0018) : const Color(0xFFBFBFBF)),
                          const SizedBox(width: 10),
                          Text(
                            _expiryDate != null
                                ? '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'
                                : 'Pick a date',
                            style: TextStyle(
                              fontSize: 14,
                              color: _expiryDate != null ? const Color(0xFF1A1C1C) : const Color(0xFFBFBFBF),
                            ),
                          ),
                          if (_expiryDate != null)
                            GestureDetector(
                              onTap: () => setState(() => _expiryDate = null),
                              child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF8E8E93)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  _buildLabel('Description (optional)'),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _descriptionCtrl,
                    hint: 'e.g. Flat 20% off on all orders',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),

                  // Create button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _create,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFBB0018),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create Coupon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF262626)));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    String? prefix,
    String? suffix,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          if (prefix != null) Text(prefix, style: const TextStyle(fontSize: 14, color: Color(0xFF5C5C5C))),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              maxLines: maxLines,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1A1C1C)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (suffix != null) Text(suffix, style: const TextStyle(fontSize: 14, color: Color(0xFF5C5C5C))),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label) {
    final isSelected = _discountType == type;
    return GestureDetector(
      onTap: () => setState(() => _discountType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF1F0) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFBB0018) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? const Color(0xFFBB0018) : const Color(0xFF5C5C5C),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFBB0018)),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }
}
