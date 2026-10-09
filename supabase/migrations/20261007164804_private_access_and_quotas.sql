-- Offline preparation only. Seed the owner's exact email before deployment.
-- Empty allowlist fails closed; existing data is retained.
create schema if not exists collect_private;
revoke all on schema collect_private from public, anon;
grant usage on schema collect_private to authenticated, supabase_auth_admin;

create table collect_private.allowed_emails (
  email text primary key check (email = lower(btrim(email)) and position('@' in email) > 1),
  enabled boolean not null default true,
  max_items integer not null default 500 check (max_items between 1 and 10000),
  max_categories integer not null default 60 check (max_categories between 5 and 500),
  max_storage_bytes bigint not null default 104857600 check (max_storage_bytes >= 2097152),
  search_per_minute integer not null default 6 check (search_per_minute between 1 and 60),
  search_per_day integer not null default 100 check (search_per_day between 1 and 1000)
);
alter table collect_private.allowed_emails enable row level security;
revoke all on collect_private.allowed_emails from public, anon, authenticated;
grant select on collect_private.allowed_emails to supabase_auth_admin;
create policy auth_hook_read_allowlist on collect_private.allowed_emails
  for select to supabase_auth_admin using (true);

create or replace function collect_private.has_collection_access()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from auth.users u join collect_private.allowed_emails a
      on a.email = lower(btrim(u.email))
    where u.id = auth.uid() and u.email_confirmed_at is not null
      and not coalesce(u.is_anonymous, false) and a.enabled
  );
$$;
revoke all on function collect_private.has_collection_access() from public, anon;
grant execute on function collect_private.has_collection_access() to authenticated;

create or replace function public.collection_access_allowed()
returns boolean language sql stable security invoker set search_path = '' as $$
  select collect_private.has_collection_access();
$$;
revoke all on function public.collection_access_allowed() from public, anon;
grant execute on function public.collection_access_allowed() to authenticated;

-- Enable this function as Authentication > Hooks > Before User Created.
create or replace function public.before_collection_user_created(event jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
  if coalesce((event->'user'->>'is_anonymous')::boolean, false) or not exists (
    select 1 from collect_private.allowed_emails
    where email = lower(btrim(event->'user'->>'email')) and enabled
  ) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', '此应用仅向获准的邮箱开放，请联系管理员。'));
  end if;
  return '{}'::jsonb;
end;
$$;
revoke all on function public.before_collection_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.before_collection_user_created(jsonb) to supabase_auth_admin;

-- Restrictive policies intersect with existing ownership policies. A future
-- permissive policy cannot accidentally bypass the allowlist.
create policy collection_members_only on public.items as restrictive
  for all to authenticated
  using ((select collect_private.has_collection_access()))
  with check ((select collect_private.has_collection_access()));
create policy collection_members_only on public.user_preferences as restrictive
  for all to authenticated
  using ((select collect_private.has_collection_access()))
  with check ((select collect_private.has_collection_access()));
create policy collection_members_only on public.user_categories as restrictive
  for all to authenticated
  using ((select collect_private.has_collection_access()))
  with check ((select collect_private.has_collection_access()));
create policy collection_members_only on storage.objects as restrictive
  for all to authenticated
  using (bucket_id <> 'item-covers' or (select collect_private.has_collection_access()))
  with check (bucket_id <> 'item-covers' or (select collect_private.has_collection_access()));

create index if not exists items_user_created_id_idx
  on public.items(user_id, created_at desc, id desc);
alter table public.items add constraint items_description_limit
  check (char_length(description) <= 20000) not valid;

create or replace function collect_private.enforce_collection_quota()
returns trigger language plpgsql security definer set search_path = '' as $$
declare rule collect_private.allowed_emails%rowtype; n integer;
begin
  -- Trusted initialization of the five default categories during signup.
  if auth.uid() is null and tg_table_name = 'user_categories' then return new; end if;
  if auth.uid() is null or new.user_id <> auth.uid() or
      not collect_private.has_collection_access() then
    raise exception '没有访问权限' using errcode = '42501';
  end if;
  -- One lock per member prevents concurrent INSERTs passing the same count.
  select a.* into rule from collect_private.allowed_emails a join auth.users u
    on lower(btrim(u.email)) = a.email where u.id = auth.uid() for update of a;
  if tg_table_name = 'items' then
    if exists (select 1 from public.items where id = new.id and user_id = new.user_id) then return new; end if;
    select count(*) into n from public.items where user_id = new.user_id;
    if n >= rule.max_items then raise exception '收藏数量已达账号上限'; end if;
  else
    if exists (select 1 from public.user_categories where user_id = new.user_id and name = new.name) then return new; end if;
    select count(*) into n from public.user_categories where user_id = new.user_id;
    -- Renaming temporarily adds one definition; only allow that transaction's RPC.
    if n >= rule.max_categories then raise exception '分类数量已达账号上限'; end if;
  end if;
  return new;
end;
$$;
revoke all on function collect_private.enforce_collection_quota() from public, anon, authenticated;
create trigger collection_item_quota before insert on public.items
  for each row execute function collect_private.enforce_collection_quota();
create trigger collection_category_quota before insert on public.user_categories
  for each row execute function collect_private.enforce_collection_quota();

-- Reserve the bucket's full per-object maximum, rather than trusting a byte
-- count supplied by the client. Abandoned reservations consume only that
-- member's quota until released; they cannot cause total storage overflow.
create table collect_private.cover_reservations (
  object_path text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index cover_reservations_owner_idx on collect_private.cover_reservations(user_id);
alter table collect_private.cover_reservations enable row level security;
revoke all on collect_private.cover_reservations from public, anon, authenticated;
update storage.buckets set public = false, file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
  where id = 'item-covers';

create or replace function collect_private.storage_used(owner uuid)
returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce((select sum(coalesce((metadata->>'size')::bigint, 2097152))
    from storage.objects where bucket_id = 'item-covers'
      and (storage.foldername(name))[1] = owner::text), 0)
    + 2097152 * (select count(*) from collect_private.cover_reservations r
      where r.user_id = owner and not exists (select 1 from storage.objects o
        where o.bucket_id = 'item-covers' and o.name = r.object_path));
$$;
revoke all on function collect_private.storage_used(uuid) from public, anon, authenticated;

create or replace function collect_private.reserve_cover(object_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare owner uuid := auth.uid(); quota bigint;
begin
  if owner is null or not collect_private.has_collection_access() then
    raise exception '没有访问权限' using errcode = '42501';
  end if;
  if object_path !~ ('^' || owner::text || '/(wallpaper|[0-9a-f-]{36})/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|heic|heif)$') then
    raise exception '图片路径无效' using errcode = '22023';
  end if;
  select a.max_storage_bytes into quota from collect_private.allowed_emails a
    join auth.users u on lower(btrim(u.email)) = a.email
    where u.id = owner for update of a;
  if exists (select 1 from collect_private.cover_reservations where cover_reservations.object_path = reserve_cover.object_path and user_id = owner) then return; end if;
  if collect_private.storage_used(owner) + 2097152 > quota then
    raise exception '图片空间已达账号上限，请删除旧图片或联系管理员';
  end if;
  insert into collect_private.cover_reservations(object_path, user_id) values (object_path, owner);
end;
$$;
revoke all on function collect_private.reserve_cover(text) from public, anon;
grant execute on function collect_private.reserve_cover(text) to authenticated;
create function public.reserve_collection_cover(object_path text)
returns void language sql security invoker set search_path = '' as $$
  select collect_private.reserve_cover(object_path);
$$;
revoke all on function public.reserve_collection_cover(text) from public, anon;
grant execute on function public.reserve_collection_cover(text) to authenticated;

create function collect_private.cover_reserved(object_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from collect_private.cover_reservations r
    where r.object_path = cover_reserved.object_path and r.user_id = auth.uid());
$$;
revoke all on function collect_private.cover_reserved(text) from public, anon;
grant execute on function collect_private.cover_reserved(text) to authenticated;
create policy collection_reserved_upload on storage.objects as restrictive
  for insert to authenticated with check (bucket_id <> 'item-covers' or collect_private.cover_reserved(name));
-- Existing clients use immutable UUID paths; overwrites are deliberately denied.
create policy collection_no_overwrite on storage.objects as restrictive
  for update to authenticated using (bucket_id <> 'item-covers');

create function collect_private.release_cover(object_path text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;
  delete from collect_private.cover_reservations r
    where r.object_path = release_cover.object_path and r.user_id = auth.uid()
    and not exists (select 1 from storage.objects o where o.bucket_id = 'item-covers' and o.name = r.object_path);
end;
$$;
revoke all on function collect_private.release_cover(text) from public, anon;
grant execute on function collect_private.release_cover(text) to authenticated;
create function public.release_collection_cover(object_path text)
returns void language sql security invoker set search_path = '' as $$
  select collect_private.release_cover(object_path);
$$;
revoke all on function public.release_collection_cover(text) from public, anon;
grant execute on function public.release_collection_cover(text) to authenticated;

create table collect_private.search_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  minute timestamptz not null, minute_count integer not null,
  day date not null, day_count integer not null
);
alter table collect_private.search_usage enable row level security;
revoke all on collect_private.search_usage from public, anon, authenticated;
create function collect_private.take_search_slot()
returns boolean language plpgsql security definer set search_path = '' as $$
declare owner uuid := auth.uid(); rule collect_private.allowed_emails%rowtype;
  usage collect_private.search_usage%rowtype;
  minute_now timestamptz := date_trunc('minute', now());
  day_now date := (now() at time zone 'Asia/Shanghai')::date;
begin
  if owner is null or not collect_private.has_collection_access() then
    raise exception '没有访问权限' using errcode = '42501';
  end if;
  select a.* into rule from collect_private.allowed_emails a join auth.users u
    on lower(btrim(u.email)) = a.email where u.id = owner for update of a;
  select * into usage from collect_private.search_usage where user_id = owner;
  if usage.minute is distinct from minute_now then usage.minute_count := 0; end if;
  if usage.day is distinct from day_now then usage.day_count := 0; end if;
  if usage.minute_count >= rule.search_per_minute or usage.day_count >= rule.search_per_day then return false; end if;
  insert into collect_private.search_usage values (owner, minute_now, usage.minute_count + 1, day_now, usage.day_count + 1)
    on conflict (user_id) do update set minute = excluded.minute, minute_count = excluded.minute_count,
      day = excluded.day, day_count = excluded.day_count;
  return true;
end;
$$;
revoke all on function collect_private.take_search_slot() from public, anon;
grant execute on function collect_private.take_search_slot() to authenticated;
create function public.take_collection_search_slot()
returns boolean language sql security invoker set search_path = '' as $$ select collect_private.take_search_slot(); $$;
revoke all on function public.take_collection_search_slot() from public, anon;
grant execute on function public.take_collection_search_slot() to authenticated;

-- Rename at the category limit by deleting the old definition first, within the
-- same transaction. Any duplicate or quota error rolls everything back.
create function collect_private.lock_collection_member()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not collect_private.has_collection_access() then
    raise exception '没有访问权限' using errcode = '42501';
  end if;
  perform a.email from collect_private.allowed_emails a join auth.users u
    on lower(btrim(u.email)) = a.email where u.id = auth.uid() for update of a;
end;
$$;
revoke all on function collect_private.lock_collection_member() from public, anon;
grant execute on function collect_private.lock_collection_member() to authenticated;
create or replace function public.rename_collection_category(old_name text, new_name text)
returns integer language plpgsql security invoker set search_path = '' as $$
declare owner uuid := auth.uid(); target text := btrim(new_name); stamp timestamptz; affected integer;
begin
  if owner is null or not collect_private.has_collection_access() then raise exception '没有访问权限' using errcode = '42501'; end if;
  if target is null or char_length(target) not between 1 and 60 then raise exception '分类名称需为 1–60 个字'; end if;
  perform collect_private.lock_collection_member();
  select created_at into stamp from public.user_categories where user_id = owner and name = old_name;
  if not found then raise exception '分类不存在，请刷新'; end if;
  if target = old_name then return 0; end if;
  delete from public.user_categories where user_id = owner and name = old_name;
  insert into public.user_categories(user_id, name, created_at) values (owner, target, stamp);
  update public.items set category = target, updated_at = now() where user_id = owner and category = old_name;
  get diagnostics affected = row_count;
  return affected;
end;
$$;
