import { NextRequest, NextResponse } from 'next/server'
import { getSupabaseAdmin } from '@/lib/supabase'

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params
    const supabase = getSupabaseAdmin()

    const { data: messages, error } = await supabase
      .from('support_messages')
      .select('*')
      .eq('conversation_id', id)
      .order('created_at', { ascending: true })

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ messages: messages || [] })
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 })
  }
}

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params
    const body = await req.json()
    const { message, sender_id } = body

    if (!message || message.trim().length === 0) {
      return NextResponse.json({ error: 'Message is required.' }, { status: 400 })
    }

    if (!sender_id) {
      return NextResponse.json({ error: 'sender_id is required.' }, { status: 400 })
    }

    const supabase = getSupabaseAdmin()

    // Verify conversation is open
    const { data: conv } = await supabase
      .from('support_conversations')
      .select('status')
      .eq('id', id)
      .maybeSingle()

    if (!conv) {
      return NextResponse.json({ error: 'Conversation not found.' }, { status: 404 })
    }

    if (conv.status === 'CLOSED') {
      return NextResponse.json({ error: 'Conversation is closed.' }, { status: 400 })
    }

    // Insert the admin message
    const { data: msg, error: insertError } = await supabase
      .from('support_messages')
      .insert({
        conversation_id: id,
        sender_id: sender_id,
        sender_role: 'ADMIN',
        message: message.trim(),
        is_read: false,
        created_at: new Date().toISOString(),
      })
      .select()
      .single()

    if (insertError) {
      return NextResponse.json({ error: insertError.message }, { status: 500 })
    }

    // Update conversation timestamp
    await supabase
      .from('support_conversations')
      .update({ updated_at: new Date().toISOString() })
      .eq('id', id)

    return NextResponse.json({ message: 'Message sent.', msg })
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 })
  }
}
