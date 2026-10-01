-- Defaults are ordinary, deletable definitions. Existing item categories are untouched.
insert into public.user_categories (user_id, name, created_at)
select u.id, d.name, now() + d.position * interval '1 microsecond'
from auth.users u
cross join (values ('游戏', 0), ('周边', 1), ('配件', 2), ('主机', 3), ('其他', 4)) as d(name, position)
on conflict (user_id, name) do nothing;

create schema if not exists collect_private;
revoke all on schema collect_private from public, anon, authenticated;

create function collect_private.initialize_collection_categories()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_categories (user_id, name, created_at)
  select new.id, d.name, now() + d.position * interval '1 microsecond'
  from (values ('游戏', 0), ('周边', 1), ('配件', 2), ('主机', 3), ('其他', 4)) as d(name, position)
  on conflict (user_id, name) do nothing;
  return new;
end;
$$;
revoke all on function collect_private.initialize_collection_categories() from public, anon, authenticated;

create trigger initialize_collection_categories
after insert on auth.users
for each row execute function collect_private.initialize_collection_categories();
