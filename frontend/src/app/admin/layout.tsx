'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ReactNode, useEffect, useState } from 'react'
import Image from 'next/image'
import { LayoutDashboard, CheckCircle, Users } from 'lucide-react'
import ThemeSwitcher from '@/components/ThemeSwitcher'
import { UserRecord } from '@/lib/types'

const navItems = [
  { href: '/admin', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/admin/approvals', label: 'Approvals', icon: CheckCircle },
  { href: '/admin/users', label: 'Users', icon: Users },
]
  
export default function AdminLayout({ children }: { children: ReactNode }) {
  const pathname = usePathname()

  const [users, setUsers] = useState<UserRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch('/api/users')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load users')
        return res.json()
      })
      .then((data) => setUsers(data))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }, [])


  return (
    <div className="drawer lg:drawer-open">
      <input id="admin-drawer" type="checkbox" className="drawer-toggle" />

      {/* Main content */}
      <div className="drawer-content flex flex-col">
        {/* Top navbar */}
        <div className="navbar bg-base-100 px-4 lg:px-6 min-h-16">
          <div className="flex-none lg:hidden">
            <label htmlFor="admin-drawer" className="btn btn-square btn-ghost">
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            </label>
          </div>

          <div className="flex-1" />

          <div className="flex-none flex items-center gap-3">
            <ThemeSwitcher />
           
          </div>
        </div>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto p-4 lg:p-6">
          {children}
        </main>
      </div>

      {/* Sidebar */}
      <div className="drawer-side z-40 border-r border-base-200">
        <label htmlFor="admin-drawer" className="drawer-overlay" />

        <aside className="bg-base-100 w-54 min-h-full flex flex-col">
          {/* Brand */}
          <div className="flex items-center gap-2 px h-16">
            <Image
              src="/logo.png"
              alt="Dailo"
              width={200}
              height={120}
              className="object-contain"
            />
          </div>

          {/* Navigation */}
          <nav className="flex-1 py-4 px-6">
            <ul className="menu menu-md gap-1">
              {navItems.map((item) => {
                const IconComponent = item.icon
                const isActive = pathname === item.href || (item.href !== '/admin' && pathname.startsWith(item.href))
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      className={`${isActive ? 'active font-semibold bg-primary/10 text-primary' : 'font-medium'} rounded-lg`}
                    >
                      <IconComponent className={`w-5 h-5 ${isActive ? 'text-primary' : ''}`} />
                      {item.label}
                    </Link>
                  </li>
                )
              })}
            </ul>
          </nav>
        </aside>
      </div>
    </div>
  )
}
