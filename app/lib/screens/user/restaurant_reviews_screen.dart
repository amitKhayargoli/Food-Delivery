import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../models/models.dart';
import 'write_review_screen.dart';

class RestaurantReviewsScreen extends StatefulWidget {
  final Restaurant restaurant;

  const RestaurantReviewsScreen({super.key, required this.restaurant});

  @override
  State<RestaurantReviewsScreen> createState() =>
      _RestaurantReviewsScreenState();
}

class _RestaurantReviewsScreenState extends State<RestaurantReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final reviews = await api.getRestaurantReviews(
        restaurantId: widget.restaurant.id,
      );
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load reviews.';
          _isLoading = false;
        });
      }
    }
  }

  /// Calculate rating distribution from reviews
  Map<int, int> _ratingDistribution() {
    final dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in _reviews) {
      final rating = (r['rating'] as num?)?.toInt() ?? 0;
      if (dist.containsKey(rating)) dist[rating] = dist[rating]! + 1;
    }
    return dist;
  }

  double _averageRating() {
    if (_reviews.isEmpty) return 0;
    final sum =
        _reviews.fold<double>(0, (s, r) => s + ((r['rating'] as num?)?.toDouble() ?? 0));
    return (sum / _reviews.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text('Reviews',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 24),
            onPressed: () => _navigateToWriteReview(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _fetchReviews,
                  color: const Color(0xFFBB0018),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        _buildRatingSummary(),
                        _buildReviewsList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchReviews,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSummary() {
    final avgRating = _averageRating();
    final distribution = _ratingDistribution();
    final totalReviews = _reviews.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Average rating (big number)
          Column(
            children: [
              Text(
                avgRating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    i < avgRating.round()
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 16,
                    color: const Color(0xFFF9A825),
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalReviews review${totalReviews == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Distribution bars
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final count = distribution[star] ?? 0;
                final pct = totalReviews > 0 ? count / totalReviews : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$star',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8E8E93),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.star_rounded,
                          size: 14, color: Color(0xFFF9A825)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFF0F0F0),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFF9A825)),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$count',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsList() {
    if (_reviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.rate_review_outlined,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('No reviews yet',
                  style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF8E8E93),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text('Be the first to review!',
                  style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _reviews.length,
      itemBuilder: (context, index) {
        return _buildReviewCard(_reviews[index]);
      },
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment'] as String?;
    final createdAt = review['created_at'] as String? ?? '';
    final imagesRaw = review['images'];
    final List<String> images = imagesRaw is List
        ? imagesRaw.whereType<String>().toList()
        : [];
    final user = review['users'] as Map<String, dynamic>? ?? {};
    final userName = user['username'] as String? ?? 'Anonymous';
    final userAvatar = user['avatar_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info + rating
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFFF1F0),
                backgroundImage: userAvatar != null && userAvatar.isNotEmpty
                    ? NetworkImage(userAvatar)
                    : null,
                child: userAvatar == null || userAvatar.isEmpty
                    ? const Icon(Icons.person, size: 18, color: Color(0xFFBB0018))
                    : null,
              ),
              const SizedBox(width: 10),
              // Name + date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    Text(
                      _formatDate(createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              // Star rating
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 16,
                    color: const Color(0xFFF9A825),
                  );
                }),
              ),
            ],
          ),

          // Comment
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF595959),
                height: 1.5,
              ),
            ),
          ],

          // Images
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: () => _showImagePreview(images[i]),
                      child: Image.network(
                        images[i],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 80,
                          height: 80,
                          color: const Color(0xFFF0F0F0),
                          child: const Icon(Icons.broken_image,
                              color: Color(0xFFBFBFBF)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToWriteReview() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => WriteReviewScreen(restaurant: widget.restaurant),
      ),
    );
    if (result == true) {
      _fetchReviews();
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
