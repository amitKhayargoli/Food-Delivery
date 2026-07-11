import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../../models/models.dart';

class WriteReviewScreen extends StatefulWidget {
  final Restaurant restaurant;

  const WriteReviewScreen({super.key, required this.restaurant});

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  int _rating = 0;
  final TextEditingController _commentCtrl = TextEditingController();
  List<String> _uploadedImageUrls = [];
  bool _isUploading = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final token = context.read<AuthProvider>().token;
      if (token == null) return;

      final storage = di.sl<StorageService>();
      final url = await storage.uploadReviewImage(
        filePath: pickedFile.path,
        token: token,
      );

      if (mounted) {
        setState(() => _uploadedImageUrls.add(url));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _removeImage(int index) {
    setState(() => _uploadedImageUrls.removeAt(index));
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }

    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    setState(() => _isSubmitting = true);

    try {
      final api = di.sl<ApiService>();
      await api.submitRestaurantReview(
        restaurantId: widget.restaurant.id,
        rating: _rating,
        comment: _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
        images: _uploadedImageUrls.isNotEmpty ? _uploadedImageUrls : null,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Review submitted!'),
              ],
            ),
            backgroundColor: Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.maybePop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Write a Review',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submitReview,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFBB0018))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Restaurant name
            Text(
              widget.restaurant.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1C1C),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── Star Rating ──
            const Text(
              'Tap a star to rate',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8E8E93),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starNum = index + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = starNum),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedScale(
                      scale: starNum == _rating ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        starNum <= _rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 48,
                        color: starNum <= _rating
                            ? const Color(0xFFF9A825)
                            : const Color(0xFFD9D9D9),
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (_rating > 0) ...[
              const SizedBox(height: 8),
              Text(
                _ratingLabel(_rating),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF9A825),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // ── Comment ──
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your review',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Share your experience... What did you like?',
                hintStyle:
                    TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFBB0018)),
                ),
                filled: true,
                fillColor: const Color(0xFFFAF9F9),
                contentPadding: const EdgeInsets.all(16),
                counterStyle: TextStyle(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 24),

            // ── Photo Upload ──
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add photos (optional)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _uploadedImageUrls.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (index == _uploadedImageUrls.length) {
                    // Add photo button
                    return GestureDetector(
                      onTap: _isUploading ? null : _pickAndUploadImage,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF9F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                            width: 1.5,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                        ),
                        child: _isUploading
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_rounded,
                                      size: 28, color: Color(0xFF8E8E93)),
                                  SizedBox(height: 4),
                                  Text('Add',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF8E8E93))),
                                ],
                              ),
                      ),
                    );
                  }

                  // Uploaded image
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _uploadedImageUrls[index],
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 96,
                            height: 96,
                            color: const Color(0xFFF0F0F0),
                            child: const Icon(Icons.broken_image,
                                color: Color(0xFFBFBFBF)),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(index),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 32),

            // ── Submit Button ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _rating == 0 || _isSubmitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFEFEDED),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Review',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }
}
