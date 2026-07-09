#!/usr/bin/env bash
#
# Rider Live Location Simulator
# ==============================
#
# Simulates a delivery rider moving along a path by directly updating
# the rider_locations table in Supabase. Also calls the backend API
# to transition order status at the right moments, triggering push
# notifications to the customer.
#
# Usage:
#   chmod +x simulate_rider.sh
#   ./simulate_rider.sh <RIDER_USER_ID> [start_lat start_lng]
#
# Examples:
#   ./simulate_rider.sh "abc-123-def-456"
#   ./simulate_rider.sh "abc-123-def-456" 27.6805 85.3870
#
# Route: Byasi (near Doko Fresh Juice Corner) → Merina (dropoff)
# Order: #DAILO-Q4783 — calls backend API for status transitions
# Press Ctrl+C to stop.

set -euo pipefail

# ── Supabase Config ──────────────────────────────────────────────────────
SUPABASE_URL="https://hsiaguzxkytfsstvatep.supabase.co"
SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhzaWFndXp4a3l0ZnNzdHZhdGVwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTk5NDg1MCwiZXhwIjoyMDkxNTcwODUwfQ.iH43ewzN4SR45S6pw5qqke2lsGjx8IocpPatLnnyF3k"

RIDER_LOCATIONS_API="${SUPABASE_URL}/rest/v1/rider_locations"

# ── Backend API Config ──────────────────────────────────────────────────
# The backend server must be running for push notifications to fire.
BACKEND_URL="http://localhost:5000/api"

# JWT for the delivery boy (used to authenticate backend API calls)
RIDER_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjIyNDM1Y2I0LTUzYjUtNDMxNy05Njc0LTgwNmJkYjYyZmRhOSIsInJvbGUiOiJERUxJVkVSWV9CT1kiLCJpYXQiOjE3ODM1ODEyNDgsImV4cCI6MTc4NDE4NjA0OH0.FCVRPde3RJUwM7AvbC6OFXelmz6wKZ-sZZjkli1Iqw0"

# Order to manage (DAILO-Q4783)
ORDER_ID="cd0aaaf3-e981-4071-9337-d75e20d1767d"

# ── Rider ID (required) ──────────────────────────────────────────────────
if [ $# -lt 1 ]; then
  echo ""
  echo "  ⚠️  Missing rider user ID"
  echo ""
  echo "  Usage: ./simulate_rider.sh <RIDER_USER_ID> [start_lat start_lng]"
  echo ""
  echo "  Need a rider ID? Run this query in Supabase SQL Editor:"
  echo "    SELECT id, username FROM users WHERE role = 'DELIVERY_BOY' LIMIT 5;"
  echo ""
  exit 1
fi

RIDER_ID="$1"

# ── Route: Byasi → Merina ───────────────────────────────────────────────
# Byasi (near Doko Fresh Juice Corner, Bhaktapur)
START_LAT="${2:-27.6805}"
START_LNG="${3:-85.3870}"

# Merina dropoff (from order #DAILO-Q4783)
END_LAT="27.7172"
END_LNG="85.3240"

# ── Movement parameters ──────────────────────────────────────────────────
INTERVAL=5          # seconds between updates
STEPS=40            # number of steps from start to finish

# Pre-compute deltas per step
DLAT=$(awk "BEGIN { printf \"%.7f\", ($END_LAT - $START_LAT) / $STEPS }" 2>/dev/null || echo "0.0009175")
DLNG=$(awk "BEGIN { printf \"%.7f\", ($END_LNG - $START_LNG) / $STEPS }" 2>/dev/null || echo "-0.0015750")

# ── Tracking flags ───────────────────────────────────────────────────────
_HAS_PICKED_UP=false   # true once markAsPickedUp has been called
_HAS_DELIVERED=false   # true once markAsDelivered has been called

# ── Reverse geocoding (Nominatim OSM — free, no API key) ──────────────
_geocache_lat=""
_geocache_lng=""
_geocache_name=""

get_location_name() {
  local lat="$1"
  local lng="$2"

  if [ -n "$_geocache_lat" ]; then
    local dlat dlon
    dlat=$(awk "BEGIN { printf \"%.6f\", $lat - $_geocache_lat }" 2>/dev/null)
    dlon=$(awk "BEGIN { printf \"%.6f\", $lng - $_geocache_lng }" 2>/dev/null)
    if [ -n "$dlat" ] && [ -n "$dlon" ] &&
       [ "$(echo "$dlat < 0.002 && $dlat > -0.002" | bc -l 2>/dev/null || echo 0)" = "1" ] &&
       [ "$(echo "$dlon < 0.002 && $dlon > -0.002" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
      echo "$_geocache_name"
      return
    fi
  fi

  local name
  name=$(curl -s --max-time 2 \
    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=en" \
    -H "User-Agent: RiderSimulator/1.0" 2>/dev/null | \
    sed -n 's/.*"display_name":"\([^"]*\)".*/\1/p')

  if [ -n "$name" ]; then
    _geocache_lat="$lat"
    _geocache_lng="$lng"
    _geocache_name="$name"
    local short
    short=$(echo "$name" | awk -F', ' '{
      if (NF >= 2) print $1 ", " $2
      else print $1
    }')
    echo "$short"
  else
    echo "${_geocache_name:-}"
  fi
}

# ── Helper: Send location update to Supabase ────────────────────────────
send_location() {
  local step="$1"
  local lat="$2"
  local lng="$3"
  local heading="$4"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local response
  response=$(curl -s -w "\n%{http_code}" -X POST "${RIDER_LOCATIONS_API}?on_conflict=user_id" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates" \
    -d "{
      \"user_id\": \"$RIDER_ID\",
      \"latitude\": $lat,
      \"longitude\": $lng,
      \"heading\": $heading,
      \"speed\": 20.0,
      \"accuracy\": 10.0,
      \"is_online\": true,
      \"is_on_delivery\": true,
      \"last_active_at\": \"$now\",
      \"updated_at\": \"$now\"
    }" 2>&1)

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" != "201" ] && [ "$http_code" != "200" ]; then
    echo "  ⚠️  Supabase error (HTTP $http_code): $body" >&2
  fi

  local location_name
  location_name=$(get_location_name "$lat" "$lng")
  if [ -n "$location_name" ]; then
    echo "  📍 Step $step: ($lat, $lng)  heading=${heading}°  — $location_name"
  else
    echo "  📍 Step $step: ($lat, $lng)  heading=${heading}°"
  fi
}

# ── Backend API: Mark order as picked up ────────────────────────────────
# This triggers a "Order Picked Up! 🛵" push notification to the customer.
mark_as_picked_up() {
  echo "  📦 Rider at restaurant — calling PATCH /api/orders/$ORDER_ID/picked-up ..."
  local response
  response=$(curl -s -w "\n%{http_code}" -X PATCH \
    "${BACKEND_URL}/orders/${ORDER_ID}/picked-up" \
    -H "Authorization: Bearer $RIDER_JWT" \
    -H "Content-Type: application/json" \
    -d '{}' 2>&1)

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" = "200" ]; then
    echo "  ✅ Order picked up! Push notification sent to customer."
    _HAS_PICKED_UP=true
  else
    echo "  ⚠️  Picked-up API error (HTTP $http_code): $body" >&2
  fi
}

# ── Backend API: Mark order as delivered ─────────────────────────────────
# This triggers a "Order Delivered! 🎉" push notification to the customer.
mark_as_delivered() {
  echo "  📦 Rider at dropoff — calling PATCH /api/orders/$ORDER_ID/deliver ..."
  local response
  response=$(curl -s -w "\n%{http_code}" -X PATCH \
    "${BACKEND_URL}/orders/${ORDER_ID}/deliver" \
    -H "Authorization: Bearer $RIDER_JWT" \
    -H "Content-Type: application/json" \
    -d '{}' 2>&1)

  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" = "200" ]; then
    echo "  ✅ Order delivered! Push notification sent to customer."
    _HAS_DELIVERED=true
  else
    echo "  ⚠️  Deliver API error (HTTP $http_code): $body" >&2
  fi
}

# ── Cleanup on Ctrl+C ───────────────────────────────────────────────────
cleanup() {
  echo ""
  echo ""
  echo "  🛑 Simulation stopped. Marking rider as offline..."
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local offline_resp
  offline_resp=$(curl -s -w "\n%{http_code}" -X PATCH "$RIDER_LOCATIONS_API?user_id=eq.$RIDER_ID" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"is_online\": false,
      \"is_on_delivery\": false,
      \"updated_at\": \"$now\"
    }" 2>&1)
  local offline_code
  offline_code=$(echo "$offline_resp" | tail -1)
  if [ "$offline_code" != "200" ] && [ "$offline_code" != "204" ]; then
    echo "  ⚠️ Offline update error (HTTP $offline_code)" >&2
  fi
  echo "  ✅ Rider marked as offline."
  echo ""
  exit 0
}
trap cleanup SIGINT SIGTERM

# ── Main simulation loop ────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     🚚  Rider Live Location Simulator           ║"
echo "  ╠══════════════════════════════════════════════════╣"
echo "  ║  Rider ID:  ${RIDER_ID:0:12}..."
echo "  ║  Route:     Byasi → Merina"
echo "  ║  Start:     $START_LAT, $START_LNG"
echo "  ║  End:       $END_LAT, $END_LNG"
echo "  ║  Order:     #DAILO-Q4783 ($ORDER_ID)"
echo "  ║  Steps:     $STEPS × ${INTERVAL}s = $((STEPS * INTERVAL))s total"
echo "  ║                                                  ║"
echo "  ║  At step ~3: Order Picked Up notification        ║"
echo "  ║  At step 40: Order Delivered notification        ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

# Set rider to Byasi, wait a moment for Realtime to propagate, then mark as picked up
send_location 0 "$START_LAT" "$START_LNG" 315
sleep 3
echo ""
mark_as_picked_up
sleep 2
echo ""

CURRENT_LAT="$START_LAT"
CURRENT_LNG="$START_LNG"
step=1

while true; do
  # Progress toward destination: linear interpolation with sine wobble
  lat=$(awk "BEGIN {
    wobble = 0.0008 * sin($step * 0.6)
    printf \"%.6f\", $START_LAT + ($DLAT * $step) + wobble
  }" 2>/dev/null || echo "")

  lng=$(awk "BEGIN {
    wobble = 0.0008 * cos($step * 0.4)
    printf \"%.6f\", $START_LNG + ($DLNG * $step) + wobble
  }" 2>/dev/null || echo "")

  # Fallback if awk fails
  if [ -z "$lat" ]; then
    lat=$(python3 -c "print(round($START_LAT + $DLAT * $step + 0.0008 * __import__('math').sin($step * 0.6), 6))" 2>/dev/null)
    lng=$(python3 -c "print(round($START_LNG + $DLNG * $step + 0.0008 * __import__('math').cos($step * 0.4), 6))" 2>/dev/null)
  fi

  # Heading: roughly toward Merina (northwest ~300°), with oscillation
  heading=$(awk "BEGIN { printf \"%.0f\", 310 + 15 * sin($step * 0.3) }")

  send_location "$step" "$lat" "$lng" "$heading"
  CURRENT_LAT="$lat"
  CURRENT_LNG="$lng"

  # After completing all steps, mark as delivered (rider reached Merina)
  if [ "$step" -ge "$STEPS" ]; then
    echo ""
    echo "  🔄 Reached Merina dropoff!"
    if [ "$_HAS_DELIVERED" = false ]; then
      mark_as_delivered
    fi
    echo "  🔄 Heading back toward Byasi..."
    echo ""

    # Swap start and end to reverse direction
    OLD_START_LAT="$START_LAT"
    OLD_START_LNG="$START_LNG"
    START_LAT="$END_LAT"
    START_LNG="$END_LNG"
    END_LAT="$OLD_START_LAT"
    END_LNG="$OLD_START_LNG"

    DLAT=$(awk "BEGIN { printf \"%.7f\", ($END_LAT - $START_LAT) / $STEPS }" 2>/dev/null || echo "-0.0009175")
    DLNG=$(awk "BEGIN { printf \"%.7f\", ($END_LNG - $START_LNG) / $STEPS }" 2>/dev/null || echo "0.0015750")

    # Reset flags for the return trip
    _HAS_PICKED_UP=false
    _HAS_DELIVERED=false
    step=1
    continue
  fi

  sleep "$INTERVAL"
  step=$((step + 1))
done
