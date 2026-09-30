-- Personal collection MVP. Apply to a dedicated Supabase project.
-- Each cover is private; the stored cover_image URL is a stable object URL,
-- while the client requests short-lived signed URLs to display the image.

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  category text not null check (char_length(btrim(category)) between 1 and 60),
  cover_image text,
  description text not null default '',
  purchase_date date,
  price numeric(12, 2) check (price is null or price >= 0),
  status text not null default 'owned' check (status in ('wanted', 'owned', 'using', 'idle', 'sold')),
  rating smallint check (rating is null or rating between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists items_user_created_idx on public.items (user_id, created_at desc);

alter table public.items enable row level security;

create policy "items_select_own" on public.items
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "items_insert_own" on public.items
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "items_update_own" on public.items
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "items_delete_own" on public.items
  for delete to authenticated using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.items to authenticated;
revoke all on public.items from anon;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('item-covers', 'item-covers', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do nothing;

-- Object names always begin with the authenticated user's UUID.
create policy "item_covers_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'item-covers' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "item_covers_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'item-covers' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "item_covers_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'item-covers' and (storage.foldername(name))[1] = (select auth.uid())::text);
