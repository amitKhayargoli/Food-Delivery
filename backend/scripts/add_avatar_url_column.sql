-- ──────────────────────────────────────────────
-- Profile Picture Support: Add avatar_url column
--
-- This migration adds an `avatar_url` column to the users table
-- for storing the public URL of the user's profile picture,
-- uploaded to the avatar-images Supabase Storage bucket.
-- ──────────────────────────────────────────────

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;
