-- Admin flag on the profile row.
alter table profiles add column if not exists is_admin boolean not null default false;

-- SECURITY DEFINER so a policy on profiles can call it without recursing into
-- profiles' own RLS check.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.is_admin from profiles p where p.id = auth.uid()), false);
$$;

-- Admins may read across accounts. Ordinary users keep their own-row policies.
drop policy if exists "admins read all usage" on ai_usage;
create policy "admins read all usage" on ai_usage for select using (public.is_admin());

drop policy if exists "admins read all entitlements" on entitlements;
create policy "admins read all entitlements" on entitlements for select using (public.is_admin());

drop policy if exists "admins read all reports" on content_reports;
create policy "admins read all reports" on content_reports for select using (public.is_admin());

-- Moderation: an admin can resolve a report and remove any post.
drop policy if exists "admins update reports" on content_reports;
create policy "admins update reports" on content_reports for update using (public.is_admin());

drop policy if exists "admins delete any post" on posts;
create policy "admins delete any post" on posts for delete using (public.is_admin());

drop policy if exists "admins delete any comment" on comments;
create policy "admins delete any comment" on comments for delete using (public.is_admin());
