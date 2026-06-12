import { NextResponse } from 'next/server'

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:5000'

// GET /api/restaurant-applications — list all applications (proxied to backend)
export async function GET() {
  try {
    const res = await fetch(`${BACKEND_URL}/api/restaurant-applications`, {
      headers: { 'Content-Type': 'application/json' },
      cache: 'no-store',
    })

    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      console.error('Failed to fetch restaurant applications:', data.error || res.statusText)
      return NextResponse.json([])
    }

    const data = await res.json()
    // Ensure we always return an array
    return NextResponse.json(Array.isArray(data) ? data : [])
  } catch (error) {
    console.error('Failed to fetch restaurant applications:', error)
    return NextResponse.json([])
  }
}
