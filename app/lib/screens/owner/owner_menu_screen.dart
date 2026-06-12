import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../core/services/api_service.dart';
import '../../widgets/toggle_switch.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'add_edit_menu_item_screen.dart';

class OwnerMenuScreen extends StatefulWidget {
  const OwnerMenuScreen({super.key});

  @override
  State<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends State<OwnerMenuScreen> {
  List<Food> _items = [];
  bool _isLoading = true;
  String? _error;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _fetchItems() async {
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
      final rawItems = await api.getMenuItems(token: token);
      if (!mounted) return;
      setState(() {
        _items = rawItems.map((j) => Food.fromJson(j)).toList();
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
        _error = 'Failed to load menu items. Check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAvailability(Food item, bool isAvailable) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.toggleMenuItemAvailability(
        itemId: item.id,
        isAvailable: isAvailable,
        token: token,
      );
      // Update the item locally instead of refreshing the entire list
      setState(() {
        final index = _items.indexWhere((i) => i.id == item.id);
        if (index != -1) {
          _items[index] = Food(
            id: _items[index].id,
            restaurantId: _items[index].restaurantId,
            name: _items[index].name,
            description: _items[index].description,
            price: _items[index].price,
            imageUrl: _items[index].imageUrl,
            categoryId: _items[index].categoryId,
            isAvailable: isAvailable,
            sizes: _items[index].sizes,
            imageUrls: _items[index].imageUrls,
            calories: _items[index].calories,
            portionWeight: _items[index].portionWeight,
            allergens: _items[index].allergens,
            ingredients: _items[index].ingredients,
            prepTime: _items[index].prepTime,
          );
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openAddEdit({Food? item}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditMenuItemScreen(existingItem: item),
      ),
    );
    if (result == true) {
      _fetchItems();
    }
  }

  // ── Derived data ────────────────────────────

  List<String> get _categories {
    final cats = <String>{};
    for (final item in _items) {
      if (item.categoryId.isNotEmpty) cats.add(item.categoryId);
    }
    return cats.toList()..sort();
  }

  List<Food> get _filteredItems {
    if (_selectedCategory == 'All') return _items;
    return _items.where((i) => i.categoryId == _selectedCategory).toList();
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
            if (!_isLoading && _error == null) _buildCategoryChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: _buildAddItemButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ── Header ───────────────────────────────────

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
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1A1C1C)),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Menu Management',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                height: 1.33,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category filter chips ────────────────────

  Widget _buildCategoryChips() {
    final allCount = _items.length;
    final chips = <String>['All', ..._categories];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final cat = chips[index];
            final isActive = _selectedCategory == cat;
            final label = cat == 'All' ? 'All Items ($allCount)' : cat;

            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFBB0018) : const Color(0xFFEFEDED),
                  borderRadius: BorderRadius.circular(9999),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF5E3F3C),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.29,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text(
              'Loading menu...',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchItems,
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

    if (_filteredItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchItems,
        color: const Color(0xFFBB0018),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.restaurant_menu_rounded,
                        size: 56, color: Color(0xFFD9D9D9)),
                    const SizedBox(height: 12),
                    Text(
                      _selectedCategory == 'All'
                          ? 'No menu items yet'
                          : 'No items in "$_selectedCategory"',
                      style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 16,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap + to add your first item',
                      style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchItems,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _filteredItems.length,
        itemBuilder: (context, index) => _buildMenuItemCard(_filteredItems[index]),
      ),
    );
  }

  // ── Menu item card ───────────────────────────

  Widget _buildMenuItemCard(Food item) {
    return IntrinsicHeight(
      child: GestureDetector(
        onTap: () => _openAddEdit(item: item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x141B1C1C),
                blurRadius: 12,
                offset: Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Thumbnail ──────────────────────
            Align(
              alignment: Alignment.topCenter,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildThumbnail(item),
              ),
            ),
            const SizedBox(width: 12),

            // ── Info ───────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + photo count badge
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            color: Color(0xFF1A1C1C),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.imageUrls.length >= 3) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F4EA),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: const Text(
                            '3+',
                            style: TextStyle(
                              color: Color(0xFF1E8E3E),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1.50,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Description
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: Color(0xFF5C5C5C),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.38,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 4),

                  // Price + category + size badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Rs. ${item.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Color(0xFFBB0018),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.50,
                        ),
                      ),
                      if (item.categoryId.isNotEmpty)
                        _buildPillBadge(
                          label: item.categoryId.toUpperCase(),
                          bgColor: const Color(0xFFEFEDED),
                          textColor: const Color(0xFF5E3F3C),
                        ),
                      if (item.sizes.isNotEmpty)
                        _buildPillBadge(
                          label: '${item.sizes.length} Size${item.sizes.length > 1 ? 's' : ''}',
                          bgColor: const Color(0xFFE8F0FE),
                          textColor: const Color(0xFF1967D2),
                        ),
                    ],
                  ),

                  // Nutrition row
                  if (item.calories != null || item.portionWeight != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (item.calories != null)
                          _buildPillBadge(
                            label: '${item.calories} kcal',
                            bgColor: const Color(0xFFFFF8E1),
                            textColor: const Color(0xFFF9A825),
                          ),
                        if (item.portionWeight != null)
                          _buildPillBadge(
                            label: item.portionWeight!,
                            bgColor: const Color(0xFFE3F2FD),
                            textColor: const Color(0xFF1E88E5),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ── Availability toggle (right side) ──
            _buildAvailabilitySection(item),
          ],
        ),
      ),
      ),
    );
  }

  // ── Thumbnail helper ─────────────────────────

  Widget _buildThumbnail(Food item) {
    final hasImage =
        item.imageUrls.isNotEmpty || item.imageUrl.isNotEmpty;

    if (!hasImage) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.restaurant, color: Color(0xFFBFBFBF), size: 28),
      );
    }

    return Image.network(
      item.imageUrls.isNotEmpty ? item.imageUrls.first : item.imageUrl,
      width: 72,
      height: 72,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.broken_image, color: Color(0xFFBFBFBF), size: 28),
      ),
    );
  }

  // ── Pill badge ───────────────────────────────

  Widget _buildPillBadge({
    required String label,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.50,
        ),
      ),
    );
  }

  // ── Availability section (right column) ──────

  Widget _buildAvailabilitySection(Food item) {
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Status text at top
          Text(
            item.isAvailable ? 'In Stock' : 'Out of Stock',
            style: TextStyle(
              color: item.isAvailable
                  ? const Color(0xFF1E8E3E)
                  : const Color(0xFFD93025),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.50,
            ),
          ),
          // Custom toggle pill at bottom
          ToggleSwitch(
            value: item.isAvailable,
            onChanged: (v) => _toggleAvailability(item, v),
          ),
        ],
      ),
    );
  }

  // ── Add Item button ──────────────────────────

  Widget _buildAddItemButton() {
    return GestureDetector(
      onTap: () => _openAddEdit(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFBB0018),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
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
        child: const Text(
          'Add Item',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.29,
          ),
        ),
      ),
    );
  }
}
