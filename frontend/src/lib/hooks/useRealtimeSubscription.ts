'use client'

import { useEffect, useRef } from 'react'
import { supabase } from '@/lib/supabase'

type RealtimeEvent = '*' | 'INSERT' | 'UPDATE' | 'DELETE'

/**
 * Subscribe to Supabase Realtime changes on a table and call onChange
 * whenever a matching event occurs. Handles cleanup automatically.
 *
 * Also supports a fallback poll interval (in ms) so data refreshes even
 * when RLS blocks the Realtime broadcast – once you grant the anon role
 * SELECT on the table, the live subscription will take over seamlessly.
 */
export function useRealtimeSubscription(
  table: string,
  event: RealtimeEvent,
  onChange: () => void,
  pollIntervalMs?: number,
) {
  // Keep a ref so we never need to re-subscribe just because the
  // callback identity changed.
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange

  useEffect(() => {
    console.log(`[RT-ADMIN] 🔌 Subscribing to ${table} (${event})...`)

    const channel = supabase
      .channel(`admin-${table}-changes`)
      .on(
        'postgres_changes',
        { event, schema: 'public', table },
        () => {
          console.log(`[RT-ADMIN] 🔄 ${table} changed – refreshing...`)
          onChangeRef.current()
        },
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log(`[RT-ADMIN] ✅ Realtime subscribed to ${table}`)
        } else if (status === 'CHANNEL_ERROR') {
          console.log(
            `[RT-ADMIN] ⚠️ Realtime subscription error for ${table} – RLS may be blocking.` +
            ` Using fallback poll every ${pollIntervalMs || 'N/A'}ms instead.`,
          )
        }
      })

    // Fallback polling interval so the page stays up-to-date even
    // when the Realtime broadcast is blocked by RLS.
    const interval = pollIntervalMs
      ? setInterval(() => {
          console.log(`[RT-ADMIN] ⏱ Polling ${table}...`)
          onChangeRef.current()
        }, pollIntervalMs)
      : undefined

    return () => {
      console.log(`[RT-ADMIN] ⏹ Unsubscribing from ${table}`)
      supabase.removeChannel(channel)
      if (interval !== undefined) clearInterval(interval)
    }
  }, [table, event, pollIntervalMs])
}
