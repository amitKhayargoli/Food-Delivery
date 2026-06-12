import { NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase'
import type { CreateUserPayload, UserRecord } from '@/lib/types'

// GET /api/users — list all users
export async function GET() {
  const { data: users, error } = await supabaseAdmin
    .from('users')
    .select('id, username, email, phone, role, status, created_at, updated_at')
    .order('created_at', { ascending: false })

  if (error) {
    console.error('Failed to fetch users:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json(users satisfies UserRecord[])
}

// POST /api/users — create a new user (auth + profile)
export async function POST(request: Request) {
  const body: CreateUserPayload = await request.json()

  const { username, email, phone, password, role } = body

  if (!username || !email || !password || !role) {
    return NextResponse.json(
      { error: 'username, email, password, and role are required' },
      { status: 400 },
    )
  }

  if (password.length < 6) {
    return NextResponse.json(
      { error: 'Password must be at least 6 characters' },
      { status: 400 },
    )
  }

  const validRoles = ['CUSTOMER', 'DELIVERY_BOY', 'RESTAURANT_OWNER', 'ADMIN']
  if (!validRoles.includes(role)) {
    return NextResponse.json(
      { error: `Invalid role. Must be one of: ${validRoles.join(', ')}` },
      { status: 400 },
    )
  }

  // 1. Check for existing user
  const { data: existing } = await supabaseAdmin
    .from('users')
    .select('id')
    .or(`email.eq.${email},username.eq.${username}${phone ? `,phone.eq.${phone}` : ''}`)
    .limit(1)
    .maybeSingle()

  if (existing) {
    return NextResponse.json(
      { error: 'A user with this email, username, or phone already exists' },
      { status: 409 },
    )
  }

  // 2. Create auth user in supabase.auth.users
  const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    phone_confirm: true,
    ...(phone ? { phone } : {}),
    user_metadata: { username },
  })

  if (authError || !authData.user) {
    console.error('Auth create error:', authError)
    return NextResponse.json({ error: authError?.message || 'Failed to create user' }, { status: 500 })
  }

  // 3. Determine initial status: non-customer roles start as PENDING
  const requiresApproval = role === 'RESTAURANT_OWNER' || role === 'DELIVERY_BOY'
  const initialStatus = requiresApproval ? 'PENDING' : 'ACTIVE'

  // 3. Upsert into public.users table
  const { data: user, error: upsertError } = await supabaseAdmin
    .from('users')
    .upsert({
      id: authData.user.id,
      username,
      email,
      ...(phone ? { phone } : {}),
      role,
      status: initialStatus,
    }, { onConflict: 'id' })
    .select('id, username, email, phone, role, status, created_at, updated_at')
    .single()

  if (upsertError || !user) {
    console.error('Upsert error:', upsertError)
    // Cleanup: delete the auth user
    await supabaseAdmin.auth.admin.deleteUser(authData.user.id).catch(() => {})
    return NextResponse.json({ error: upsertError?.message || 'Failed to create user profile' }, { status: 500 })
  }

  return NextResponse.json(user satisfies UserRecord, { status: 201 })
}
