import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

/// Screen for customers to report a problem with their order.
class ReportProblemScreen extends StatefulWidget {
  final String orderId;
  final String orderNumber;

  const ReportProblemScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  String? _selectedType;
  final _descCtrl = TextEditingController();
  bool _isSubmitting = false;

  static const _issueTypes = [
    ('wrong_item', 'Wrong Item', Icons.fastfood_outlined, 'Received an item I didn\'t order'),
    ('missing_item', 'Missing Item', Icons.inventory_2_outlined, 'An item was missing from my order'),
    ('quality', 'Food Quality', Icons.thumb_down_outlined, 'Food quality was poor or undercooked'),
    ('other', 'Other Issue', Icons.more_horiz, 'Something else'),
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _submit() async {
    if (_selectedType == null) return;

    final token = _token;
    if (token == null) return;

    setState(() => _isSubmitting = true);

    try {
      final api = di.sl<ApiService>();
      await api.submitProblem(
        orderId: widget.orderId,
        issueType: _selectedType!,
        description: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
        token: token,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Problem reported. We\'ll review it shortly.')),
            ],
          ),
          backgroundColor: Color(0xFF1E8E3E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text('Report a Problem',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded,
                      size: 20, color: Color(0xFFBB0018)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Order',
                          style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                      const Text('Order',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1C1C))),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Text('What went wrong?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C))),
            const SizedBox(height: 4),
            const Text('Select the issue that best describes your problem',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
            const SizedBox(height: 12),

            // Issue type cards
            ..._issueTypes.map((type) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => setState(() => _selectedType = type.$1),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _selectedType == type.$1
                        ? const Color(0xFFFFF1F0)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedType == type.$1
                          ? const Color(0xFFBB0018)
                          : const Color(0xFFE5E7EB),
                      width: _selectedType == type.$1 ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(type.$3,
                          size: 24,
                          color: _selectedType == type.$1
                              ? const Color(0xFFBB0018)
                              : const Color(0xFF8E8E93)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.$2,
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600,
                                    color: _selectedType == type.$1
                                        ? const Color(0xFFBB0018)
                                        : const Color(0xFF1A1C1C))),
                            const SizedBox(height: 2),
                            Text(type.$4,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF8E8E93))),
                          ],
                        ),
                      ),
                      if (_selectedType == type.$1)
                        const Icon(Icons.check_circle,
                            size: 20, color: Color(0xFFBB0018)),
                    ],
                  ),
                ),
              ),
            )),

            const SizedBox(height: 20),

            // Description
            const Text('Tell us more (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C))),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Describe what happened in detail...',
                hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFBB0018), width: 1.5),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(14),
              ),
              style: const TextStyle(fontSize: 14),
            ),

            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _selectedType == null || _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isSubmitting ? 'Submitting...' : 'Submit Report',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFEFEDED),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFFF9A825)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your report will be reviewed by the restaurant owner. '
                      'You\'ll be notified when it\'s approved or rejected.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF795548), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
