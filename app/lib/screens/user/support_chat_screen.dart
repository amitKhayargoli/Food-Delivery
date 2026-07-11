import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, RealtimeChannel;
import '../../core/services/api_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

/// Screen that shows messages for a support conversation with realtime updates.
class SupportChatScreen extends StatefulWidget {
  final String conversationId;
  final String subject;
  final bool isAdmin;

  const SupportChatScreen({
    super.key,
    required this.conversationId,
    required this.subject,
    this.isAdmin = false,
  });

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  RealtimeChannel? _realtimeChannel;
  bool _isClosed = false;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  /// Subscribe to new messages via Supabase Realtime.
  void _subscribeToRealtime() {
    try {
      _realtimeChannel = SupabaseClientService.client.channel(
        'support-chat-${widget.conversationId}',
      );

      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'support_messages',
        callback: (payload) {
          final newMsg = payload.newRecord;
          if (newMsg['conversation_id']?.toString() != widget.conversationId) return;

          // Avoid duplicating the user's own just-sent message
          if (_messages.any((m) => m['id']?.toString() == newMsg['id']?.toString())) return;

          if (mounted) {
            setState(() {
              _messages.add(newMsg);
            });
            _scrollToBottom();
          }
        },
      );

      _realtimeChannel!.subscribe((status, [error]) {
        debugPrint('[SupportRT] Channel status: $status for conv ${widget.conversationId}');
        if (error != null) debugPrint('[SupportRT] Error: $error');
      });
    } catch (e) {
      debugPrint('[SupportRT] Setup error: $e');
    }
  }

  Future<void> _fetchMessages() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoading = true);

    try {
      final api = di.sl<ApiService>();
      final messages = await api.getSupportMessages(
        conversationId: widget.conversationId,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load messages.';
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } catch (_) {
        // Silently handle edge case where controller is disposed
        // during the post-frame callback.
      }
    });
  }

  Future<void> _sendMessage() async {
    // Guard against rapid double-taps (onSubmitted + button press)
    if (_isSending) return;

    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    final token = _token;
    if (token == null) return;

    setState(() => _isSending = true);
    _messageCtrl.clear();

    try {
      final api = di.sl<ApiService>();
      await api.sendSupportMessage(
        conversationId: widget.conversationId,
        message: text,
        token: token,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message.'),
            backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSending = false);
  }

  Future<void> _closeConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Close Conversation',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
          'Are you sure you want to close this conversation?\n\n'
          'Both you and the other party will no longer be able to send messages.',
          style: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C)),
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

    if (confirmed != true) return;

    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.closeSupportConversation(
        conversationId: widget.conversationId,
        token: token,
      );
      if (!mounted) return;
      setState(() => _isClosed = true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Support Chat',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                if (_isClosed) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Closed',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: Color(0xFF8E8E93))),
                  ),
                ],
              ],
            ),
            Text(widget.subject,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (!_isClosed)
            IconButton(
              onPressed: _closeConversation,
              icon: Icon(
                widget.isAdmin ? Icons.check_circle_outline : Icons.close_rounded,
                size: 22,
              ),
              tooltip: 'Close conversation',
            ),
        ],
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // Messages
          Expanded(child: _buildMessagesList()),
          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading messages...',
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
              onPressed: _fetchMessages,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No messages yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Send a message to start the conversation',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchMessages,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: _messages.length,
        itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isAdmin = msg['sender_role'] == 'ADMIN';
    final message = msg['message'] as String? ?? '';
    final createdAt = msg['created_at'] as String? ?? '';
    final time = createdAt.length >= 16
        ? createdAt.substring(11, 16)
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(Icons.support_agent, size: 16, color: Color(0xFFBB0018)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isAdmin ? Colors.white : const Color(0xFFBB0018),
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: isAdmin ? Radius.zero : const Radius.circular(16),
                  bottomRight: isAdmin ? const Radius.circular(16) : Radius.zero,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  if (isAdmin)
                    const Text('Support',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: Color(0xFFBB0018))),
                  const SizedBox(height: 2),
                  Text(message,
                      style: TextStyle(
                          fontSize: 14,
                          color: isAdmin ? const Color(0xFF1A1C1C) : Colors.white),
                      maxLines: 20,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(time,
                      style: TextStyle(
                          fontSize: 10,
                          color: isAdmin ? const Color(0xFFBFBFBF) : Colors.white70)),
                ],
              ),
            ),
          ),
          if (!isAdmin) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    if (_isClosed) {
      return Container(
        padding: EdgeInsets.only(
          left: 12, right: 8, top: 12, bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 14, color: Color(0xFF8E8E93)),
            const SizedBox(width: 6),
            const Text('This conversation is closed',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _messageCtrl,
                enabled: !_isSending,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: const TextStyle(color: Color(0xFFBFBFBF)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFBB0018)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: ElevatedButton(
              onPressed: _messageCtrl.text.trim().isEmpty || _isSending ? null : _sendMessage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBB0018),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFEFEDED),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                elevation: 0,
              ),
              child: _isSending
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
