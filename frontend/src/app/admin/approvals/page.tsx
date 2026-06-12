'use client'

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import Lottie from 'lottie-react'
import type { UserRecord } from '@/lib/types'
import doneAnimation from '@/lib/done.json'

interface RestaurantApplication {
  id: string
  user_id: string
  restaurant_name: string
  owner_name: string
  phone: string
  email: string
  address: string
  pan_number: string
  pan_certificate_url: string
  description: string | null
  logo_url: string | null
  cover_image_url: string | null
  opening_hours: string | null
  open_time: string | null
  close_time: string | null
  cuisine_type: string | null
  status: string
  created_at: string
  reviewed_at: string | null
  users: { username: string; email: string; phone: string } | null
}

function formatTime(time: string): string {
  const [h, m] = time.split(':')
  const hour = parseInt(h, 10)
  const minute = parseInt(m, 10)
  const period = hour >= 12 ? 'PM' : 'AM'
  const hour12 = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour
  const minuteStr = minute.toString().padStart(2, '0')
  return `${hour12}:${minuteStr} ${period}`
}

type TabType = 'users' | 'restaurants'

export default function ApprovalsPage() {
  const [activeTab, setActiveTab] = useState<TabType>('users')
  const [pendingUsers, setPendingUsers] = useState<UserRecord[]>([])
  const [applications, setApplications] = useState<RestaurantApplication[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [actionLoading, setActionLoading] = useState<string | null>(null)

  const [confirmTarget, setConfirmTarget] = useState<{
    id: string
    type: 'user' | 'restaurant'
    action: 'approve' | 'reject'
    name: string
  } | null>(null)

  const fetchPending = useCallback(() => {
    setLoading(true)
    setError(null)
    Promise.all([
      fetch('/api/users').then((r) => r.json()),
      fetch('/api/restaurant-applications').then((r) => r.json()),
    ])
      .then(([usersData, appsData]) => {
        // Surface API error messages in the UI instead of silently failing
        const apiError =
          (!Array.isArray(usersData) && (usersData as any)?.error) ||
          (!Array.isArray(appsData) && (appsData as any)?.error)
        if (apiError) setError(apiError)

        setPendingUsers(
          Array.isArray(usersData)
            ? (usersData as UserRecord[]).filter((u) => u.status === 'PENDING')
            : [],
        )
        setApplications(
          Array.isArray(appsData)
            ? (appsData as RestaurantApplication[]).filter((a) => a.status === 'PENDING')
            : [],
        )
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => { fetchPending() }, [fetchPending])

  const handleUserAction = async (id: string, status: 'ACTIVE' | 'REJECTED') => {
    setConfirmTarget(null)
    setActionLoading(id)
    setError(null)
    try {
      const res = await fetch(`/api/users/${id}/status`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status }),
      })
      if (!res.ok) {
        const data = await res.json()
        throw new Error(data.error || 'Failed to update status')
      }
      setPendingUsers((prev) => prev.filter((u) => u.id !== id))
    } catch (err: any) {
      setError(err.message)
    } finally {
      setActionLoading(null)
    }
  }

  const handleApplicationAction = async (id: string, status: 'APPROVED' | 'REJECTED') => {
    setConfirmTarget(null)
    setActionLoading(id)
    setError(null)
    try {
      const res = await fetch(`/api/restaurant-applications/${id}/status`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status }),
      })
      if (!res.ok) {
        const data = await res.json()
        throw new Error(data.error || 'Failed to update application')
      }
      setApplications((prev) => prev.filter((a) => a.id !== id))
    } catch (err: any) {
      setError(err.message)
    } finally {
      setActionLoading(null)
    }
  }

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-base-content">Approvals</h2>
          <p className="text-sm text-base-content/60 mt-1">
            Review pending users and restaurant applications
          </p>
        </div>
      </div>

      {/* Tabs */}
      <div role="tablist" className="tabs tabs-boxed">
        <button
          role="tab"
          className={`tab ${activeTab === 'users' ? 'tab-active' : ''}`}
          onClick={() => setActiveTab('users')}
        >
          Users ({pendingUsers.length})
        </button>
        <button
          role="tab"
          className={`tab ${activeTab === 'restaurants' ? 'tab-active' : ''}`}
          onClick={() => setActiveTab('restaurants')}
        >
          Restaurant Applications ({applications.length})
        </button>
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

      {/* Confirmation modal */}
      <dialog className={`modal ${confirmTarget ? 'modal-open' : ''}`}>
        <div className="modal-box">
          <h3 className="font-bold text-lg">
            {confirmTarget?.action === 'approve' ? 'Approve?' : 'Reject?'}
          </h3>
          <p className="py-2 text-base-content/70">
            {confirmTarget?.action === 'approve'
              ? `This will approve "${confirmTarget?.name}".`
              : `This will reject "${confirmTarget?.name}".`}
          </p>
          {confirmTarget?.type === 'restaurant' && confirmTarget?.action === 'approve' && (
            <p className="text-sm text-amber-600">
              The user&apos;s role will be upgraded to Restaurant Owner.
            </p>
          )}
          <div className="modal-action">
            <button className="btn btn-ghost" onClick={() => setConfirmTarget(null)}>
              Cancel
            </button>
            <button
              className={`btn ${confirmTarget?.action === 'approve' ? 'btn-success' : 'btn-error'}`}
              onClick={() => {
                if (!confirmTarget) return
                if (confirmTarget.type === 'user') {
                  handleUserAction(
                    confirmTarget.id,
                    confirmTarget.action === 'approve' ? 'ACTIVE' : 'REJECTED',
                  )
                } else {
                  handleApplicationAction(
                    confirmTarget.id,
                    confirmTarget.action === 'approve' ? 'APPROVED' : 'REJECTED',
                  )
                }
              }}
            >
              {confirmTarget?.action === 'approve' ? 'Approve' : 'Reject'}
            </button>
          </div>
        </div>
        <form method="dialog" className="modal-backdrop">
          <button onClick={() => setConfirmTarget(null)}>close</button>
        </form>
      </dialog>

      {/* Loading */}
      {loading && (
        <div className="flex items-center justify-center h-48">
          <span className="loading loading-spinner loading-lg text-primary" />
        </div>
      )}

      {/* ─── USERS TAB ─── */}
      {!loading && activeTab === 'users' && (
        <>
          {pendingUsers.length === 0 ? (
            <div className="card bg-base-100 border border-base-200">
              <div className="card-body items-center py-16">
                <div className="w-60 h-60 mb-2">
                  <Lottie animationData={doneAnimation} loop={false} />
                </div> 
                <h3 className="card-title text-lg">All Caught Up</h3>
                <p className="text-sm text-base-content/60">No pending users to review right now.</p>
                <Link href="/admin/users/create" className="btn btn-primary mt-4">
                  + Create New User
                </Link>
              </div>
            </div>
          ) : (
            <div className="space-y-3">
              {pendingUsers.map((user) => (
                <div key={user.id} className="card card-side bg-base-100 border border-warning/30 items-center p-4">
                  <div className="avatar placeholder">
                    <div className="w-10 rounded-full bg-warning text-warning-content">
                      <span className="font-semibold">{user.username.charAt(0).toUpperCase()}</span>
                    </div>
                  </div>
                  <div className="flex-1 ml-4">
                    <div className="flex items-center gap-2 flex-wrap">
                      <p className="font-semibold text-base-content">{user.username}</p>
                      <span className={`badge badge-sm px-3 rounded-full ${
                        user.role === 'ADMIN' ? 'badge-error' :
                        user.role === 'DELIVERY_BOY' ? 'badge-secondary' :
                        user.role === 'RESTAURANT_OWNER' ? 'badge-warning' :
                        'badge-success'
                      }`}>
                        {user.role}
                      </span>
                      <span className="badge badge-sm badge-warning px-3 rounded-full">PENDING</span>
                    </div>
                    <p className="text-xs text-base-content/60 mt-0.5">{user.email}</p>
                    <p className="text-xs text-base-content/40 mt-0.5">
                      Created {new Date(user.created_at).toLocaleDateString()}
                      {user.phone ? ` · ${user.phone}` : ''}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      className="btn btn-success btn-sm"
                      onClick={() =>
                        setConfirmTarget({
                          id: user.id,
                          type: 'user',
                          action: 'approve',
                          name: user.username,
                        })
                      }
                      disabled={actionLoading === user.id}
                    >
                      {actionLoading === user.id ? <span className="loading loading-spinner loading-xs" /> : 'Approve'}
                    </button>
                    <button
                      className="btn btn-ghost btn-sm text-error"
                      onClick={() =>
                        setConfirmTarget({
                          id: user.id,
                          type: 'user',
                          action: 'reject',
                          name: user.username,
                        })
                      }
                      disabled={actionLoading === user.id}
                    >
                      Reject
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      {/* ─── RESTAURANT APPLICATIONS TAB ─── */}
      {!loading && activeTab === 'restaurants' && (
        <>
          {applications.length === 0 ? (
            <div className="card bg-base-100 border border-base-200">
              <div className="card-body items-center py-16">
                <div className="w-60 h-60 mb-2">
                  <Lottie animationData={doneAnimation} loop={false} />
                </div>
                <h3 className="card-title text-lg">No Applications</h3>
                <p className="text-sm text-base-content/60">No restaurant owner applications to review.</p>
              </div>
            </div>
          ) : (
            <div className="space-y-4">
              {applications.map((app) => (
                <div key={app.id} className="card bg-base-100 border border-warning/30">
                  <div className="card-body p-5">
                    <div className="flex items-start justify-between mb-3">
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="font-bold text-base">{app.restaurant_name}</h3>
                          <span className="badge badge-sm badge-warning">{app.status}</span>
                        </div>
                        <p className="text-xs text-base-content/60 mt-1">
                          Applied {new Date(app.created_at).toLocaleDateString()} · by{' '}
                          {app.users?.username || app.owner_name}
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <button
                          className="btn btn-success btn-sm"
                          onClick={() =>
                            setConfirmTarget({
                              id: app.id,
                              type: 'restaurant',
                              action: 'approve',
                              name: app.restaurant_name,
                            })
                          }
                          disabled={actionLoading === app.id}
                        >
                          {actionLoading === app.id ? <span className="loading loading-spinner loading-xs" /> : 'Approve'}
                        </button>
                        <button
                          className="btn btn-ghost btn-sm text-error"
                          onClick={() =>
                            setConfirmTarget({
                              id: app.id,
                              type: 'restaurant',
                              action: 'reject',
                              name: app.restaurant_name,
                            })
                          }
                          disabled={actionLoading === app.id}
                        >
                          Reject
                        </button>
                      </div>
                    </div>

                    {/* Details grid */}
                    <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
                      <div>
                        <span className="text-base-content/40">Owner:</span>{' '}
                        <span className="text-base-content/80">{app.owner_name}</span>
                      </div>
                      <div>
                        <span className="text-base-content/40">Phone:</span>{' '}
                        <span className="text-base-content/80">{app.phone}</span>
                      </div>
                      <div>
                        <span className="text-base-content/40">Email:</span>{' '}
                        <span className="text-base-content/80">{app.email}</span>
                      </div>
                      <div>
                        <span className="text-base-content/40">PAN:</span>{' '}
                        <span className="text-base-content/80">{app.pan_number}</span>
                      </div>
                      <div className="col-span-2">
                        <span className="text-base-content/40">Address:</span>{' '}
                        <span className="text-base-content/80">{app.address}</span>
                      </div>
                      {app.cuisine_type && (
                        <div>
                          <span className="text-base-content/40">Cuisine:</span>{' '}
                          <span className="text-base-content/80">{app.cuisine_type}</span>
                        </div>
                      )}
                      {(app.open_time || app.opening_hours) && (
                        <div>
                          <span className="text-base-content/40">Hours:</span>{' '}
                          <span className="text-base-content/80">
                            {app.open_time && app.close_time
                              ? `${formatTime(app.open_time)} - ${formatTime(app.close_time)}`
                              : app.opening_hours}
                          </span>
                        </div>
                      )}
                      {app.description && (
                        <div className="col-span-2">
                          <span className="text-base-content/40">Description:</span>{' '}
                          <span className="text-base-content/80">{app.description}</span>
                        </div>
                      )}
                    </div>

                    {/* PAN Certificate */}
                    <div className="mt-3 pt-3 border-t border-base-200">
                      <a
                        href={app.pan_certificate_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="link link-primary text-sm flex items-center gap-2"
                      >
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                        </svg>
                        View PAN Certificate
                      </a>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}
