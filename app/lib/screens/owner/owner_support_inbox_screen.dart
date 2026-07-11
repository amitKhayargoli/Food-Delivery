import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../user/support_chat_screen.dart';

/// Screen listing all support conversations from customers for the owner's restaurant.
/// The owner can view and respond to customer inquiries here.
class OwnerSupportInboxScreen extends StatefulWidget {
  const OwnerSupportInboxScreen({super.key});

  @override
  State<OwnerSupportInboxScreen> createState() => _OwnerSupportInboxScreenState();
}

class _OwnerSupportInboxScreenState extends State<OwnerSupportInboxScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchConversations();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _fetchConversations() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoading = true);

    try {
      final api = di.sl<ApiService>();
      final conversations = await api.getAllSupportConversations(token: token);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load conversations.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text('Customer Support',
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
            Text('Loading conversations...',
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
              onPressed: _fetchConversations,
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

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headset_mic_rounded,
                size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No customer conversations yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Customer inquiries will appear here',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    final openFirst = List<Map<String, dynamic>>.from(_conversations)
      ..sort((a, b) {
        final aOpen = a['status'] == 'OPEN' ? 0 : 1;
        final bOpen = b['status'] == 'OPEN' ? 0 : 1;
        if (aOpen != bOpen) return aOpen.compareTo(bOpen);
        return (b['updated_at'] as String? ?? '').compareTo(a['updated_at'] as String? ?? '');
      });

    return RefreshIndicator(
      onRefresh: _fetchConversations,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: openFirst.length,
        itemBuilder: (context, index) => _buildConversationCard(openFirst[index]),
      ),
    );
  }

  Widget _buildConversationCard(Map<String, dynamic> conv) {
    final status = conv['status'] as String? ?? 'OPEN';
    final subject = conv['subject'] as String? ?? '';
    final lastMsg = conv['last_message'] as Map<String, dynamic>?;
    final msgCount = (conv['message_count'] as num?)?.toInt() ?? 0;
    final userInfo = conv['user'] as Map<String, dynamic>?;
    final userName = userInfo?['username'] as String? ?? 'Unknown';
    final isOpen = status == 'OPEN';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupportChatScreen(
              conversationId: conv['id'] as String? ?? '',
              subject: subject,
              isAdmin: true,
            ),
          ),
        ).then((_) => _fetchConversations());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isOpen
              ? Border.all(color: const Color(0xFFBB0018).withValues(alpha: 0.2))
              : null,
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 3),
          )],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isOpen ? const Color(0xFFFFF1F0) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isOpen ? Icons.chat_rounded : Icons.check_circle_outlined,
                color: isOpen ? const Color(0xFFBB0018) : const Color(0xFF8E8E93),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(subject,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1C1C)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOpen ? const Color(0xFFFFF1F0) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(isOpen ? 'Open' : 'Closed',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: isOpen ? const Color(0xFFBB0018) : const Color(0xFF8E8E93))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 13, color: Color(0xFF8E8E93)),
                      const SizedBox(width: 4),
                      Text(userName,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                      const SizedBox(width: 12),
                      const Icon(Icons.chat_bubble_outline, size: 12, color: Color(0xFFBFBFBF)),
                      const SizedBox(width: 3),
                      Text('$msgCount msgs',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFBFBFBF))),
                    ],
                  ),
                  if (lastMsg != null) ...[
                    const SizedBox(height: 4),
                    Text(lastMsg['message'] as String? ?? '',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF5C5C5C)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBFBFBF)),
          ],
        ),
      ),
    );
  }
}
