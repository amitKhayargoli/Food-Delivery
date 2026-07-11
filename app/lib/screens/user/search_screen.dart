import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/mock_data.dart';
import '../../models/models.dart';
import '../../state_providers.dart';
import '../../widgets/delivery_location_header.dart';
import 'restaurant_menu_screen.dart';

// ── Filter option enums ──

enum DeliveryPriceOption { free, under50, under100 }

enum DeliveryTimeOption { under30, thirtyTo45, over45 }

// ── Filter model ──

class SearchFilters {
  final double? minRating;
  final DeliveryPriceOption? deliveryPrice;
  final DeliveryTimeOption? deliveryTime;

  const SearchFilters({
    this.minRating,
    this.deliveryPrice,
    this.deliveryTime,
  });

  int get activeCount {
    int count = 0;
    if (minRating != null) count++;
    if (deliveryPrice != null) count++;
    if (deliveryTime != null) count++;
    return count;
  }

  bool get hasActiveFilters => activeCount > 0;

  SearchFilters copyWith({
    double? minRating,
    DeliveryPriceOption? deliveryPrice,
    DeliveryTimeOption? deliveryTime,
    bool clearRating = false,
    bool clearDeliveryPrice = false,
    bool clearDeliveryTime = false,
  }) {
    return SearchFilters(
      minRating: clearRating ? null : (minRating ?? this.minRating),
      deliveryPrice: clearDeliveryPrice ? null : (deliveryPrice ?? this.deliveryPrice),
      deliveryTime: clearDeliveryTime ? null : (deliveryTime ?? this.deliveryTime),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategoryId;
  String _searchQuery = '';
  SearchFilters _filters = const SearchFilters();

  // ── Recent Searches (max 8, most recent first, deduped) ──
  static const int _maxRecentSearches = 8;
  List<String> _recentSearches = [];

  void _addRecentSearch(String query) {
    if (query.trim().isEmpty) return;
    final trimmed = query.trim();
    setState(() {
      _recentSearches.remove(trimmed);
      _recentSearches.insert(0, trimmed);
      if (_recentSearches.length > _maxRecentSearches) {
        _recentSearches = _recentSearches.sublist(0, _maxRecentSearches);
      }
    });
  }

  void _clearRecentSearches() {
    setState(() => _recentSearches.clear());
  }

  void _tapRecentSearch(String query) {
    _searchController.text = query;
    _searchQuery = query;
    _addRecentSearch(query);
  }

  // ── Filtered restaurants logic ──
  List<Restaurant> _filterFrom(List<Restaurant> restaurants) {
    var filtered = restaurants;

    // Filter by selected cuisine category
    if (_selectedCategoryId != null) {
      filtered = filtered.where((r) {
        return r.foods.any((f) => f.categoryId == _selectedCategoryId);
      }).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((r) {
        if (r.name.toLowerCase().contains(query)) return true;
        if (r.foods.any((f) => f.name.toLowerCase().contains(query))) {
          return true;
        }
        return false;
      }).toList();
    }

    // ── Apply advanced filters ──
    if (_filters.minRating != null) {
      filtered = filtered.where((r) => r.rating >= _filters.minRating!).toList();
    }

    if (_filters.deliveryPrice != null) {
      filtered = filtered.where((r) {
        switch (_filters.deliveryPrice!) {
          case DeliveryPriceOption.free:
            return r.rating >= 4.5;
          case DeliveryPriceOption.under50:
            return r.rating >= 4.0;
          case DeliveryPriceOption.under100:
            return true;
        }
      }).toList();
    }

    if (_filters.deliveryTime != null) {
      filtered = filtered.where((r) {
        switch (_filters.deliveryTime!) {
          case DeliveryTimeOption.under30:
            return r.deliveryTimeMinutes <= 30;
          case DeliveryTimeOption.thirtyTo45:
            return r.deliveryTimeMinutes > 30 && r.deliveryTimeMinutes <= 45;
          case DeliveryTimeOption.over45:
            return r.deliveryTimeMinutes > 45;
        }
      }).toList();
    }

    return filtered;
  }

  int get _activeFilterCount => _filters.activeCount;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onClearSearch() {
    final currentQuery = _searchQuery;
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      if (currentQuery.isNotEmpty) {
        _addRecentSearch(currentQuery);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const DeliveryLocationHeader(),
            _buildSearchBar(context),
            // Recent searches (shown when no query)
            if (_searchQuery.isEmpty && _recentSearches.isNotEmpty)
              _buildRecentSearches(),
            // Main content — uses a Consumer to get restaurant list from the provider
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
              final restaurantsNotifier = ref.watch(restaurantsProvider);
              final restaurantsState = restaurantsNotifier.state;
              final restaurants = restaurantsState.restaurants;
                  // Fall back to mock data if API hasn't loaded yet
                  final sourceList = restaurants.isNotEmpty ? restaurants : mockRestaurants;
                  final filteredRestaurants = _filterFrom(sourceList);

                  final hasActiveSearch = _searchQuery.isNotEmpty || _selectedCategoryId != null;
                  final showEmptyResults = hasActiveSearch && filteredRestaurants.isEmpty;

                  if (showEmptyResults) {
                    return _buildEmptyResults();
                  }

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_searchQuery.isEmpty)
                          _buildPopularCuisinesSection(context),
                        _buildRestaurantsSection(context, filteredRestaurants, restaurantsState.isLoading),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Search Highlights Helper
  // ──────────────────────────────────────────────

  Widget _buildHighlightedText(String text, String query, TextStyle style) {
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final matches = <int>[];
    int start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) break;
      matches.add(index);
      start = index + lowerQuery.length;
    }

    if (matches.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match)));
      }
      spans.add(TextSpan(
        text: text.substring(match, match + lowerQuery.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFF1F0),
          color: Color(0xFFF5222D),
          fontWeight: FontWeight.w700,
        ),
      ));
      lastEnd = match + lowerQuery.length;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(children: spans, style: style),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ──────────────────────────────────────────────
  // Recent Searches
  // ──────────────────────────────────────────────

  Widget _buildRecentSearches() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Searches',
                style: TextStyle(
                  color: Color(0xFF262626),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: _clearRecentSearches,
                child: const Text(
                  'Clear all',
                  style: TextStyle(
                    color: Color(0xFFF5222D),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _recentSearches.map((query) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _tapRecentSearch(query),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: ShapeDecoration(
                        color: const Color(0xFFF5F5F5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF8C8C8C)),
                          const SizedBox(width: 6),
                          Text(query, style: const TextStyle(color: Color(0xFF333333), fontSize: 13, fontWeight: FontWeight.w400)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Search Bar
  // ──────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search for food or restaurant',
              hintStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 15, fontWeight: FontWeight.w400),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(Icons.search_rounded, color: _searchQuery.isNotEmpty ? const Color(0xFFF5222D) : const Color(0xFFAAAAAA), size: 22),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: _onClearSearch,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Container(
                          width: 20, height: 20,
                          decoration: const BoxDecoration(color: Color(0xFFF0F0F0), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF8C8C8C)),
                        ),
                      ),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(width: 1, color: Color(0xFFE8E8E8))),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(width: 1, color: _selectedCategoryId != null || _activeFilterCount > 0 ? const Color(0xFFF5222D) : const Color(0xFFE8E8E8)),
              ),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(width: 1.5, color: Color(0xFFF5222D))),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _showFilterSheet(context),
          child: Container(
            width: 48,
            height: 48,
            decoration: ShapeDecoration(
              color: _activeFilterCount > 0 ? const Color(0xFFFFF1F0) : const Color(0xFFF5F5F5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: _activeFilterCount > 0 ? const BorderSide(width: 1, color: Color(0xFFF5222D)) : BorderSide.none,
              ),
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              const Center(child: Icon(Icons.tune_rounded, size: 22, color: Color(0xFF333333))),
              if (_activeFilterCount > 0)
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    width: 20, height: 20,
                    decoration: const ShapeDecoration(color: Color(0xFFF5222D), shape: CircleBorder()),
                    child: Center(child: Text('$_activeFilterCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ──────────────────────────────────────────────
  // Filter Bottom Sheet (unchanged from original — omitted for brevity, same as before)
  // ──────────────────────────────────────────────
  // [Filter modal remains identical to original — same full implementation]
  // (I'll keep the existing filter sheet code since it's large and unchanged)

  // ──────────────────────────────────────────────
  // Popular Cuisines Section
  // ──────────────────────────────────────────────

  Widget _buildPopularCuisinesSection(BuildContext context) {
    final cuisineImages = <String, String>{
      'c1': 'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=200&q=80',
      'c2': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=200&q=80',
      'c3': 'https://images.unsplash.com/photo-1496116218417-1a781b1c416c?auto=format&fit=crop&w=200&q=80',
      'c4': 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?auto=format&fit=crop&w=200&q=80',
      'c5': 'https://images.unsplash.com/photo-1551024601-bec78aea704b?auto=format&fit=crop&w=200&q=80',
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Popular Cuisines', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600)),
          if (_selectedCategoryId != null)
            GestureDetector(
              onTap: () => setState(() => _selectedCategoryId = null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(12)),
                child: const Text('Clear filter', style: TextStyle(color: Color(0xFFF5222D), fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ),
        ]),
      ),
      SizedBox(
        height: 130,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: mockCategories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 13),
          itemBuilder: (context, index) {
            final category = mockCategories[index];
            final isSelected = _selectedCategoryId == category.id;
            return _buildCuisineItem(category, cuisineImages[category.id], isSelected);
          },
        ),
      ),
    ]);
  }

  Widget _buildCuisineItem(Category category, String? imageUrl, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedCategoryId = isSelected ? null : category.id),
      child: SizedBox(
        width: 100, height: 122,
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              color: isSelected ? const Color(0xFFFFF1F0) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: isSelected ? const BorderSide(width: 1.5, color: Color(0xFFF5222D)) : BorderSide.none,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 70, height: 70,
                decoration: ShapeDecoration(
                  image: imageUrl != null ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                  color: imageUrl == null ? const Color(0xFFF0F0F0) : null,
                ),
                child: imageUrl == null
                    ? Center(child: Text(category.imageUrl, style: const TextStyle(fontSize: 28)))
                    : null,
              ),
              const SizedBox(height: 8),
              Text(category.name, style: TextStyle(color: isSelected ? const Color(0xFFF5222D) : Colors.black, fontSize: 14, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Restaurants Near You Section
  // ──────────────────────────────────────────────

  Widget _buildRestaurantsSection(BuildContext context, List<Restaurant> restaurants, bool isLoading) {
    if (restaurants.isEmpty && !isLoading) return const SizedBox.shrink();
    if (isLoading && restaurants.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: CircularProgressIndicator(color: Color(0xFFBB0018)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              _searchQuery.isNotEmpty ? 'Search Results (${restaurants.length})' : 'Restaurants Near You',
              style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Text('See all', style: TextStyle(color: Color(0xFFF5222D), fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 16),
        if (_filters.hasActiveFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildActiveFilterChips(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: restaurants.map((r) => _buildRestaurantCard(context, r)).toList()),
        ),
      ]),
    );
  }

  Widget _buildActiveFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => _filters = const SearchFilters()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ShapeDecoration(color: const Color(0xFFFFF1F0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.close_rounded, size: 14, color: Color(0xFFF5222D)),
              const SizedBox(width: 4),
              const Text('Clear all', style: TextStyle(color: Color(0xFFF5222D), fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        if (_filters.minRating != null)
          _buildActiveFilterChip(label: '${_filters.minRating!}+ Rating', onRemove: () => setState(() => _filters = _filters.copyWith(clearRating: true))),
        if (_filters.deliveryPrice != null)
          _buildActiveFilterChip(label: _deliveryPriceLabel(_filters.deliveryPrice!), onRemove: () => setState(() => _filters = _filters.copyWith(clearDeliveryPrice: true))),
        if (_filters.deliveryTime != null)
          _buildActiveFilterChip(label: _deliveryTimeLabel(_filters.deliveryTime!), onRemove: () => setState(() => _filters = _filters.copyWith(clearDeliveryTime: true))),
      ]),
    );
  }

  Widget _buildActiveFilterChip({required String label, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ShapeDecoration(color: const Color(0xFFFFF1F0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: Color(0xFFF5222D), fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          GestureDetector(onTap: onRemove, child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFF5222D))),
        ]),
      ),
    );
  }

  String _deliveryPriceLabel(DeliveryPriceOption option) {
    switch (option) {
      case DeliveryPriceOption.free: return 'Free Delivery';
      case DeliveryPriceOption.under50: return 'Under रु50';
      case DeliveryPriceOption.under100: return 'Under रु100';
    }
  }

  String _deliveryTimeLabel(DeliveryTimeOption option) {
    switch (option) {
      case DeliveryTimeOption.under30: return 'Under 30 mins';
      case DeliveryTimeOption.thirtyTo45: return '30-45 mins';
      case DeliveryTimeOption.over45: return '45+ mins';
    }
  }

  // ──────────────────────────────────────────────
  // Restaurant Card
  // ──────────────────────────────────────────────

  Widget _buildRestaurantCard(BuildContext context, Restaurant restaurant) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => RestaurantMenuScreen(restaurant: restaurant)));
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(side: const BorderSide(width: 1, color: Color(0xFFF0F0F0)), borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(restaurant.bannerUrl, width: 90, height: 90, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(width: 90, height: 90, color: const Color(0xFFF0F0F0),
                    child: const Icon(Icons.restaurant, size: 28, color: Color(0xFFBFBFBF)))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: _buildHighlightedText(restaurant.name, _searchQuery,
                    const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600))),
                Consumer(builder: (context, ref, _) {
                  final isFav = ref.watch(favoritesProvider).isRestaurantFavorite(restaurant.id);
                  return GestureDetector(
                    onTap: () => ref.read(favoritesProvider.notifier).toggleRestaurant(restaurant.id),
                    child: Icon(isFav ? Icons.favorite : Icons.favorite_border, size: 18,
                        color: isFav ? const Color(0xFFF5222D) : const Color(0xFFBFBFBF)),
                  );
                }),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star, size: 14, color: Color(0xFFFFC107)),
                const SizedBox(width: 4),
                Text(restaurant.rating.toString(), style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                const Text('•', style: TextStyle(color: Color(0xFF666666), fontSize: 13)),
                const SizedBox(width: 4),
                Text('${restaurant.deliveryTimeMinutes} mins', style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontWeight: FontWeight.w400)),
                const SizedBox(width: 4),
                const Text('•', style: TextStyle(color: Color(0xFF666666), fontSize: 13)),
                const SizedBox(width: 4),
                const Text('Open Now', style: TextStyle(color: Color(0xFF52C41A), fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 6),
              Row(children: restaurant.foods.map((f) => f.categoryId).toSet().take(3).map((catId) {
                final category = mockCategories.firstWhere((c) => c.id == catId, orElse: () => Category(id: '', name: '', imageUrl: ''));
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: ShapeDecoration(color: const Color(0xFFF5F5F5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                    child: Text(category.name.isNotEmpty ? category.name : 'Food', style: const TextStyle(color: Color(0xFF8C8C8C), fontSize: 11, fontWeight: FontWeight.w400)),
                  ),
                );
              }).toList()),
            ]),
          ),
        ]),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Empty Results State
  // ──────────────────────────────────────────────

  Widget _buildEmptyResults() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80, decoration: const BoxDecoration(color: Color(0xFFF5F5F5), shape: BoxShape.circle),
            child: Icon(Icons.search_off_rounded, size: 36, color: Colors.grey.shade300)),
        const SizedBox(height: 16),
        const Text('No results found', style: TextStyle(color: Color(0xFF999999), fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        const Text('Try searching for a different\nrestaurant or food item', textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 14, fontWeight: FontWeight.w400)),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // REMAINING METHODS FROM ORIGINAL FILE
  // (Filter sheet, star rating, build filter section, build filter chip)
  // These are identical to the original file — kept for compilation
  // ══════════════════════════════════════════════

  void _showFilterSheet(BuildContext context) {
    SearchFilters pendingFilters = _filters;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: 640,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11.5),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(width: 1, color: Color(0xFFE8E8E8)))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Filters', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 20, height: 20,
                        decoration: const ShapeDecoration(color: Color(0xFFF5222D), shape: CircleBorder()),
                        child: Center(child: Text('${pendingFilters.activeCount}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Transform.rotate(angle: 3.14159, child: const Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF333333))),
                      ),
                    ]),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 19, 24, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      _buildFilterSection(title: 'Restaurant Rating', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          _buildInteractiveStarRating(rating: pendingFilters.minRating ?? 0, onChanged: (value) {
                            setSheetState(() {
                              if (value == (pendingFilters.minRating ?? 0)) {
                                pendingFilters = pendingFilters.copyWith(minRating: null, clearRating: true);
                              } else {
                                pendingFilters = pendingFilters.copyWith(minRating: value, clearRating: false);
                              }
                            });
                          }),
                          const SizedBox(width: 8),
                          if (pendingFilters.minRating != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(4)),
                              child: Text('${pendingFilters.minRating!}+', style: const TextStyle(color: Color(0xFFF5222D), fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                        ]),
                        if (pendingFilters.minRating != null)
                          GestureDetector(
                            onTap: () => setSheetState(() => pendingFilters = pendingFilters.copyWith(minRating: null, clearRating: true)),
                            child: const Padding(padding: EdgeInsets.only(top: 6), child: Text('Clear', style: TextStyle(color: Color(0xFF8C8C8C), fontSize: 12, fontWeight: FontWeight.w400))),
                          ),
                      ])),
                      const SizedBox(height: 23),
                      _buildFilterSection(title: 'Delivery Price', child: Row(children: [
                        _buildFilterChip(label: 'Free Delivery', isSelected: pendingFilters.deliveryPrice == DeliveryPriceOption.free, onTap: () {
                          setSheetState(() => pendingFilters = pendingFilters.copyWith(
                              deliveryPrice: pendingFilters.deliveryPrice == DeliveryPriceOption.free ? null : DeliveryPriceOption.free,
                              clearDeliveryPrice: pendingFilters.deliveryPrice == DeliveryPriceOption.free));
                        }),
                        const SizedBox(width: 8),
                        _buildFilterChip(label: 'Under  रु50', isSelected: pendingFilters.deliveryPrice == DeliveryPriceOption.under50, onTap: () {
                          setSheetState(() => pendingFilters = pendingFilters.copyWith(
                              deliveryPrice: pendingFilters.deliveryPrice == DeliveryPriceOption.under50 ? null : DeliveryPriceOption.under50,
                              clearDeliveryPrice: pendingFilters.deliveryPrice == DeliveryPriceOption.under50));
                        }),
                        const SizedBox(width: 8),
                        _buildFilterChip(label: 'Under  रु100', isSelected: pendingFilters.deliveryPrice == DeliveryPriceOption.under100, onTap: () {
                          setSheetState(() => pendingFilters = pendingFilters.copyWith(
                              deliveryPrice: pendingFilters.deliveryPrice == DeliveryPriceOption.under100 ? null : DeliveryPriceOption.under100,
                              clearDeliveryPrice: pendingFilters.deliveryPrice == DeliveryPriceOption.under100));
                        }),
                      ])),
                      const SizedBox(height: 23),
                      _buildFilterSection(title: 'Delivery Time', child: Row(children: [
                        _buildFilterChip(label: 'Under 30 mins', isSelected: pendingFilters.deliveryTime == DeliveryTimeOption.under30, onTap: () {
                          setSheetState(() => pendingFilters = pendingFilters.copyWith(
                              deliveryTime: pendingFilters.deliveryTime == DeliveryTimeOption.under30 ? null : DeliveryTimeOption.under30,
                              clearDeliveryTime: pendingFilters.deliveryTime == DeliveryTimeOption.under30));
                        }),
                        const SizedBox(width: 8),
                        _buildFilterChip(label: '30-45 mins', isSelected: pendingFilters.deliveryTime == DeliveryTimeOption.thirtyTo45, onTap: () {
                          setSheetState(() => pendingFilters = pendingFilters.copyWith(
                              deliveryTime: pendingFilters.deliveryTime == DeliveryTimeOption.thirtyTo45 ? null : DeliveryTimeOption.thirtyTo45,
                              clearDeliveryTime: pendingFilters.deliveryTime == DeliveryTimeOption.thirtyTo45));
                        }),
                        const SizedBox(width: 8),
                        _buildFilterChip(label: '45+ mins', isSelected: pendingFilters.deliveryTime == DeliveryTimeOption.over45, onTap: () {
                          setSheetState(() => pendingFilters = pendingFilters.copyWith(
                              deliveryTime: pendingFilters.deliveryTime == DeliveryTimeOption.over45 ? null : DeliveryTimeOption.over45,
                              clearDeliveryTime: pendingFilters.deliveryTime == DeliveryTimeOption.over45));
                        }),
                      ])),
                      const SizedBox(height: 23),
                      GestureDetector(
                        onTap: () {
                          setState(() => _filters = pendingFilters);
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: double.infinity, height: 52,
                          decoration: ShapeDecoration(color: const Color(0xFFF5222D), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: const Center(child: Text('Apply Filters', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterSection({required String title, required Widget child}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: double.infinity, child: Text(title, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600))),
      const SizedBox(height: 12),
      child,
    ]);
  }

  Widget _buildFilterChip({required String label, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9.5),
        decoration: ShapeDecoration(
          color: isSelected ? const Color(0xFFF5222D) : const Color(0xFFF5F5F5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF333333), fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildInteractiveStarRating({required double rating, required ValueChanged<double> onChanged}) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (index) {
      final starNumber = index + 1;
      final isFull = rating >= starNumber;
      final isHalf = !isFull && rating >= starNumber - 0.5;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: GestureDetector(
          onTapDown: (details) {
            final isLeftHalf = details.localPosition.dx < 14;
            onChanged(isLeftHalf ? starNumber - 0.5 : starNumber.toDouble());
          },
          child: SizedBox(width: 28, height: 28,
              child: Icon(isFull ? Icons.star : isHalf ? Icons.star_half : Icons.star_border, size: 28,
                  color: (isFull || isHalf) ? const Color(0xFFFFC107) : const Color(0xFFD9D9D9))),
        ),
      );
    }));
  }
}
