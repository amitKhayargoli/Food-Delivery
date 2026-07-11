import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

class OwnerReviewsScreen extends StatefulWidget {
  const OwnerReviewsScreen({super.key});

  @override
  State<OwnerReviewsScreen> createState() => _OwnerReviewsScreenState();
}

class _OwnerReviewsScreenState extends State<OwnerReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  String? _restaurantName;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    setState(() { _isLoading = true; _error = null; });

    try {
      final api = di.sl<ApiService>();
      final result = await api.getOwnerRestaurantReviews(token: token);
      if (mounted) {
        setState(() {
          _restaurantName = result['restaurant_name'] as String?;
          _reviews = (result['reviews'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ?? [];
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'Failed to load reviews.'; _isLoading = false; });
      }
    }
  }

  double _averageRating() {
    if (_reviews.isEmpty) return 0;
    final sum = _reviews.fold<num>(0, (s, r) => s + ((r['rating'] as num?)?.toInt() ?? 0));
    return (sum / _reviews.length).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: Text(
          _restaurantName != null ? '$_restaurantName Reviews' : 'Reviews',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _fetchReviews,
                  color: const Color(0xFFBB0018),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildStatsHeader(),
                      ..._reviews.map((r) => _buildReviewCard(r)),
                      if (_reviews.isEmpty) _buildEmptyState(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatsHeader() {
    final avg = _averageRating();
    final total = _reviews.length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0C000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) => Icon(
                  i < avg.round() ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16, color: const Color(0xFFF9A825),
                )),
              ),
              const SizedBox(height: 4),
              Text('$total review${total == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final count = _reviews.where((r) => (r['rating'] as num?)?.toInt() == star).length;
                final pct = total > 0 ? count / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 24,
                          child: Text('$star', style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)))),
                      const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF9A825)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct, minHeight: 5,
                            backgroundColor: const Color(0xFFF0F0F0),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF9A825)),
                          ),
                        ),
                      ),
                      SizedBox(width: 20,
                          child: Text('$count', textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)))),
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

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment'] as String?;
    final createdAt = review['created_at'] as String? ?? '';
    final imagesRaw = review['images'];
    final List<String> images = imagesRaw is List ? imagesRaw.whereType<String>().toList() : [];
    final user = review['users'] as Map<String, dynamic>? ?? {};
    final userName = user['username'] as String? ?? 'Anonymous';
    final userAvatar = user['avatar_url'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFFFF1F0),
                backgroundImage: userAvatar != null && userAvatar.isNotEmpty
                    ? NetworkImage(userAvatar) : null,
                child: userAvatar == null || userAvatar.isEmpty
                    ? const Icon(Icons.person, size: 16, color: Color(0xFFBB0018)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(_formatDate(createdAt),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                  ],
                ),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => Icon(
                i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                size: 14, color: const Color(0xFFF9A825),
              ))),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comment, style: const TextStyle(fontSize: 14, color: Color(0xFF595959), height: 1.4)),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(images[i], width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(width: 72, height: 72,
                        color: const Color(0xFFF0F0F0),
                        child: const Icon(Icons.broken_image, color: Color(0xFFBFBFBF))),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No reviews yet', style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93))),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return ''; }
  }
}
