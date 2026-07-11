import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

/// Screen that lists all problem reports from customers for the owner's restaurant.
/// The owner can view and manage these reports.
class OwnerReportsScreen extends StatefulWidget {
  const OwnerReportsScreen({super.key});

  @override
  State<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends State<OwnerReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _fetchReports() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoading = true);

    try {
      final api = di.sl<ApiService>();
      final reports = await api.getRestaurantProblems(token: token);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load reports.';
        _isLoading = false;
      });
    }
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(dateTime);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text('Customer Reports',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
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
            Text('Loading reports...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Color(0xFF8E8E93))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchReports,
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
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, size: 48, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No customer reports yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Customer issues will appear here',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchReports,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _reports.length,
        itemBuilder: (context, index) => _buildReportCard(_reports[index]),
      ),
    );
  }

  Future<void> _updateProblemStatus({
    required String problemId,
    required String status,
    String? adminNote,
    double? refundAmount,
  }) async {
    final token = _token;
    if (token == null) return;

    // Optimistic update
    _updateReportInPlace(problemId, status, adminNote: adminNote, refundAmount: refundAmount);

    try {
      final api = di.sl<ApiService>();
      await api.updateProblemStatus(
        problemId: problemId,
        status: status,
        adminNote: adminNote,
        refundAmount: refundAmount,
        token: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report ${status == 'APPROVED' ? 'approved' : 'rejected'}.'),
          backgroundColor: status == 'APPROVED'
              ? const Color(0xFF1E8E3E)
              : const Color(0xFFBB0018),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      // Revert on failure
      if (!mounted) return;
      _fetchReports();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
    } catch (_) {
      if (!mounted) return;
      _fetchReports();
    }
  }

  void _updateReportInPlace(
    String problemId,
    String newStatus, {
    String? adminNote,
    double? refundAmount,
  }) {
    final idx = _reports.indexWhere((r) => r['id']?.toString() == problemId);
    if (idx == -1) return;
    _reports[idx] = {
      ..._reports[idx],
      'status': newStatus,
      if (adminNote != null) 'admin_note': adminNote,
      if (refundAmount != null) 'refund_amount': refundAmount,
      'updated_at': DateTime.now().toIso8601String(),
    };
    setState(() {});
  }

  Future<void> _showApproveDialog(String problemId) async {
    final noteCtrl = TextEditingController();
    final refundCtrl = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF1E8E3E), size: 24),
            SizedBox(width: 10),
            Text('Approve Report',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This will mark the report as approved.',
                style: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C))),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Admin Note (optional)',
                labelStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                hintText: 'Add a note for the customer...',
                hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1E8E3E)),
                ),
                contentPadding: const EdgeInsets.all(12),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refundCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Refund Amount (optional)',
                labelStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                hintText: 'e.g. 500',
                hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                prefixText: 'Rs. ',
                prefixStyle: const TextStyle(color: Color(0xFF1A1C1C), fontSize: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1E8E3E)),
                ),
                contentPadding: const EdgeInsets.all(12),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF8E8E93))),
          ),
          ElevatedButton(
            onPressed: () {
              final double? refund = double.tryParse(refundCtrl.text.trim());
              Navigator.pop(ctx, {
                'note': noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                'refund': refund,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E8E3E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Approve',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    noteCtrl.dispose();
    refundCtrl.dispose();

    if (result == null) return;
    await _updateProblemStatus(
      problemId: problemId,
      status: 'APPROVED',
      adminNote: result['note'] as String?,
      refundAmount: result['refund'] as double?,
    );
  }

  Future<void> _showRejectDialog(String problemId) async {
    final noteCtrl = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Color(0xFFBB0018), size: 24),
            SizedBox(width: 10),
            Text('Reject Report',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This will mark the report as rejected.',
                style: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C))),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Reason for rejection',
                labelStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                hintText: 'Explain to the customer why...',
                hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFBB0018)),
                ),
                contentPadding: const EdgeInsets.all(12),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF8E8E93))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBB0018),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Reject',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    noteCtrl.dispose();

    if (result == null) return;
    await _updateProblemStatus(
      problemId: problemId,
      status: 'REJECTED',
      adminNote: result,
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = report['status'] as String? ?? 'PENDING';
    final issueType = report['issue_type'] as String? ?? '';
    final description = report['description'] as String? ?? '';
    final customerName = report['customer_name'] as String? ?? 'Unknown';
    final createdAt = report['created_at'] as String? ?? '';
    final reportId = report['id'] as String? ?? '';
    final adminNote = report['admin_note'] as String?;

    final typeLabels = {
      'wrong_item': 'Wrong Item',
      'missing_item': 'Missing Item',
      'quality': 'Food Quality',
      'other': 'Other Issue',
    };
    final typeIcons = {
      'wrong_item': Icons.fastfood_outlined,
      'missing_item': Icons.inventory_2_outlined,
      'quality': Icons.thumb_down_outlined,
      'other': Icons.more_horiz,
    };

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    Color bgColor;

    switch (status) {
      case 'APPROVED':
        statusColor = const Color(0xFF1E8E3E);
        statusLabel = 'Approved';
        statusIcon = Icons.check_circle;
        bgColor = const Color(0xFFE6F4EA);
      case 'REJECTED':
        statusColor = const Color(0xFFBB0018);
        statusLabel = 'Rejected';
        statusIcon = Icons.cancel_rounded;
        bgColor = const Color(0xFFFFF1F0);
      default:
        statusColor = const Color(0xFFF9A825);
        statusLabel = 'Pending';
        statusIcon = Icons.hourglass_empty_rounded;
        bgColor = const Color(0xFFFFF8E1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: status == 'PENDING'
            ? Border.all(color: const Color(0xFFF9A825).withValues(alpha: 0.3))
            : null,
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  typeIcons[issueType] ?? Icons.flag_outlined,
                  size: 22,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          typeLabels[issueType] ?? issueType,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1C1C)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(statusLabel,
                                  style: TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w700,
                                      color: statusColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 13, color: Color(0xFF8E8E93)),
                        const SizedBox(width: 3),
                        Text(customerName,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500)),
                        if (createdAt.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(_timeAgo(createdAt),
                              style: const TextStyle(fontSize: 11, color: Color(0xFFBFBFBF))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Description
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(description,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF5C5C5C), height: 1.4)),
            ),
          ],

          // Admin note (shown when present)
          if (adminNote != null && adminNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chat_outlined, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(adminNote,
                        style: TextStyle(
                            fontSize: 12, color: statusColor, height: 1.4)),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons for pending reports
          if (status == 'PENDING') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _showRejectDialog(reportId),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Reject',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFBB0018),
                        side: const BorderSide(color: Color(0xFFFFCDD2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _showApproveDialog(reportId),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Approve',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E3E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
