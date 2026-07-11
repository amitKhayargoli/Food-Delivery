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

    // Look up restaurant_id from the order (if order_id is provided)
    let restaurantId: string | null = null;
    if (order_id) {
      const { data: order } = await supabase.admin
        .from('orders')
        .select('restaurant_id')
        .eq('id', order_id)
        .maybeSingle();

      if (order) {
        restaurantId = order.restaurant_id;
      }
    }

    const { data: conversation, error } = await supabase.admin
      .from('support_conversations')
      .insert({
        user_id: userId,
        order_id: order_id || null,
        restaurant_id: restaurantId,
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

    // Fetch restaurant name if linked to a restaurant
    let restaurantName: string | null = null;
    if (restaurantId) {
      const { data: app } = await supabase.admin
        .from('restaurant_applications')
        .select('restaurant_name')
        .eq('id', restaurantId)
        .maybeSingle();

      restaurantName = app?.restaurant_name || null;
    }

    // Notify the relevant users about the new conversation
    if (restaurantId) {
      // Notify the specific restaurant owner
      const { data: restaurant } = await supabase.admin
        .from('restaurant_applications')
        .select('user_id')
        .eq('id', restaurantId)
        .maybeSingle();

      if (restaurant?.user_id) {
        notifyUser(restaurant.user_id, supabase.admin, {
          title: 'New Support Request 📩',
          body: `New conversation: ${subject}`,
          data: { type: 'support_new', conversation_id: conversation.id },
        }, 'owner').catch(() => {});
      }
    }

    // Also notify all admins
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
        }, 'admin').catch(() => {});
      }
    }

    res.status(201).json({
      message: 'Conversation created.',
      conversation: {
        ...conversation,
        restaurant_name: restaurantName,
      },
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

    // Batch-fetch restaurant names for any conversations with restaurant_id
    const restaurantIds = [...new Set((conversations || [])
      .map((c: any) => c.restaurant_id)
      .filter(Boolean))] as string[];

    const restaurantNameMap = new Map<string, string>();
    if (restaurantIds.length > 0) {
      const { data: apps } = await supabase.admin
        .from('restaurant_applications')
        .select('id, restaurant_name')
        .in('id', restaurantIds);

      for (const app of apps || []) {
        restaurantNameMap.set(app.id, app.restaurant_name);
      }
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
          restaurant_name: conv.restaurant_id ? (restaurantNameMap.get(conv.restaurant_id) || null) : null,
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
    if (role !== 'ADMIN' && role !== 'RESTAURANT_OWNER') {
      res.status(403).json({ error: 'Support agent access required.' });
      return;
    }

    const status = req.query.status as string | undefined;

    let query = supabase.admin
      .from('support_conversations')
      .select('*')
      .order('updated_at', { ascending: false });

    // For restaurant owners, only show conversations for their restaurant
    if (role === 'RESTAURANT_OWNER') {
      const userId = await getUserId(req);
      const { data: application } = await supabase.admin
        .from('restaurant_applications')
        .select('id')
        .eq('user_id', userId)
        .eq('status', 'APPROVED')
        .maybeSingle();

      if (application) {
        query = query.eq('restaurant_id', application.id);
      } else {
        // Owner has no approved restaurant — return empty
        res.status(200).json({ conversations: [] });
        return;
      }
    }

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

    // Verify the user owns this conversation or is a support agent
    const role = getUserRole(req);
    const { data: conversation } = await supabase.admin
      .from('support_conversations')
      .select('user_id, restaurant_id')
      .eq('id', id)
      .maybeSingle();

    if (!conversation) {
      res.status(404).json({ error: 'Conversation not found.' });
      return;
    }

    // Conversation owner or admin can always access
    if (conversation.user_id === userId || role === 'ADMIN') {
      // allowed
    } else if (role === 'RESTAURANT_OWNER') {
      // Restaurant owner must own the restaurant tied to this conversation
      const { data: application } = await supabase.admin
        .from('restaurant_applications')
        .select('id')
        .eq('id', conversation.restaurant_id)
        .eq('user_id', userId)
        .maybeSingle();

      if (!application) {
        res.status(403).json({ error: 'Access denied. You do not own this restaurant.' });
        return;
      }
    } else {
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

    // Mark admin/owner messages as read if the current user is a regular user (not support agent)
    if (role !== 'ADMIN' && role !== 'RESTAURANT_OWNER') {
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
      .select('user_id, status, restaurant_id')
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

    // Only the conversation owner or support agents can send messages
    const isSupportAgent = role === 'ADMIN' || role === 'RESTAURANT_OWNER';
    if (conversation.user_id !== userId && !isSupportAgent) {
      res.status(403).json({ error: 'Access denied.' });
      return;
    }

    // Restaurant owner must own the restaurant for this conversation
    if (role === 'RESTAURANT_OWNER' && conversation.user_id !== userId) {
      const { data: application } = await supabase.admin
        .from('restaurant_applications')
        .select('id')
        .eq('id', conversation.restaurant_id)
        .eq('user_id', userId)
        .maybeSingle();

      if (!application) {
        res.status(403).json({ error: 'You do not own this restaurant.' });
        return;
      }
    }

    const senderRole = isSupportAgent ? 'ADMIN' : 'USER';

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
      // Notify the restaurant owner for this conversation (if restaurant-linked)
      if (conversation.restaurant_id) {
        const { data: restaurant } = await supabase.admin
          .from('restaurant_applications')
          .select('user_id')
          .eq('id', conversation.restaurant_id)
          .maybeSingle();

        if (restaurant?.user_id) {
          notifyUser(restaurant.user_id, supabase.admin, {
            title: 'New Support Message 💬',
            body: `New message: ${message.trim().substring(0, 80)}`,
            data: { type: 'support_message', conversation_id: id },
          }, 'owner').catch(() => {});
        }
      }

      // Also notify all admins
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
          }, 'admin').catch(() => {});
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
      .select('user_id, restaurant_id')
      .eq('id', id)
      .maybeSingle();

    if (fetchError || !conversation) {
      res.status(404).json({ error: 'Conversation not found.' });
      return;
    }

    const role = getUserRole(req);

    // Conversation owner or admin can always close
    if (conversation.user_id === userId || role === 'ADMIN') {
      // allowed
    } else if (role === 'RESTAURANT_OWNER') {
      // Restaurant owner must own the restaurant
      const { data: application } = await supabase.admin
        .from('restaurant_applications')
        .select('id')
        .eq('id', conversation.restaurant_id)
        .eq('user_id', userId)
        .maybeSingle();

      if (!application) {
        res.status(403).json({ error: 'You do not own this restaurant.' });
        return;
      }
    } else {
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
