import { describe, it, expect, vi, beforeEach } from 'vitest'
import { NextRequest } from 'next/server'

// ── Mock the supabase module ──────────────────────────────────────────

const mockFrom = vi.fn()
const mockSelect = vi.fn()
const mockEq = vi.fn()
const mockSingle = vi.fn()
const mockMaybeSingle = vi.fn()
const mockUpdate = vi.fn()
const mockLimit = vi.fn()
const mockNeq = vi.fn()
const mockOr = vi.fn()

// Default mock user returned by most queries
const defaultUser = {
  id: 'user-123',
  username: 'johndoe',
  email: 'john@example.com',
  phone: '9800000000',
  role: 'CUSTOMER' as const,
  status: 'ACTIVE',
  created_at: '2025-01-01T00:00:00Z',
  updated_at: '2025-01-01T00:00:00Z',
}

vi.mock('@/lib/supabase', () => ({
  supabaseAdmin: {
    from: (table: string) => {
      mockFrom(table)
      return ({
        // select path: from('users').select('...').eq/neq/or/limit/maybeSingle/single
        select: (cols?: string) => {
          mockSelect(cols)
          return ({
            eq: (col: string, val: string) => {
              mockEq(col, val)
              return ({
                single: () => mockSingle(),
                maybeSingle: () => mockMaybeSingle(),
              })
            },
            neq: (col: string, val: string) => {
              mockNeq(col, val)
              return ({
                or: (...args: any[]) => {
                  mockOr(...args)
                  return ({
                    limit: (n: number) => mockLimit(n),
                  })
                },
              })
            },
          })
        },
        // update path: from('users').update(data).eq('id', id).select('...').single()
        update: (data: Record<string, any>) => {
          mockUpdate(data)
          return ({
            eq: (col: string, val: string) => {
              mockEq(col, val)
              return ({
                select: (cols?: string) => {
                  mockSelect(cols)
                  return ({
                    single: () => mockSingle(),
                  })
                },
              })
            },
          })
        },
      })
    },
  },
}))

describe('PATCH /api/users/[id] — Edit User API', () => {
  beforeEach(() => {
    vi.clearAllMocks()

    // Default: user exists and no conflicts
    mockMaybeSingle.mockResolvedValue({ data: { id: 'user-123' }, error: null })
    mockLimit.mockResolvedValue({ data: [], error: null })
  })

  // ── 1. Successfully update username ─────────────────────────────
  it('should update the username successfully', async () => {
    mockSingle.mockResolvedValue({
      data: { ...defaultUser, username: 'newusername' },
      error: null,
    })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'newusername' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.username).toBe('newusername')
    expect(body.email).toBe('john@example.com')
  })

  // ── 2. Successfully update email ────────────────────────────────
  it('should update the email successfully', async () => {
    mockSingle.mockResolvedValue({
      data: { ...defaultUser, email: 'new@example.com' },
      error: null,
    })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'new@example.com' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.email).toBe('new@example.com')
  })

  // ── 3. Successfully update role ────────────────────────────────
  it('should update the role successfully', async () => {
    mockSingle.mockResolvedValue({
      data: { ...defaultUser, role: 'ADMIN' },
      error: null,
    })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ role: 'ADMIN' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.role).toBe('ADMIN')
  })

  // ── 4. Successfully update status ──────────────────────────────
  it('should update the status successfully', async () => {
    mockSingle.mockResolvedValue({
      data: { ...defaultUser, status: 'SUSPENDED' },
      error: null,
    })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'SUSPENDED' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.status).toBe('SUSPENDED')
  })

  // ── 5. Successfully update all fields at once ──────────────────
  it('should update all fields simultaneously', async () => {
    mockSingle.mockResolvedValue({
      data: {
        ...defaultUser,
        username: 'newname',
        email: 'new@example.com',
        phone: '9900000000',
        role: 'ADMIN',
        status: 'INACTIVE',
      },
      error: null,
    })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'newname',
        email: 'new@example.com',
        phone: '9900000000',
        role: 'ADMIN',
        status: 'INACTIVE',
      }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.username).toBe('newname')
    expect(body.email).toBe('new@example.com')
    expect(body.phone).toBe('9900000000')
    expect(body.role).toBe('ADMIN')
    expect(body.status).toBe('INACTIVE')
  })

  // ── 6. Return 400 when no fields provided ──────────────────────
  it('should return 400 when no updatable fields are provided', async () => {
    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('At least one field')
  })

  // ── 7. Return 400 when invalid role provided ────────────────────
  it('should return 400 when an invalid role is provided', async () => {
    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ role: 'SUPER_ADMIN' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('Invalid role')
  })

  // ── 8. Return 404 when user does not exist ──────────────────────
  it('should return 404 when the user does not exist', async () => {
    // The user existence check returns null (no user found)
    mockMaybeSingle.mockResolvedValue({ data: null, error: null })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-999', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'ghost' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-999' }) })
    const body = await response.json()

    expect(response.status).toBe(404)
    expect(body.error).toBe('User not found')
  })

  // ── 9. Return 409 when username/email conflicts with another user ──
  it('should return 409 when the new username is already taken', async () => {
    mockLimit.mockResolvedValue({
      data: [{ id: 'user-456', username: 'takenuser', email: 'other@example.com', phone: null }],
      error: null,
    })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'takenuser' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(409)
    expect(body.error).toContain('already taken')
  })

  // ── 10. Return 500 when the database update fails ──────────────
  it('should return 500 when the database update throws an error', async () => {
    mockSingle.mockResolvedValue({
      data: null,
      error: { message: 'Database connection lost', code: 'CONNECTION_ERROR' },
    })

    const { PATCH } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-123', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'fine' }),
    })
    const response = await PATCH(request, { params: Promise.resolve({ id: 'user-123' }) })
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Database connection lost')
  })
})
