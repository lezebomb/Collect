-- Rename the definition and all owned items in one transaction.
-- Existing tables, columns, RLS policies and backup formats are unchanged.
create or replace function public.rename_collection_category(old_name text, new_name text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner uuid := auth.uid();
  target text := btrim(new_name);
  affected integer;
begin
  if owner is null then
    raise exception '请先登录' using errcode = '42501';
  end if;
  if target is null or char_length(target) not between 1 and 60 then
    raise exception '分类名称需为 1–60 个字' using errcode = '22023';
  end if;
  if not exists (select 1 from public.user_categories where user_id = owner and name = old_name) then
    raise exception '该分类已不存在，请刷新后重试' using errcode = 'P0002';
  end if;
  if old_name = target then return 0; end if;

  -- INSERT/DELETE uses existing category permissions; no UPDATE grant needed.
  -- A duplicate target fails before any items change, rolling back everything.
  insert into public.user_categories (user_id, name, created_at)
  select owner, target, created_at from public.user_categories
  where user_id = owner and name = old_name;
  if not found then
    raise exception '该分类已不存在，请刷新后重试' using errcode = 'P0002';
  end if;
  update public.items set category = target, updated_at = now()
  where user_id = owner and category = old_name;
  get diagnostics affected = row_count;
  delete from public.user_categories where user_id = owner and name = old_name;
  return affected;
end;
$$;
revoke all on function public.rename_collection_category(text, text) from public, anon;
grant execute on function public.rename_collection_category(text, text) to authenticated;
