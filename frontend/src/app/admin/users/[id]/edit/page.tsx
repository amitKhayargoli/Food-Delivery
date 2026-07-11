'use client'

import { useEffect, useState } from 'react'
import { useRouter, useParams } from 'next/navigation'
import Link from 'next/link'
import type { UserRecord, AppRole } from '@/lib/types'

const roles: { value: AppRole; label: string }[] = [
  { value: 'CUSTOMER', label: 'Customer' },
  { value: 'DELIVERY_BOY', label: 'Delivery Boy' },
  { value: 'RESTAURANT_OWNER', label: 'Restaurant Owner' },
  { value: 'ADMIN', label: 'Admin' },
]

const statuses: { value: string; label: string }[] = [
  { value: 'ACTIVE', label: 'Active' },
  { value: 'INACTIVE', label: 'Inactive' },
  { value: 'SUSPENDED', label: 'Suspended' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'REJECTED', label: 'Rejected' },
]

export default function EditUserPage() {
  const router = useRouter()
  const params = useParams()
  const userId = params.id as string

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [form, setForm] = useState({
    username: '',
    email: '',
    phone: '',
    role: 'CUSTOMER' as AppRole,
    status: 'ACTIVE' as string,
  })

  // Fetch existing user data
  useEffect(() => {
    fetch(`/api/users/${userId}`)
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load user')
        return res.json()
      })
      .then((user: UserRecord) => {
        setForm({
          username: user.username,
          email: user.email,
          phone: user.phone || '',
          role: user.role,
          status: user.status,
        })
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }, [userId])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSaving(true)

    try {
      const res = await fetch(`/api/users/${userId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })

      const data = await res.json()

      if (!res.ok) {
        setError(data.error || 'Failed to update user')
        return
      }

      setSuccess(true)
      setTimeout(() => router.push('/admin/users'), 1500)
    } catch (err: any) {
      setError(err.message || 'An unexpected error occurred')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <span className="loading loading-spinner loading-lg text-primary" />
      </div>
    )
  }

  if (success) {
    return (
      <div className="flex flex-col items-center justify-center h-64">
        <div className="w-16 h-16 rounded-full bg-success/20 flex items-center justify-center mb-4">
          <span className="text-3xl text-success">✓</span>
        </div>
        <h2 className="text-xl font-bold text-base-content">User Updated Successfully</h2>
        <p className="text-sm text-base-content/60 mt-2">Redirecting to users list...</p>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto">
      <div className="mb-6">
        <Link href="/admin/users" className="link link-hover text-sm text-base-content/60">
          ← Back to Users
        </Link>
        <h2 className="text-2xl font-bold text-base-content mt-2">Edit User</h2>
        <p className="text-sm text-base-content/60 mt-1">
          Update user details, role, or status
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-6">
        {error && (
          <div role="alert" className="alert alert-error">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span>{error}</span>
          </div>
        )}

        {/* Username & Email */}
        <div className="grid grid-cols-2 gap-4">
          <label className="form-control">
            <div className="label">
              <span className="label-text">Username *</span>
            </div>
            <input
              type="text"
              required
              value={form.username}
              onChange={(e) => setForm({ ...form, username: e.target.value })}
              className="input input-bordered"
            />
          </label>
          <label className="form-control">
            <div className="label">
              <span className="label-text">Email *</span>
            </div>
            <input
              type="email"
              required
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              className="input input-bordered"
            />
          </label>
        </div>

        {/* Phone */}
        <label className="form-control">
          <div className="label">
            <span className="label-text">Phone</span>
          </div>
          <input
            type="tel"
            value={form.phone}
            onChange={(e) => setForm({ ...form, phone: e.target.value })}
            className="input input-bordered"
          />
        </label>

        {/* Role & Status */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="label">
              <span className="label-text">Role *</span>
            </label>
            <select
              value={form.role}
              onChange={(e) => setForm({ ...form, role: e.target.value as AppRole })}
              className="select select-bordered w-full"
            >
              {roles.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="label">
              <span className="label-text">Status *</span>
            </label>
            <select
              value={form.status}
              onChange={(e) => setForm({ ...form, status: e.target.value })}
              className="select select-bordered w-full"
            >
              {statuses.map((s) => (
                <option key={s.value} value={s.value}>{s.label}</option>
              ))}
            </select>
          </div>
        </div>

        {/* Submit */}
        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={saving}
            className="btn btn-primary flex-1"
          >
            {saving ? <span className="loading loading-spinner" /> : 'Save Changes'}
          </button>
          <Link
            href="/admin/users"
            className="btn btn-ghost"
          >
            Cancel
          </Link>
        </div>
      </form>
    </div>
  )
}
