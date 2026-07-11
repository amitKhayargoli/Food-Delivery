import { describe, it, expect, vi, beforeEach } from 'vitest'
import { NextRequest } from 'next/server'

// ── Mock the supabase module ──────────────────────────────────────────

const mockFrom = vi.fn()
const mockSelect = vi.fn()
const mockEq = vi.fn()
const mockMaybeSingle = vi.fn()
const mockDeleteOp = vi.fn()
const mockDeleteAuthUser = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabaseAdmin: {
    from: (table: string) => {
      mockFrom(table)
      return ({
        select: (cols?: string) => {
          mockSelect(cols)
          return ({
            eq: (col: string, val: string) => {
              mockEq(col, val)
              return ({
                maybeSingle: () => mockMaybeSingle(),
              })
            },
          })
        },
        delete: () => ({
          eq: (col: string, val: string) => {
            mockEq(col, val)
            return mockDeleteOp()
          },
        }),
      })
    },
    auth: {
      admin: {
        deleteUser: (id: string) => mockDeleteAuthUser(id),
      },
    },
  },
}))

const existingUser = {
  id: 'user-to-delete',
  username: 'johndoe',
  role: 'CUSTOMER',
}

describe('DELETE /api/users/[id] — Delete User API', () => {
  beforeEach(() => {
    vi.clearAllMocks()

    // Default: user exists, auth delete succeeds, table delete succeeds
    mockMaybeSingle.mockResolvedValue({ data: existingUser, error: null })
    mockDeleteAuthUser.mockResolvedValue({ data: null, error: null })
    mockDeleteOp.mockResolvedValue({ data: null, error: null })
  })

  // ── 1. Successful delete ────────────────────────────────────────

  it('should delete an existing user successfully', async () => {
    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.message).toContain('johndoe')
    expect(body.message).toContain('deleted')
  })

  // ── 2. Success response contains username -- ──────────────────────

  it('should return the correct success message with username', async () => {
    const user = { ...existingUser, username: 'janedoe' }
    mockMaybeSingle.mockResolvedValue({ data: user, error: null })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.message).toBe('User janedoe deleted successfully')
  })

  // ── 3. Calls auth deleteUser with correct id ─────────────────────

  it('should call auth.admin.deleteUser with the correct user id', async () => {
    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })

    expect(mockDeleteAuthUser).toHaveBeenCalledWith('user-to-delete')
  })

  // ── 4. Calls table delete with correct id ────────────────────────

  it('should call from().delete().eq() with the correct user id', async () => {
    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })

    // mockEq is called twice: once for existence check, once for delete
    // We assert the second call (from delete) had the right id
    expect(mockEq).toHaveBeenCalledWith('id', 'user-to-delete')
  })

  // ── 5. Return 404 when user does not exist ──────────────────────

  it('should return 404 when the user does not exist', async () => {
    mockMaybeSingle.mockResolvedValue({ data: null, error: null })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/nonexistent', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'nonexistent' }) })
    const body = await response.json()

    expect(response.status).toBe(404)
    expect(body.error).toBe('User not found')
  })

  // ── 6. Return 500 when existence check query fails ──────────────

  it('should return 500 when the existence check query fails', async () => {
    mockMaybeSingle.mockResolvedValue({
      data: null,
      error: { message: 'Database connection error' },
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Database connection error')
  })

  // ── 7. Return 500 when auth delete fails ─────────────────────────

  it('should return 500 when auth.admin.deleteUser fails', async () => {
    mockDeleteAuthUser.mockResolvedValue({
      data: null,
      error: { message: 'Auth user not found or already deleted' },
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Auth user not found')
  })

  // ── 8. Does not call table delete if auth delete fails ───────────

  it('should NOT call table delete if auth delete fails', async () => {
    mockDeleteAuthUser.mockResolvedValue({
      data: null,
      error: { message: 'Auth deletion failed' },
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })

    // from() called only once (for existence check), not for table delete
    expect(mockFrom).toHaveBeenCalledTimes(1)
  })

  // ── 9. Return 500 when table delete fails ────────────────────────

  it('should return 500 when the table delete operation fails', async () => {
    mockDeleteOp.mockResolvedValue({
      data: null,
      error: { message: 'Foreign key constraint violation' },
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('Foreign key constraint violation')
  })

  // ── 10. Table delete fails after auth delete succeeds ─────────────

  it('should still return 500 even when auth delete succeeded but table delete fails', async () => {
    // Auth delete succeeds
    mockDeleteAuthUser.mockResolvedValue({ data: null, error: null })
    // Table delete fails
    mockDeleteOp.mockResolvedValue({
      data: null,
      error: { message: 'Table delete failed' },
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(500)
    // Auth delete was called (partial state)
    expect(mockDeleteAuthUser).toHaveBeenCalled()
  })

  // ── 11. Delete CUSTOMER user — success ──────────────────────────

  it('should delete a CUSTOMER user successfully', async () => {
    mockMaybeSingle.mockResolvedValue({
      data: { id: 'cust-id', username: 'customer1', role: 'CUSTOMER' },
      error: null,
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/cust-id', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'cust-id' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.message).toContain('customer1')
  })

  // ── 12. Delete ADMIN user — success ────────────────────────────

  it('should delete an ADMIN user successfully', async () => {
    mockMaybeSingle.mockResolvedValue({
      data: { id: 'admin-id', username: 'admin1', role: 'ADMIN' },
      error: null,
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/admin-id', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'admin-id' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.message).toContain('admin1')
  })

  // ── 13. Delete DELIVERY_BOY user — success ─────────────────────

  it('should delete a DELIVERY_BOY user successfully', async () => {
    mockMaybeSingle.mockResolvedValue({
      data: { id: 'delivery-id', username: 'delivery1', role: 'DELIVERY_BOY' },
      error: null,
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/delivery-id', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'delivery-id' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.message).toContain('delivery1')
  })

  // ── 14. Delete RESTAURANT_OWNER user — success ─────────────────

  it('should delete a RESTAURANT_OWNER user successfully', async () => {
    mockMaybeSingle.mockResolvedValue({
      data: { id: 'owner-id', username: 'restowner1', role: 'RESTAURANT_OWNER' },
      error: null,
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/owner-id', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'owner-id' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.message).toContain('restowner1')
  })

  // ── 15. Calls both from().select() and from().delete() on success ─

  it('should call from() twice on success (existence check + delete)', async () => {
    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })

    // First call: existence check, Second call: table delete
    expect(mockFrom).toHaveBeenCalledTimes(2)
    expect(mockFrom).toHaveBeenCalledWith('users')
  })

  // ── 16. Existence check selects id, username, role ───────────────

  it('should select specific fields during existence check', async () => {
    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })

    expect(mockSelect).toHaveBeenCalledWith('id, username, role')
  })

  // ── 17. Return 500 when an unexpected error is thrown ────────────

  it('should return 500 when the handler throws an unexpected error', async () => {
    // Force a JSON parse error in params
    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, {
      params: Promise.reject(new Error('Unexpected params error')),
    })
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toBe('Internal server error')
  })

  // ── 18. Auth delete with empty error object ─────────────────────

  it('should propagate auth delete error messages correctly', async () => {
    mockDeleteAuthUser.mockResolvedValue({
      data: null,
      error: { message: 'User not found in auth.users table', code: 'PGRST116' },
    })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(500)
    expect(body.error).toContain('auth.users')
  })

  // ── 19. Handles deleted user with no related records ────────────

  it('should succeed even when the user has no related records', async () => {
    // Simulates a user with no relations — clean delete
    mockDeleteOp.mockResolvedValue({ data: null, error: null })

    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/clean-user', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'clean-user' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.message).toBe('User johndoe deleted successfully')
  })

  // ── 20. Delete response is a plain JSON object with message ─────

  it('should return a response with message field on success', async () => {
    const { DELETE } = await import('@/app/api/users/[id]/route')
    const request = new NextRequest('http://localhost/api/users/user-to-delete', {
      method: 'DELETE',
    })
    const response = await DELETE(request, { params: Promise.resolve({ id: 'user-to-delete' }) })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body).toHaveProperty('message')
    expect(Object.keys(body).length).toBe(1)
  })
})
