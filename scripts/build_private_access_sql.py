"""Assemble an atomic private-access rollout with a verified administrator."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/migrations/20261007164804_private_access_and_quotas.sql'


def assemble(email):
    email = email.strip().lower()
    if not re.fullmatch(r'[a-z0-9._+%-]+@[a-z0-9.-]+\.[a-z]{2,}', email):
        raise ValueError('Administrator must be an exact email address')
    return f'''-- Generated deployment bundle. Run only on the existing Collect project.
-- First back up data, prepare private-mode clients, and disable public signup
-- or enable the Before User Created Hook. This SQL does not configure Auth settings.
-- All changes and the administrator allowlist are committed together.
begin;
do $preflight$
begin
  if to_regclass('collect_private.allowed_emails') is not null then
    raise exception 'Private access is already initialized. Use the administrator allowlist SQL to maintain members.';
  end if;
  if not exists (select 1 from auth.users where lower(btrim(email)) = '{email}'
      and email_confirmed_at is not null and not coalesce(is_anonymous, false)) then
    raise exception 'The administrator account must exist and have a verified email before enabling private access.';
  end if;
end;
$preflight$;

''' + MIGRATION.read_text(encoding='utf-8') + f'''

insert into collect_private.allowed_emails
  (email, max_items, max_categories, max_storage_bytes, search_per_minute, search_per_day)
values ('{email}', 500, 60, 104857600, 6, 100);

-- Check the same access predicate used by the clients, within this transaction.
select set_config('request.jwt.claim.sub',
  (select id::text from auth.users where lower(btrim(email)) = '{email}'
    and email_confirmed_at is not null and not coalesce(is_anonymous, false) limit 1), true);
do $verify$
begin
  if not public.collection_access_allowed() then
    raise exception 'Administrator access validation failed; all changes must roll back.';
  end if;
end;
$verify$;
commit;
'''


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--admin-email', required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/wechat-package/private-access-deploy.sql')
    args = parser.parse_args()
    try:
        sql = assemble(args.admin_email)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(sql, encoding='utf-8')
        print(args.output.resolve())
        print('Prepared only; no database connection or schema change was made.')
    except (ValueError, OSError) as error:
        parser.exit(1, f'Preparation failed: {error}\n')
