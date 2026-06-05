'use client'

import { useEffect, useState } from 'react'

const themes = [
  { value: 'dailo', label: 'Dailo Light', icon: '🔴' },
  { value: 'dailo-dark', label: 'Dailo Dark', icon: '🌙' },
  { value: 'light', label: 'Light', icon: '☀️' },
  { value: 'dark', label: 'Dark', icon: '🌚' },
  { value: 'cupcake', label: 'Cupcake', icon: '🧁' },
  { value: 'synthwave', label: 'Synthwave', icon: '🌴' },
  { value: 'retro', label: 'Retro', icon: '📼' },
  { value: 'autumn', label: 'Autumn', icon: '🍂' },
  { value: 'luxury', label: 'Luxury', icon: '💎' },
  { value: 'coffee', label: 'Coffee', icon: '☕' },
  { value: 'dim', label: 'Dim', icon: '🌆' },
  { value: 'night', label: 'Night', icon: '🌃' },
]

export default function ThemeSwitcher() {
  const [currentTheme, setCurrentTheme] = useState('dailo')

  useEffect(() => {
    const saved = localStorage.getItem('theme') || 'dailo'
    setCurrentTheme(saved)
    document.documentElement.setAttribute('data-theme', saved)
  }, [])

  const activeTheme = themes.find((t) => t.value === currentTheme)

  return (
    <div className="dropdown dropdown-end">
      <label tabIndex={0} className="btn btn-ghost btn-sm gap-2">
        <span className="text-base">{activeTheme?.icon || '🔴'}</span>
        <span className="hidden sm:inline text-sm">{activeTheme?.label || 'Dailo Light'}</span>
        <svg className="w-4 h-4 opacity-60" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </label>
      <ul tabIndex={0} className="dropdown-content menu menu-sm bg-base-200 rounded-box z-50 w-48 p-2 shadow-lg">
        {themes.map((theme) => (
          <li key={theme.value}>
            <button
              type="button"
              onClick={() => {
                setCurrentTheme(theme.value)
                document.documentElement.setAttribute('data-theme', theme.value)
                localStorage.setItem('theme', theme.value)
              }}
              className={`flex items-center gap-3 ${currentTheme === theme.value ? 'active' : ''}`}
            >
              <span className="text-lg">{theme.icon}</span>
              <span>{theme.label}</span>
              {currentTheme === theme.value && (
                <svg className="w-4 h-4 ml-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              )}
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
