import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase'
import type { UserRecord, AppRole } from '@/lib/types'

// DELETE /api/users/[id] — delete a user (auth + profile)
export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params

    // 1. Check if user exists
    const { data: existing, error: fetchError } = await supabaseAdmin
      .from('users')
      .select('id, username, role')
      .eq('id', id)
      .maybeSingle()

    if (fetchError) {
      console.error('Fetch user error:', fetchError)
      return NextResponse.json({ error: fetchError.message }, { status: 500 })
    }

    if (!existing) {
      return NextResponse.json({ error: 'User not found' }, { status: 404 })
    }

    const username = existing.username

    // 2. Delete from auth (supabase.auth.users)
    const { error: authError } = await supabaseAdmin.auth.admin.deleteUser(id)
    if (authError) {
      console.error('Auth delete error:', authError)
      return NextResponse.json({ error: authError.message }, { status: 500 })
    }

    // 3. Delete from public.users table
    const { error: deleteError } = await supabaseAdmin
      .from('users')
      .delete()
      .eq('id', id)

    if (deleteError) {
      console.error('Profile delete error:', deleteError)
      // Auth user already deleted — no cleanup needed, surface the error
      return NextResponse.json({ error: deleteError.message }, { status: 500 })
    }

    console.log(`User ${username} (${id}) deleted`)

    return NextResponse.json({ message: `User ${username} deleted successfully` })
  } catch (error) {
    console.error('Delete user error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

// GET /api/users/[id] — get a single user
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params

    const { data: user, error } = await supabaseAdmin
      .from('users')
      .select('id, username, email, phone, role, status, created_at, updated_at')
      .eq('id', id)
      .single()

    if (error) {
      if (error.code === 'PGRST116') {
        return NextResponse.json({ error: 'User not found' }, { status: 404 })
      }
      console.error('Fetch user error:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json(user satisfies UserRecord)
  } catch (error) {
    console.error('Fetch user error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

// PATCH /api/users/[id] — update a user's details
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params
    const body = await request.json()
    const { username, email, phone, role, status } = body

    // Validate at least one field is provided
    if (!username && !email && !phone && !role && !status) {
      return NextResponse.json(
        { error: 'At least one field (username, email, phone, role, status) must be provided' },
        { status: 400 },
      )
    }

    // Validate role if provided
    const validRoles: AppRole[] = ['CUSTOMER', 'DELIVERY_BOY', 'RESTAURANT_OWNER', 'ADMIN']
    if (role && !validRoles.includes(role)) {
      return NextResponse.json(
        { error: `Invalid role. Must be one of: ${validRoles.join(', ')}` },
        { status: 400 },
      )
    }

    // Check if user exists
    const { data: existing } = await supabaseAdmin
      .from('users')
      .select('id')
      .eq('id', id)
      .maybeSingle()

    if (!existing) {
      return NextResponse.json({ error: 'User not found' }, { status: 404 })
    }

    // Check for conflicts (username, email, phone taken by another user)
    if (username || email || phone) {
      const orConditions: string[] = []
      if (username) orConditions.push(`username.eq.${username}`)
      if (email) orConditions.push(`email.eq.${email}`)
      if (phone) orConditions.push(`phone.eq.${phone}`)

      const { data: conflicts } = await supabaseAdmin
        .from('users')
        .select('id, username, email, phone')
        .neq('id', id)
        .or(orConditions.join(','))
        .limit(1)

      if (conflicts && conflicts.length > 0) {
        const conflict = conflicts[0]
        const field = conflict.username === username ? 'username' :
                      conflict.email === email ? 'email' : 'phone'
        return NextResponse.json(
          { error: `This ${field} is already taken by another user.` },
          { status: 409 },
        )
      }
    }

    // Build update object with only provided fields
    const updateData: Record<string, any> = { updated_at: new Date().toISOString() }
    if (username !== undefined) updateData.username = username
    if (email !== undefined) updateData.email = email
    if (phone !== undefined) updateData.phone = phone
    if (role !== undefined) updateData.role = role
    if (status !== undefined) updateData.status = status

    const { data: updated, error } = await supabaseAdmin
      .from('users')
      .update(updateData)
      .eq('id', id)
      .select('id, username, email, phone, role, status, created_at, updated_at')
      .single()

    if (error) {
      console.error('Update user error:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    console.log(`User ${updated.username} (${id}) updated:`, Object.keys(updateData).filter(k => k !== 'updated_at').join(', '))

    return NextResponse.json(updated satisfies UserRecord)
  } catch (error) {
    console.error('Update user error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
