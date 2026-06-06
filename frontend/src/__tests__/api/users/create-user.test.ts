import { describe, it, expect, vi, beforeEach } from 'vitest'

// ── Mock the supabase module ──────────────────────────────────────────

const mockFrom = vi.fn()
const mockSelect = vi.fn()
const mockSingle = vi.fn()
const mockMaybeSingle = vi.fn()
const mockOr = vi.fn()
const mockUpsert = vi.fn()
const mockCreateUser = vi.fn()
const mockDeleteUser = vi.fn()

const defaultUser = {
  id: 'new-user-id-abc',
  username: 'janedoe',
  email: 'jane@example.com',
  phone: '9800000000',
  role: 'CUSTOMER' as const,
  status: 'ACTIVE',
  created_at: '2025-06-01T00:00:00Z',
  updated_at: '2025-06-01T00:00:00Z',
}

vi.mock('@/lib/supabase', () => ({
  supabaseAdmin: {
    from: (table: string) => {
      mockFrom(table)
      return ({
        // select path: from('users').select('...').or(conditions).limit(1).maybeSingle()
        select: (cols?: string) => {
          mockSelect(cols)
          return ({
            or: (...args: any[]) => {
              mockOr(...args)
              return ({
                limit: (_n: number) => ({
                  maybeSingle: () => mockMaybeSingle(),
                }),
              })
            },
          })
        },
        // upsert path: from('users').upsert(data, opts).select('...').single()
        upsert: (data: Record<string, any>, opts?: any) => {
          mockUpsert(data, opts)
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
    auth: {
      admin: {
        createUser: (payload: any) => mockCreateUser(payload),
        deleteUser: (id: string) => mockDeleteUser(id),
      },
    },
  },
}))

describe('POST /api/users — Create User API', () => {
  beforeEach(() => {
    vi.clearAllMocks()

    // Default: no existing user, auth creation succeeds, upsert succeeds
    mockMaybeSingle.mockResolvedValue({ data: null, error: null })
    mockCreateUser.mockResolvedValue({
      data: { user: { id: 'new-user-id-abc' } },
      error: null,
    })
    mockSingle.mockResolvedValue({ data: defaultUser, error: null })
    mockDeleteUser.mockResolvedValue({ data: null, error: null })
  })

  // ── Validation: missing fields ──────────────────────────────────

  it('should return 400 when the request body is empty', async () => {
    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('required')
  })

  it('should return 400 when username is missing', async () => {
    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'test@test.com', password: '123456', role: 'CUSTOMER' }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('required')
  })

  it('should return 400 when email is missing', async () => {
    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'testuser', password: '123456', role: 'CUSTOMER' }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('required')
  })

  it('should return 400 when password is missing', async () => {
    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'testuser', email: 'test@test.com', role: 'CUSTOMER' }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('required')
  })

  it('should return 400 when role is missing', async () => {
    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'testuser', email: 'test@test.com', password: '123456' }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('required')
  })

  // ── Validation: field formats ───────────────────────────────────

  it('should return 400 when password is shorter than 6 characters', async () => {
    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('at least 6 characters')
  })

  it('should return 400 when an invalid role is provided', async () => {
    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123456',
        role: 'SUPER_ADMIN',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(400)
    expect(body.error).toContain('Invalid role')
  })

  // ── Conflict detection ──────────────────────────────────────────

  it('should return 409 when a user with the same email already exists', async () => {
    mockMaybeSingle.mockResolvedValue({
      data: { id: 'existing-user' },
      error: null,
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'newuser',
        email: 'existing@example.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(409)
    expect(body.error).toContain('already exists')
  })

  it('should return 409 when a user with the same username already exists', async () => {
    mockMaybeSingle.mockResolvedValue({
      data: { id: 'existing-user' },
      error: null,
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'takenuser',
        email: 'unique@example.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(409)
    expect(body.error).toContain('already exists')
  })

  // ── Auth creation failures ──────────────────────────────────────

  it('should return 500 when Supabase auth user creation fails', async () => {
    mockCreateUser.mockResolvedValue({
      data: { user: null },
      error: { message: 'Email already registered in auth system' },
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Email already registered')
  })

  it('should return 500 when auth creation returns no user and no error', async () => {
    mockCreateUser.mockResolvedValue({
      data: { user: null },
      error: null,
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Failed to create user')
  })

  // ── Upsert (profile creation) failures ──────────────────────────

  it('should return 500 when the upsert into users table fails', async () => {
    mockSingle.mockResolvedValue({
      data: null,
      error: { message: 'Database constraint violation' },
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Database constraint violation')
  })

  it('should call deleteUser to clean up auth user when upsert fails', async () => {
    mockSingle.mockResolvedValue({
      data: null,
      error: { message: 'Upsert failed' },
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    await POST(request)

    expect(mockDeleteUser).toHaveBeenCalledWith('new-user-id-abc')
  })

  it('should return 500 when upsert returns null user without error', async () => {
    mockSingle.mockResolvedValue({
      data: null,
      error: null,
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Failed to create user profile')
  })

  // ── Success cases: various roles ────────────────────────────────

  it('should create a CUSTOMER user with status ACTIVE and no phone', async () => {
    const createdUser = { ...defaultUser, role: 'CUSTOMER', status: 'ACTIVE', phone: null }
    mockSingle.mockResolvedValue({ data: createdUser, error: null })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'janedoe',
        email: 'jane@example.com',
        password: 'secure123',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(201)
    expect(body.role).toBe('CUSTOMER')
    expect(body.status).toBe('ACTIVE')
    expect(body.phone).toBeNull()
  })

  it('should create a CUSTOMER user with phone included', async () => {
    const createdUser = {
      ...defaultUser,
      username: 'johndoe',
      email: 'john@example.com',
      phone: '9812345678',
      role: 'CUSTOMER',
      status: 'ACTIVE',
    }
    mockSingle.mockResolvedValue({ data: createdUser, error: null })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'johndoe',
        email: 'john@example.com',
        phone: '9812345678',
        password: 'secure123',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(201)
    expect(body.role).toBe('CUSTOMER')
    expect(body.status).toBe('ACTIVE')
    expect(body.phone).toBe('9812345678')
  })

  it('should create an ADMIN user with status ACTIVE', async () => {
    const createdUser = {
      ...defaultUser,
      username: 'admin1',
      email: 'admin@example.com',
      role: 'ADMIN',
      status: 'ACTIVE',
    }
    mockSingle.mockResolvedValue({ data: createdUser, error: null })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'admin1',
        email: 'admin@example.com',
        password: 'adminpass123',
        role: 'ADMIN',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(201)
    expect(body.role).toBe('ADMIN')
    expect(body.status).toBe('ACTIVE')
  })

  it('should create a RESTAURANT_OWNER user with status PENDING', async () => {
    const createdUser = {
      ...defaultUser,
      username: 'restowner',
      email: 'owner@restaurant.com',
      role: 'RESTAURANT_OWNER',
      status: 'PENDING',
    }
    mockSingle.mockResolvedValue({ data: createdUser, error: null })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'restowner',
        email: 'owner@restaurant.com',
        password: 'ownerpass123',
        role: 'RESTAURANT_OWNER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(201)
    expect(body.role).toBe('RESTAURANT_OWNER')
    expect(body.status).toBe('PENDING')
  })

  it('should create a DELIVERY_BOY user with status PENDING', async () => {
    const createdUser = {
      ...defaultUser,
      username: 'delivery1',
      email: 'delivery@example.com',
      role: 'DELIVERY_BOY',
      status: 'PENDING',
    }
    mockSingle.mockResolvedValue({ data: createdUser, error: null })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'delivery1',
        email: 'delivery@example.com',
        password: 'deliver123',
        role: 'DELIVERY_BOY',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(201)
    expect(body.role).toBe('DELIVERY_BOY')
    expect(body.status).toBe('PENDING')
  })

  // ── Edge cases ──────────────────────────────────────────────────

  it('should handle username with numbers and underscores', async () => {
    const createdUser = {
      ...defaultUser,
      username: 'user_name_123',
      email: 'special@example.com',
      phone: null,
      role: 'CUSTOMER',
      status: 'ACTIVE',
    }
    mockSingle.mockResolvedValue({ data: createdUser, error: null })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'user_name_123',
        email: 'special@example.com',
        password: 'password123',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(201)
    expect(body.username).toBe('user_name_123')
  })

  it('should handle cleanup gracefully when deleteUser also fails', async () => {
    mockSingle.mockResolvedValue({
      data: null,
      error: { message: 'Upsert failed' },
    })
    mockDeleteUser.mockResolvedValue({
      data: null,
      error: { message: 'Delete failed too' },
    })

    const { POST } = await import('@/app/api/users/route')
    const request = new Request('http://localhost/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'test@test.com',
        password: '123456',
        role: 'CUSTOMER',
      }),
    })
    const response = await POST(request)
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Upsert failed')
  })
})
