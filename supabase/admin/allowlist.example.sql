-- Administrator-only example. Replace addresses before executing in SQL Editor.
-- First add yourself. Matching is exact after trim/lowercase; no domain wildcard.
insert into collect_private.allowed_emails
  (email, max_items, max_storage_bytes, search_per_minute, search_per_day)
values
  ('owner@example.com', 500, 104857600, 6, 100),
  ('friend@example.com', 200, 20971520, 3, 30)
on conflict (email) do update set enabled = true;

-- Revoke immediately for all NEW database/Storage requests, even with an old JWT:
-- update collect_private.allowed_emails set enabled = false
-- where email = 'friend@example.com';

-- Inspect allocated budgets and leave room for your project's other data:
-- select count(*) as members, sum(max_items) as max_total_items,
--        sum(max_storage_bytes) as allocated_image_bytes
-- from collect_private.allowed_emails where enabled;

-- Inspect abandoned reservations. Only release after checking no upload is active.
-- select r.* from collect_private.cover_reservations r
-- where r.created_at < now() - interval '24 hours' and not exists (
--   select 1 from storage.objects o where o.bucket_id = 'item-covers' and o.name = r.object_path
-- );
