'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import type { UserRecord, AppRole } from '@/lib/types'

export default function UsersPage() {
  const [users, setUsers] = useState<UserRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [roleFilter, setRoleFilter] = useState<string>('')
  const [deleteTarget, setDeleteTarget] = useState<{ id: string; username: string } | null>(null)
  const [deleting, setDeleting] = useState<string | null>(null)

  const fetchUsers = () => {
    setLoading(true)
    fetch('/api/users')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to fetch users')
        return res.json()
      })
      .then((data) => setUsers(data))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }

  useEffect(() => { fetchUsers() }, [])

  const handleDelete = async () => {
    if (!deleteTarget) return
    const { id } = deleteTarget
    setDeleteTarget(null)
    setDeleting(id)
    setError(null)

    try {
      const res = await fetch(`/api/users/${id}`, { method: 'DELETE' })
      const data = await res.json()

      if (!res.ok) {
        throw new Error(data.error || 'Failed to delete user')
      }

      setUsers((prev) => prev.filter((u) => u.id !== id))
    } catch (err: any) {
      setError(err.message || 'An unexpected error occurred')
    } finally {
      setDeleting(null)
    }
  }

  const filtered = users.filter((u) => {
    const q = search.toLowerCase()
    const matchesSearch =
      !q ||
      u.username.toLowerCase().includes(q) ||
      u.email.toLowerCase().includes(q) ||
      (u.phone && u.phone.includes(q))
    const matchesRole = !roleFilter || u.role === roleFilter
    return matchesSearch && matchesRole
  })

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-base-content">Users</h2>
          <p className="text-sm text-base-content/60 mt-1">
            {users.length} total user{users.length !== 1 ? 's' : ''}
          </p>
        </div>
        <Link
          href="/admin/users/create"
          className="btn btn-primary"
        >
          + Create User
        </Link>
      </div>

      {/* Filters */}
      <div className="flex gap-3">
        <label className="input input-bordered flex items-center gap-2 flex-1">
          <svg className="w-4 h-4 opacity-60" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input
            type="text"
            placeholder="Search by username, email, or phone..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="grow"
          />
        </label>
        <select
          value={roleFilter}
          onChange={(e) => setRoleFilter(e.target.value)}
          className="select select-bordered w-44"
        >
          <option value="">All Roles</option>
          <option value="CUSTOMER">Customer</option>
          <option value="DELIVERY_BOY">Delivery Boy</option>
          <option value="RESTAURANT_OWNER">Restaurant Owner</option>
          <option value="ADMIN">Admin</option>
        </select>
      </div>

      {/* Error */}
      {error && (
        <div role="alert" className="alert alert-error">
          <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span>{error}</span>
        </div>
      )}

      {/* Delete confirmation modal */}
      <dialog className={`modal ${deleteTarget ? 'modal-open' : ''}`}>
        <div className="modal-box">
          <h3 className="font-bold text-lg">Delete User</h3>
          <p className="py-2 text-base-content/70">
            Are you sure you want to delete <strong>{deleteTarget?.username}</strong>?
          </p>
          <p className="text-sm text-error/80">
            This action cannot be undone. The user will be permanently removed from both auth and the users table.
          </p>
          <div className="modal-action">
            <button className="btn btn-ghost" onClick={() => setDeleteTarget(null)}>
              Cancel
            </button>
            <button
              className="btn btn-error"
              onClick={handleDelete}
              disabled={deleting === deleteTarget?.id}
            >
              {deleting === deleteTarget?.id ? (
                <span className="loading loading-spinner loading-xs" />
              ) : (
                'Delete'
              )}
            </button>
          </div>
        </div>
        <form method="dialog" className="modal-backdrop">
          <button onClick={() => setDeleteTarget(null)}>close</button>
        </form>
      </dialog>

      {/* Loading */}
      {loading && (
        <div className="flex items-center justify-center h-48">
          <span className="loading loading-spinner loading-lg text-primary" />
        </div>
      )}

      {/* Table */}
      {!loading && !error && (
        <div className="overflow-x-auto card bg-base-100 border border-base-200">
          <table className="table">
            <thead>
              <tr>
                <th>Username</th>
                <th>Email</th>
                <th>Phone</th>
                <th>Role</th>
                <th>Status</th>
                <th>Created</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={7} className="text-center py-12 text-base-content/40">
                    No users found
                  </td>
                </tr>
              ) : (
                filtered.map((user) => (
                  <tr key={user.id} className="hover">
                    <td className="font-medium">{user.username}</td>
                    <td className="text-sm text-base-content/60">{user.email}</td>
                    <td className="text-sm text-base-content/50">{user.phone || '—'}</td>
                    <td>
                      <span className={`badge px-3 py-1 rounded-full ${
                        user.role === 'ADMIN' ? 'badge-error' :
                        user.role === 'DELIVERY_BOY' ? 'badge-secondary' :
                        user.role === 'RESTAURANT_OWNER' ? 'badge-warning' :
                        'badge-success'
                      }`}>
                        {user.role}
                      </span>
                    </td>
                    <td>
                      <div className="flex items-center gap-2">
                        <span className={`w-2 h-2 rounded-full ${
                          user.status === 'ACTIVE' ? 'bg-success' :
                          user.status === 'INACTIVE' ? 'bg-gray-400' :
                          user.status === 'SUSPENDED' ? 'bg-error' :
                          user.status === 'PENDING' ? 'bg-warning' :
                          user.status === 'REJECTED' ? 'bg-rose-500' :
                          'bg-gray-400'
                        }`} />
                        <span className="text-sm">{user.status}</span>
                      </div>
                    </td>
                    <td className="text-sm text-base-content/50">
                      {new Date(user.created_at).toLocaleDateString()}
                    </td>
                    <td>
                      <div className="flex items-center gap-1">
                        <Link
                          href={`/admin/users/${user.id}/edit`}
                          className="btn btn-ghost btn-sm"
                        >
                          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                          </svg>
                          Edit
                        </Link>
                        <button
                          className="btn btn-ghost btn-sm text-error"
                          onClick={() => setDeleteTarget({ id: user.id, username: user.username })}
                          disabled={deleting === user.id}
                        >
                          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                          </svg>
                          {deleting === user.id ? <span className="loading loading-spinner loading-xs" /> : 'Delete'}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
