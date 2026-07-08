import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';
import { notifyUser } from '../services/fcm.service';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

function getUserRole(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  try {
    const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as { id: string; role: string };
    return payload.role;
  } catch {
    return null;
  }
}

// ──────────────────────────────────────────────
// POST /api/support/conversations
// Create a new support conversation (customer)
// ──────────────────────────────────────────────
export const createConversation = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { subject, order_id } = req.body;

    if (!subject || subject.trim().length === 0) {
      res.status(400).json({ error: 'Subject is required.' });
      return;
    }

    const { data: conversation, error } = await supabase.admin
      .from('support_conversations')
      .insert({
        user_id: userId,
        order_id: order_id || null,
        subject: subject.trim(),
        status: 'OPEN',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error) {
      console.error('Create conversation error:', error);
      res.status(500).json({ error: 'Failed to create conversation.' });
      return;
    }

    // Notify admin users about the new conversation
    const { data: admins } = await supabase.admin
      .from('users')
      .select('id')
      .eq('role', 'ADMIN');

    if (admins) {
      for (const admin of admins) {
        notifyUser(admin.id, supabase.admin, {
          title: 'New Support Request 📩',
          body: `New conversation: ${subject}`,
          data: { type: 'support_new', conversation_id: conversation.id },
        }).catch(() => {});
      }
    }

    res.status(201).json({
      message: 'Conversation created.',
      conversation,
    });
  } catch (error) {
    console.error('Create conversation error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/support/conversations
// Get conversations for the authenticated user
// ──────────────────────────────────────────────
export const getMyConversations = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: conversations, error } = await supabase.admin
      .from('support_conversations')
      .select('*')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false });

    if (error) {
      console.error('Fetch conversations error:', error);
      res.status(500).json({ error: 'Failed to fetch conversations.' });
      return;
    }

    // Fetch last message and unread count for each conversation
    const conversationsWithMeta = await Promise.all(
      (conversations || []).map(async (conv: any) => {
        const { data: lastMsg } = await supabase.admin
          .from('support_messages')
          .select('*')
          .eq('conversation_id', conv.id)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        const { count: unreadCount } = await supabase.admin
          .from('support_messages')
          .select('*', { count: 'exact', head: true })
          .eq('conversation_id', conv.id)
          .eq('sender_role', 'ADMIN')
          .eq('is_read', false);

        return {
          ...conv,
          last_message: lastMsg || null,
          unread_count: unreadCount || 0,
        };
      }),
    );

    res.status(200).json({ conversations: conversationsWithMeta });
  } catch (error) {
    console.error('Get conversations error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/support/conversations/admin/all
// Get all conversations (admin only)
// ──────────────────────────────────────────────
export const getAllConversations = async (req: Request, res: Response): Promise<void> => {
  try {
    const role = getUserRole(req);
    if (role !== 'ADMIN') {
      res.status(403).json({ error: 'Admin access required.' });
      return;
    }

    const status = req.query.status as string | undefined;

    let query = supabase.admin
      .from('support_conversations')
      .select('*')
      .order('updated_at', { ascending: false });

    if (status === 'OPEN' || status === 'CLOSED') {
      query = query.eq('status', status);
    }

    const { data: conversations, error } = await query;

    if (error) {
      console.error('Fetch all conversations error:', error);
      res.status(500).json({ error: 'Failed to fetch conversations.' });
      return;
    }

    // Fetch user info for each conversation
    const userIds = [...new Set((conversations || []).map((c: any) => c.user_id))];
    const { data: users } = await supabase.admin
      .from('users')
      .select('id, username, avatar_url')
      .in('id', userIds);

    const userMap = new Map<string, any>();
    for (const u of users || []) {
      userMap.set(u.id, u);
    }

    // Fetch last message for each conversation
    const conversationsWithMeta = await Promise.all(
      (conversations || []).map(async (conv: any) => {
        const { data: lastMsg } = await supabase.admin
          .from('support_messages')
          .select('*')
          .eq('conversation_id', conv.id)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        const { count: msgCount } = await supabase.admin
          .from('support_messages')
          .select('*', { count: 'exact', head: true })
          .eq('conversation_id', conv.id);

        const userInfo = userMap.get(conv.user_id);

        return {
          ...conv,
          last_message: lastMsg || null,
          message_count: msgCount || 0,
          user: userInfo
            ? {
                id: userInfo.id,
                username: userInfo.username || 'Unknown',
                avatar_url: userInfo.avatar_url,
              }
            : null,
        };
      }),
    );

    res.status(200).json({ conversations: conversationsWithMeta });
  } catch (error) {
    console.error('Get all conversations error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/support/conversations/:id/messages
// Get messages for a conversation
// ──────────────────────────────────────────────
export const getMessages = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    // Verify the user owns this conversation or is admin
    const role = getUserRole(req);
    const { data: conversation } = await supabase.admin
      .from('support_conversations')
      .select('user_id')
      .eq('id', id)
      .maybeSingle();

    if (!conversation) {
      res.status(404).json({ error: 'Conversation not found.' });
      return;
    }

    if (conversation.user_id !== userId && role !== 'ADMIN') {
      res.status(403).json({ error: 'Access denied.' });
      return;
    }

    const { data: messages, error } = await supabase.admin
      .from('support_messages')
      .select('*')
      .eq('conversation_id', id)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Fetch messages error:', error);
      res.status(500).json({ error: 'Failed to fetch messages.' });
      return;
    }

    // Mark admin messages as read if the current user is not an admin
    if (role !== 'ADMIN') {
      const unreadIds = (messages || [])
        .filter((m: any) => m.sender_role === 'ADMIN' && !m.is_read)
        .map((m: any) => m.id);

      if (unreadIds.length > 0) {
        await supabase.admin
          .from('support_messages')
          .update({ is_read: true })
          .in('id', unreadIds);
      }
    }

    res.status(200).json({ messages: messages || [] });
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/support/conversations/:id/messages
// Send a message in a conversation
// ──────────────────────────────────────────────
export const sendMessage = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { message } = req.body;

    if (!message || message.trim().length === 0) {
      res.status(400).json({ error: 'Message is required.' });
      return;
    }

    // Verify the conversation exists
    const role = getUserRole(req);
    const { data: conversation } = await supabase.admin
      .from('support_conversations')
      .select('user_id, status')
      .eq('id', id)
      .maybeSingle();

    if (!conversation) {
      res.status(404).json({ error: 'Conversation not found.' });
      return;
    }

    if (conversation.status === 'CLOSED') {
      res.status(400).json({ error: 'This conversation is closed.' });
      return;
    }

    // Only the conversation owner or admin can send messages
    if (conversation.user_id !== userId && role !== 'ADMIN') {
      res.status(403).json({ error: 'Access denied.' });
      return;
    }

    const senderRole = role === 'ADMIN' ? 'ADMIN' : 'USER';

    const { data: msg, error } = await supabase.admin
      .from('support_messages')
      .insert({
        conversation_id: id,
        sender_id: userId,
        sender_role: senderRole,
        message: message.trim(),
        is_read: senderRole === 'USER', // User's own messages are auto-read
        created_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error) {
      console.error('Send message error:', error);
      res.status(500).json({ error: 'Failed to send message.' });
      return;
    }

    // Update conversation timestamp
    await supabase.admin
      .from('support_conversations')
      .update({ updated_at: new Date().toISOString() })
      .eq('id', id);

    // Send push notification to the other party
    if (senderRole === 'ADMIN') {
      // Notify the user
      notifyUser(conversation.user_id, supabase.admin, {
        title: 'Support Response 💬',
        body: `Support replied: ${message.trim().substring(0, 80)}`,
        data: { type: 'support_reply', conversation_id: id },
      }).catch(() => {});
    } else {
      // Notify all admins
      const { data: admins } = await supabase.admin
        .from('users')
        .select('id')
        .eq('role', 'ADMIN');

      if (admins) {
        for (const admin of admins) {
          notifyUser(admin.id, supabase.admin, {
            title: 'New Support Message 💬',
            body: `New message: ${message.trim().substring(0, 80)}`,
            data: { type: 'support_message', conversation_id: id },
          }).catch(() => {});
        }
      }
    }

    res.status(201).json({
      message: 'Message sent.',
      msg,
    });
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/support/conversations/:id/close
// Close a conversation
// ──────────────────────────────────────────────
export const closeConversation = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { data: conversation, error: fetchError } = await supabase.admin
      .from('support_conversations')
      .select('user_id')
      .eq('id', id)
      .maybeSingle();

    if (fetchError || !conversation) {
      res.status(404).json({ error: 'Conversation not found.' });
      return;
    }

    const role = getUserRole(req);
    if (conversation.user_id !== userId && role !== 'ADMIN') {
      res.status(403).json({ error: 'Access denied.' });
      return;
    }

    const { data: updated, error } = await supabase.admin
      .from('support_conversations')
      .update({
        status: 'CLOSED',
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .select()
      .single();

    if (error) {
      console.error('Close conversation error:', error);
      res.status(500).json({ error: 'Failed to close conversation.' });
      return;
    }

    res.status(200).json({
      message: 'Conversation closed.',
      conversation: updated,
    });
  } catch (error) {
    console.error('Close conversation error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
