/**
 * Support Chat Test Script
 * =========================
 *
 * Use this to test the realtime support chat end-to-end.
 *
 * Usage:
 *   npx ts-node scripts/test_support_chat.ts list              # List open conversations
 *   npx ts-node scripts/test_support_chat.ts reply <conv_id>    # Reply to a conversation
 *
 * Prerequisites:
 *   - Backend .env file must have SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
 *   - Run from the backend/ directory
 */

import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as readline from 'readline';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const WebSocket = require('ws');

// Load .env from backend root
dotenv.config({ path: path.resolve(__dirname, '../.env') });

const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!SUPABASE_URL || !SERVICE_ROLE) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { autoRefreshToken: false, persistSession: false },
  realtime: { transport: WebSocket as any },
});

async function listConversations() {
  console.log('\n📋 Fetching open support conversations...\n');

  const { data: conversations, error } = await admin
    .from('support_conversations')
    .select('*')
    .eq('status', 'OPEN')
    .order('updated_at', { ascending: false });

  if (error) {
    console.error('❌ Error fetching conversations:', error.message);
    process.exit(1);
  }

  if (!conversations || conversations.length === 0) {
    console.log('   No open conversations found.');
    console.log('   📱 Open the Flutter app → Profile → Support → Contact Support');
    console.log('   Then run this script again.\n');
    process.exit(0);
  }

  // Fetch user info and message count for each
  const userIds = [...new Set(conversations.map((c: any) => c.user_id))];
  const { data: users } = await admin
    .from('users')
    .select('id, username, email')
    .in('id', userIds);

  const userMap = new Map<string, any>();
  for (const u of users || []) userMap.set(u.id, u);

  for (const conv of conversations) {
    const userInfo = userMap.get(conv.user_id);
    const { count: msgCount } = await admin
      .from('support_messages')
      .select('*', { count: 'exact', head: true })
      .eq('conversation_id', conv.id);

    const { data: lastMsg } = await admin
      .from('support_messages')
      .select('*')
      .eq('conversation_id', conv.id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
    console.log(`  ID:       ${conv.id.substring(0, 12)}...`);
    console.log(`  Subject:  ${conv.subject}`);
    console.log(`  User:     ${userInfo?.username || 'Unknown'} (${userInfo?.email || 'no email'})`);
    console.log(`  Messages: ${msgCount ?? 0}`);
    console.log(`  Created:  ${conv.created_at}`);
    if (lastMsg) {
      const preview = (lastMsg.message as string).substring(0, 80);
      console.log(`  Last msg: ${preview}${lastMsg.message.length > 80 ? '...' : ''}`);
      console.log(`  By:       ${lastMsg.sender_role}`);
    }
    console.log('');
  }

  console.log(`\n✅ To reply to a conversation, run:`);
  console.log(`   npx ts-node scripts/test_support_chat.ts reply <FULL_CONVERSATION_ID>\n`);
}

async function replyToConversation(convId: string) {
  // First verify the conversation exists and is open
  const { data: conv, error: fetchError } = await admin
    .from('support_conversations')
    .select('*')
    .eq('id', convId)
    .maybeSingle();

  if (fetchError || !conv) {
    console.error('❌ Conversation not found. Check the ID and try again.');
    process.exit(1);
  }

  if (conv.status === 'CLOSED') {
    console.error('❌ This conversation is already closed.');
    process.exit(1);
  }

  if (!conv.user_id) {
    console.error('❌ Conversation has no user_id. Cannot proceed.');
    process.exit(1);
  }

  console.log(`\n💬 Replying to: "${conv.subject}"\n`);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const message = await new Promise<string>((resolve) => {
    rl.question('   Type your admin reply and press Enter: ', (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });

  if (!message) {
    console.log('   No message entered. Exiting.\n');
    return;
  }

  // Look up an actual admin user for the sender_id
  const { data: admins } = await admin
    .from('users')
    .select('id')
    .eq('role', 'ADMIN')
    .limit(1);

  const adminId = (admins && admins.length > 0) ? admins[0].id : conv.user_id;
  if (!adminId) {
    console.error('❌ Could not determine sender_id for admin message.');
    process.exit(1);
  }

  // Insert the message as ADMIN
  const { data: msg, error: insertError } = await admin
    .from('support_messages')
    .insert({
      conversation_id: convId,
      sender_id: adminId,
      sender_role: 'ADMIN',
      message: message,
      is_read: false,
      created_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (insertError) {
    console.error('❌ Failed to send message:', insertError.message);
    process.exit(1);
  }

  // Update conversation timestamp
  await admin
    .from('support_conversations')
    .update({ updated_at: new Date().toISOString() })
    .eq('id', convId);

  console.log(`\n✅ Admin reply sent successfully!`);
  console.log(`   Message ID: ${(msg as any).id}`);
  console.log(`\n   📱 Check your phone — the reply should appear in realtime!\n`);
}

const command = process.argv[2];

if (command === 'list') {
  listConversations();
} else if (command === 'reply') {
  const convId = process.argv[3];
  if (!convId) {
    console.error('❌ Please provide a conversation ID.\n   Usage: npx ts-node scripts/test_support_chat.ts reply <CONVERSATION_ID>\n');
    process.exit(1);
  }
  replyToConversation(convId);
} else {
  console.log(`
  Support Chat Test Script

  Commands:
    list              List all open support conversations
    reply <conv_id>   Send an admin reply to a conversation

  Examples:
    npx ts-node scripts/test_support_chat.ts list
    npx ts-node scripts/test_support_chat.ts reply abc-123-def

  First, open the Flutter app on your phone and create a support conversation.
  `);
}
