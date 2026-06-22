'use client'

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import type { UserRecord } from '@/lib/types'
import { useRealtimeSubscription } from '@/lib/hooks/useRealtimeSubscription'

export default function AdminDashboard() {
  const [users, setUsers] = useState<UserRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchUsers = useCallback(() => {
    return fetch('/api/users')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load users')
        return res.json()
      })
      .then((data) => setUsers(data))
      .catch((err) => setError(err.message))
  }, [])

  useEffect(() => {
    setLoading(true)
    fetchUsers().finally(() => setLoading(false))
  }, [fetchUsers])

  // Auto-refresh when users table changes (falls back to 10s poll)
  useRealtimeSubscription('users', '*', fetchUsers, 10_000)

  const roleCounts = users.reduce(
    (acc, u) => {
      acc[u.role] = (acc[u.role] || 0) + 1
      return acc
    },
    {} as Record<string, number>,
  )

  const statusCounts = users.reduce(
    (acc, u) => {
      acc[u.status] = (acc[u.status] || 0) + 1
      return acc
    },
    {} as Record<string, number>,
  )

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <span className="loading loading-spinner loading-lg text-primary" />
      </div>
    )
  }

  if (error) {
    return (
      <div role="alert" className="alert alert-error">
        <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <span>Failed to load dashboard: {error}</span>
      </div>
    )
  }

  const pendingCount = statusCounts['PENDING'] || 0

  const statCards = [
    { label: 'Total Users', value: users.length, classes: 'bg-info/10 text-info' },
    { label: 'Customers', value: roleCounts['CUSTOMER'] || 0, classes: 'bg-success/10 text-success' },
    { label: 'Delivery Boys', value: roleCounts['DELIVERY_BOY'] || 0, classes: 'bg-secondary/10 text-secondary' },
    { label: 'Restaurant Owners', value: roleCounts['RESTAURANT_OWNER'] || 0, classes: 'bg-warning/10 text-warning' },
    { label: 'Active', value: statusCounts['ACTIVE'] || 0, classes: 'bg-emerald-100/50 text-emerald-700' },
  ]

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-base-content">Dashboard Overview</h2>
          <p className="text-sm text-base-content/60 mt-1">User management summary</p>
        </div>
        <Link
          href="/admin/users/create"
          className="btn btn-primary"
        >
          + Create User
        </Link>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        {statCards.map((card) => (
          <div key={card.label} className={`card rounded-xl p-5 ${card.classes}`}>
            <p className="text-3xl font-bold">{card.value}</p>
            <p className="text-sm font-medium mt-1 opacity-80">{card.label}</p>
          </div>
        ))}
        <Link
          href="/admin/approvals"
          className={`card rounded-xl p-5 ${pendingCount > 0 ? 'bg-warning/10 text-warning ring-2 ring-warning/40' : 'bg-base-200 text-base-content/50'}`}
        >
          <p className="text-3xl font-bold">{pendingCount}</p>
          <p className="text-sm font-medium mt-1 opacity-80">Pending Approval</p>
        </Link>
      </div>

      {/* Recent users */}
      <div className="card bg-base-100 border border-base-200">
        <div className="card-body p-5">
          <h3 className="card-title text-base-content">Recent Users</h3>
          <div className="overflow-x-auto">
            <table className="table table-sm">
              <thead>
                <tr>
                  <th>Username</th>
                  <th>Email</th>
                  <th>Role</th>
                </tr>
              </thead>
              <tbody>
                {users.slice(0, 5).map((user) => (
                  <tr key={user.id} className="hover">
                    <td className="font-medium">{user.username}</td>
                    <td className="text-base-content/60 text-sm">{user.email}</td>
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
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
