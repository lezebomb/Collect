-- Enforce the same exact-email membership before any new Auth user is stored.
-- Existing accounts, sessions and password recovery are retained.
create function collect_private.enforce_email_signup()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(new.is_anonymous, false) or not exists (
    select 1 from collect_private.email_members m
    where m.email = lower(btrim(new.email)) and m.enabled
  ) then
    raise exception '此应用仅供获准邮箱使用' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function collect_private.enforce_email_signup() from public, anon, authenticated;
create trigger collection_email_signup_gate before insert on auth.users
  for each row execute function collect_private.enforce_email_signup();
