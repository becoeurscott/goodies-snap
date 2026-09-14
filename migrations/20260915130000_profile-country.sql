-- Add country code to profiles so the admin dashboard can show user geography.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS country TEXT;

-- Allow admins to read it; existing RLS policies already grant SELECT to the profile owner.
