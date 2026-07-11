import { NextResponse } from 'next/server'
import { getSupabaseAdmin } from '@/lib/supabase'

export async function GET() {
  try {
    const supabase = getSupabaseAdmin()

    const { data: conversations, error } = await supabase
      .from('support_conversations')
      .select('*')
      .order('updated_at', { ascending: false })

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    // Fetch user info and last message for each
    const userIds = [...new Set((conversations || []).map((c: any) => c.user_id))]
    const { data: users } = await supabase
      .from('users')
      .select('id, username, email, phone')
      .in('id', userIds)

    const userMap = new Map<string, any>()
    for (const u of users || []) userMap.set(u.id, u)

    const results = await Promise.all(
      (conversations || []).map(async (conv: any) => {
        const { data: lastMsg } = await supabase
          .from('support_messages')
          .select('*')
          .eq('conversation_id', conv.id)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle()

        const { count: msgCount } = await supabase
          .from('support_messages')
          .select('*', { count: 'exact', head: true })
          .eq('conversation_id', conv.id)

        return {
          ...conv,
          user: userMap.get(conv.user_id) || null,
          last_message: lastMsg || null,
          message_count: msgCount || 0,
        }
      }),
    )

    return NextResponse.json({ conversations: results })
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 })
  }
}
