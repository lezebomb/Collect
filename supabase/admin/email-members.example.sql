-- Administrator-only: execute in your own project's SQL Editor.
-- Replace these example addresses; the client has no permission to edit members.
insert into collect_private.email_members (email, enabled)
values ('owner@example.com', true), ('friend@example.com', true)
on conflict (email) do update set enabled = excluded.enabled;

-- Revoke future database/Storage/search access without deleting stored data:
-- update collect_private.email_members set enabled = false
-- where email = 'friend@example.com';

-- Number of enabled members; do not publish the private list:
-- select count(*) from collect_private.email_members where enabled;
