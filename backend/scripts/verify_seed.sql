-- ============================================
-- DAILO DATABASE SEED VERIFICATION
-- Run this in Supabase SQL Editor
-- ============================================

-- 1. USERS
SELECT '👤 USERS' AS section;
SELECT role, COUNT(*) AS count FROM public.users GROUP BY role ORDER BY count DESC;

-- 2. RESTAURANTS
SELECT '🍽️  RESTAURANTS' AS section;
SELECT 
  r.id::varchar(8) AS id,
  r.restaurant_name, 
  r.cuisine_type,
  r.status,
  (SELECT COUNT(*) FROM public.menu_items m WHERE m.restaurant_id = r.id) AS menu_items,
  (SELECT COUNT(*) FROM public.orders o WHERE o.restaurant_id = r.id) AS orders
FROM public.restaurant_applications r
ORDER BY r.created_at DESC;

-- 3. MENU ITEMS (total count)
SELECT '📝 MENU ITEMS' AS section;
SELECT COUNT(*) AS total_menu_items FROM public.menu_items;

-- 4. ORDERS BY STATUS
SELECT '📦 ORDERS BY STATUS' AS section;
SELECT 
  status,
  COUNT(*) AS count,
  ROUND(AVG(total)::numeric, 0) AS avg_total
FROM public.orders
GROUP BY status
ORDER BY status;

-- 5. TOTAL ORDER COUNT
SELECT '📦 TOTAL ORDERS' AS section;
SELECT COUNT(*) AS total_orders FROM public.orders;

-- 6. OVERALL SUMMARY
SELECT '✅ DATABASE SUMMARY' AS section;
SELECT 
  (SELECT COUNT(*) FROM public.restaurant_applications) AS restaurants,
  (SELECT COUNT(*) FROM public.menu_items) AS menu_items,
  (SELECT COUNT(*) FROM public.orders) AS orders;
