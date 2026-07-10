import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'support_chat_screen.dart';

/// Screen listing the user's support conversations, with ability to start a new one.
class SupportConversationListScreen extends StatefulWidget {
  final String? orderId;
  final String? orderNumber;

  const SupportConversationListScreen({
    super.key,
    this.orderId,
    this.orderNumber,
  });

  @override
  State<SupportConversationListScreen> createState() => _SupportConversationListScreenState();
}

class _SupportConversationListScreenState extends State<SupportConversationListScreen> {
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
      final conversations = await api.getMySupportConversations(token: token);
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

  Future<void> _startNewConversation() async {
    final subjectCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.headset_mic_rounded, color: Color(0xFFBB0018), size: 24),
            SizedBox(width: 10),
            Text('Contact Support',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tell us what you need help with:',
                style: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C))),
            const SizedBox(height: 12),
            if (widget.orderNumber != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 16, color: Color(0xFF8E8E93)),
                    const SizedBox(width: 6),
                    Text('Order #${widget.orderNumber}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF5C5C5C))),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: subjectCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Wrong item in my order',
                hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFBB0018)),
                ),
                contentPadding: const EdgeInsets.all(14),
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
            onPressed: subjectCtrl.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, subjectCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBB0018),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Submit',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    subjectCtrl.dispose();

    if (result == null || result.isEmpty) return;

    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final conv = await api.createSupportConversation(
        subject: result,
        orderId: widget.orderId,
        token: token,
      );
      if (!mounted) return;
      final convId = conv['id'] as String?;
      if (convId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupportChatScreen(
              conversationId: convId,
              subject: result,
            ),
          ),
        );
        _fetchConversations();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _closeConversation(String convId) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.closeSupportConversation(
        conversationId: convId,
        token: token,
      );
      if (!mounted) return;
      _fetchConversations();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation closed.'),
          backgroundColor: Color(0xFF1E8E3E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  String _timeAgo(String? dt) {
    if (dt == null) return '';
    final dateTime = DateTime.tryParse(dt);
    if (dateTime == null) return '';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return dateTime.toString().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text('Support',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        actions: [
          IconButton(
            onPressed: _startNewConversation,
            icon: const Icon(Icons.add_rounded, size: 24),
            tooltip: 'New conversation',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewConversation,
        backgroundColor: const Color(0xFFBB0018),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.headset_mic_rounded, size: 20),
        label: const Text('Contact Support',
            style: TextStyle(fontWeight: FontWeight.w600)),
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
            const Text('No conversations yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Tap the button below to contact support',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchConversations,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: _conversations.length,
        itemBuilder: (context, index) => _buildConversationCard(_conversations[index]),
      ),
    );
  }

  Widget _buildConversationCard(Map<String, dynamic> conv) {
    final status = conv['status'] as String? ?? 'OPEN';
    final subject = conv['subject'] as String? ?? '';
    final lastMsg = conv['last_message'] as Map<String, dynamic>?;
    final unread = (conv['unread_count'] as num?)?.toInt() ?? 0;
    final isOpen = status == 'OPEN';
    final convId = conv['id'] as String? ?? '';

    final card = GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupportChatScreen(
              conversationId: convId,
              subject: subject,
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
                color: isOpen ? Colors.white : const Color(0xFFF5F5F5),
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
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFBB0018),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('$unread',
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (lastMsg != null)
                    Text(lastMsg['message'] as String? ?? '',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOpen ? Colors.white : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(isOpen ? 'Open' : 'Closed',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: isOpen ? const Color(0xFFBB0018) : const Color(0xFF8E8E93))),
                      ),
                      const SizedBox(width: 8),
                      Text(_timeAgo(conv['updated_at'] as String?),
                          style: const TextStyle(fontSize: 11, color: Color(0xFFBFBFBF))),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBFBFBF)),
          ],
        ),
      ),
    );

    // Swipe-to-close for open conversations
    if (!isOpen) return card;

    return Dismissible(
      key: Key('close-conv-$convId'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Close this conversation?',
                style: TextStyle(fontWeight: FontWeight.w700)),
            content: Text(
              'Are you sure you want to close "$subject"?',
              style: const TextStyle(fontSize: 14, color: Color(0xFF5C5C5C)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF8E8E93))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: const Text('Close',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) => _closeConversation(convId),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFBB0018),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text('Close',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ],
        ),
      ),
      child: card,
    );
  }
}
