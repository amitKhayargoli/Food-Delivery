-- ──────────────────────────────────────────────
-- Multi-Role Support: Add roles array to users
--
-- This migration adds a `roles` array column that allows a single user
-- to hold multiple roles simultaneously (e.g. USER + RESTAURANT_OWNER).
-- The existing `role` column is kept as the "primary" role for backward
-- compatibility with existing JWT tokens and backend checks.
-- ──────────────────────────────────────────────

-- Add roles array column with default of just CUSTOMER
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS roles TEXT[] DEFAULT ARRAY['CUSTOMER'];

-- Migrate existing users: set roles array from their current single role
UPDATE public.users
  SET roles = ARRAY[role]
  WHERE roles IS NULL
     OR array_length(roles, 1) IS NULL
     OR roles = ARRAY[]::text[];

-- Create a GIN index on the roles array for efficient contains queries
CREATE INDEX IF NOT EXISTS idx_users_roles
  ON public.users USING GIN (roles);
