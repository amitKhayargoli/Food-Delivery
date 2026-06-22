import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase'
import type { UserStatus } from '@/lib/types'

// PATCH /api/users/[id]/status — update user status (approve/reject)
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params
    const body: { status: UserStatus } = await request.json()
    const { status } = body

    console.log(`[RT-ADMIN] 🏷 PATCH /api/users/${id}/status → ${status}`);

    const validStatuses: UserStatus[] = ['ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING', 'REJECTED']
    if (!validStatuses.includes(status)) {
      console.log(`[RT-ADMIN] ❌ Invalid status: ${status}`);
      return NextResponse.json(
        { error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` },
        { status: 400 },
      )
    }

    // Update the user's status
    const { data: user, error } = await supabaseAdmin
      .from('users')
      .update({ status, updated_at: new Date().toISOString() })
      .eq('id', id)
      .select('id, username, email, phone, role, status, created_at, updated_at')
      .single()

    if (error) {
      console.error('[RT-ADMIN] ❌ Supabase status update error:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    if (!user) {
      console.log(`[RT-ADMIN] ❌ User not found: ${id}`);
      return NextResponse.json({ error: 'User not found' }, { status: 404 })
    }

    console.log(`[RT-ADMIN] ✅ User ${user.username} (${user.role}) status → ${status}`);
    console.log(`[RT-ADMIN]   └─ Supabase Realtime should now broadcast this change`);

    return NextResponse.json(user)
  } catch (error) {
    console.error('[RT-ADMIN] ❌ Status update error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
