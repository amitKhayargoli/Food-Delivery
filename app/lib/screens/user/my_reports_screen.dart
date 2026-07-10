import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

/// Screen that lists all problem reports submitted by the authenticated user.
/// Fetches from GET /api/problems/my and shows each report with its status,
/// issue type, order number, and description.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
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
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Not authenticated.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final reports = await api.getMyProblems(token: token);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text('My Reports',
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
            Text('Loading your reports...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
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
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
              const SizedBox(height: 24),
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
            const Text('No reports yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Report a problem from an order detail screen',
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

  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = report['status'] as String? ?? 'PENDING';
    final issueType = report['issue_type'] as String? ?? '';
    final description = report['description'] as String?;
    final orderNumber = report['order_number'] as String? ?? '';
    final adminNote = report['admin_note'] as String?;
    final createdAt = report['created_at'] as String? ?? '';

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
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('Order #$orderNumber',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF1967D2),
                                fontWeight: FontWeight.w500)),
                        if (createdAt.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(_timeAgo(createdAt),
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF8E8E93))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Description
          if (description != null && description.isNotEmpty) ...[
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

          // Admin note
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
        ],
      ),
    );
  }

  String _timeAgo(String isoDate) {
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
}
