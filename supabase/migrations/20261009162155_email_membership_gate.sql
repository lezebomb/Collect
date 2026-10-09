-- Standalone email gate. Keeps existing clients' image uploads compatible.
-- Real member addresses are provisioned separately and never committed.
create schema if not exists collect_private;
revoke all on schema collect_private from public, anon;
grant usage on schema collect_private to authenticated;

create table collect_private.email_members (
  email text primary key check (email = lower(btrim(email)) and position('@' in email) > 1),
  enabled boolean not null default true
);
alter table collect_private.email_members enable row level security;
revoke all on collect_private.email_members from public, anon, authenticated;

create function collect_private.has_email_access()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from auth.users u join collect_private.email_members m
      on m.email = lower(btrim(u.email))
    where u.id = auth.uid() and u.email_confirmed_at is not null
      and not coalesce(u.is_anonymous, false) and m.enabled
  );
$$;
revoke all on function collect_private.has_email_access() from public, anon;
grant execute on function collect_private.has_email_access() to authenticated;

create function public.collection_email_access_allowed()
returns boolean language sql stable security invoker set search_path = '' as $$
  select collect_private.has_email_access();
$$;
revoke all on function public.collection_email_access_allowed() from public, anon;
grant execute on function public.collection_email_access_allowed() to authenticated;

create policy collection_email_members_only on public.items as restrictive
  for all to authenticated using ((select collect_private.has_email_access()))
  with check ((select collect_private.has_email_access()));
create policy collection_email_members_only on public.user_preferences as restrictive
  for all to authenticated using ((select collect_private.has_email_access()))
  with check ((select collect_private.has_email_access()));
create policy collection_email_members_only on public.user_categories as restrictive
  for all to authenticated using ((select collect_private.has_email_access()))
  with check ((select collect_private.has_email_access()));
create policy collection_email_members_only on storage.objects as restrictive
  for all to authenticated
  using (bucket_id <> 'item-covers' or (select collect_private.has_email_access()))
  with check (bucket_id <> 'item-covers' or (select collect_private.has_email_access()));

-- Serialize paid searches per member, independently of optional upload quotas.
create table collect_private.email_search_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  minute timestamptz not null,
  minute_count integer not null,
  day date not null,
  day_count integer not null
);
alter table collect_private.email_search_usage enable row level security;
revoke all on collect_private.email_search_usage from public, anon, authenticated;

create function collect_private.take_email_search_slot()
returns boolean language plpgsql security definer set search_path = '' as $$
declare owner uuid := auth.uid(); usage collect_private.email_search_usage%rowtype;
  minute_now timestamptz := date_trunc('minute', now());
  day_now date := (now() at time zone 'Asia/Shanghai')::date;
begin
  if owner is null or not collect_private.has_email_access() then
    raise exception '没有访问权限' using errcode = '42501';
  end if;
  perform m.email from collect_private.email_members m join auth.users u
    on m.email = lower(btrim(u.email)) where u.id = owner for update of m;
  select * into usage from collect_private.email_search_usage where user_id = owner;
  if usage.minute is distinct from minute_now then usage.minute_count := 0; end if;
  if usage.day is distinct from day_now then usage.day_count := 0; end if;
  if usage.minute_count >= 6 or usage.day_count >= 100 then return false; end if;
  insert into collect_private.email_search_usage values
    (owner, minute_now, usage.minute_count + 1, day_now, usage.day_count + 1)
    on conflict (user_id) do update set minute = excluded.minute,
      minute_count = excluded.minute_count, day = excluded.day, day_count = excluded.day_count;
  return true;
end;
$$;
revoke all on function collect_private.take_email_search_slot() from public, anon;
grant execute on function collect_private.take_email_search_slot() to authenticated;
create function public.take_email_collection_search_slot()
returns boolean language sql security invoker set search_path = '' as $$
  select collect_private.take_email_search_slot();
$$;
revoke all on function public.take_email_collection_search_slot() from public, anon;
grant execute on function public.take_email_collection_search_slot() to authenticated;
