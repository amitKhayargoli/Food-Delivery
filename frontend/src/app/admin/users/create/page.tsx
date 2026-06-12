'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import type { AppRole } from '@/lib/types'

const roles: { value: AppRole; label: string; description: string }[] = [
  { value: 'CUSTOMER', label: 'Customer', description: 'End user who orders food' },
  { value: 'DELIVERY_BOY', label: 'Delivery Boy', description: 'Delivers orders to customers' },
  { value: 'RESTAURANT_OWNER', label: 'Restaurant Owner', description: 'Manages restaurant & menu' },
  { value: 'ADMIN', label: 'Admin', description: 'Superadmin with full access' },
]

export default function CreateUserPage() {
  const router = useRouter()
  const [form, setForm] = useState({
    username: '',
    email: '',
    phone: '',
    password: '',
    role: 'CUSTOMER' as AppRole,
  })
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [submitting, setSubmitting] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      const res = await fetch('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })

      const data = await res.json()

      if (!res.ok) {
        setError(data.error || 'Failed to create user')
        return
      }

      setSuccess(true)
      setTimeout(() => router.push('/admin/users'), 1500)
    } catch (err: any) {
      setError(err.message || 'An unexpected error occurred')
    } finally {
      setSubmitting(false)
    }
  }

  if (success) {
    return (
      <div className="flex flex-col items-center justify-center h-64">
        <div className="w-16 h-16 rounded-full bg-success/20 flex items-center justify-center mb-4">
          <span className="text-3xl text-success">✓</span>
        </div>
        <h2 className="text-xl font-bold text-base-content">User Created Successfully</h2>
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
        <h2 className="text-2xl font-bold text-base-content mt-2">Create User</h2>
        <p className="text-sm text-base-content/60 mt-1">
          Create a new user account with a specific role
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
              placeholder="johndoe"
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
              placeholder="john@example.com"
            />
          </label>
        </div>

        {/* Phone & Password */}
        <div className="grid grid-cols-2 gap-4">
          <label className="form-control">
            <div className="label">
              <span className="label-text">Phone</span>
            </div>
            <input
              type="tel"
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
              className="input input-bordered"
              placeholder="9800000000"
            />
          </label>
          <label className="form-control">
            <div className="label">
              <span className="label-text">Password *</span>
            </div>
            <input
              type="password"
              required
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              className="input input-bordered"
              placeholder="Minimum 6 characters"
              minLength={6}
            />
          </label>
        </div>

        {/* Role Selection */}
        <div>
          <label className="label">
            <span className="label-text">Role *</span>
          </label>
          <div className="grid grid-cols-2 gap-3">
            {roles.map((r) => (
              <button
                key={r.value}
                type="button"
                onClick={() => setForm({ ...form, role: r.value })}
                className={`card border-2 text-left transition-all p-4 ${
                  form.role === r.value
                    ? 'border-primary bg-primary/5'
                    : 'border-base-300 hover:border-base-content/30'
                }`}
              >
                <p className="font-semibold text-sm text-base-content">{r.label}</p>
                <p className="text-xs text-base-content/50 mt-0.5">{r.description}</p>
              </button>
            ))}
          </div>
        </div>

        {/* Submit */}
        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={submitting}
            className="btn btn-primary flex-1"
          >
            {submitting ? <span className="loading loading-spinner" /> : 'Create User'}
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
