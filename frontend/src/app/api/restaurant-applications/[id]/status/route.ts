import { NextRequest, NextResponse } from 'next/server'

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:5000'

// PATCH /api/restaurant-applications/[id]/status — approve/reject application (proxied to backend)
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params
    const body: { status: string } = await request.json()
    const { status } = body

    const validStatuses = ['APPROVED', 'REJECTED']
    if (!validStatuses.includes(status)) {
      return NextResponse.json(
        { error: `Status must be one of: ${validStatuses.join(', ')}` },
        { status: 400 },
      )
    }

    const res = await fetch(`${BACKEND_URL}/api/restaurant-applications/${id}/status`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status }),
      cache: 'no-store',
    })

    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      return NextResponse.json(
        { error: data.error || 'Failed to update application status' },
        { status: res.status },
      )
    }

    const data = await res.json()
    return NextResponse.json(data)
  } catch (error) {
    console.error('Failed to update restaurant application status:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}
