// Offline SQL integration tests. Installs nothing and never contacts Supabase.
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const root = process.cwd();
const runtime = process.env.COLLECT_PGLITE_PATH || path.join(root,'.tooling/verification/node_modules/@electric-sql/pglite/dist/index.js');
const { PGlite } = await import(pathToFileURL(runtime).href);
const db = new PGlite();
try {
  await db.exec(`
    create role anon; create role authenticated; create role supabase_auth_admin;
    create schema auth; create schema storage;
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,is_anonymous boolean default false);
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,metadata jsonb,unique(bucket_id,name));
    create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name,'/') $$;
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated;
    grant select,insert,update,delete on storage.objects to authenticated;
  `);
  await db.exec(await readFile(path.join(root,'supabase/schema.sql'),'utf8'));
  const migrations=(await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')).sort();
  for(const file of migrations.filter(f=>!f.includes('email_signup_gate'))) {
    if(file.includes('private_access_and_quotas')) await db.exec("update storage.buckets set public=true where id='item-covers'");
    await db.exec(await readFile(path.join(root,'supabase/migrations',file),'utf8'));
  }
  assert.equal((await db.query("select public from storage.buckets where id='item-covers'")).rows[0].public,false);
  const alice='11111111-1111-4111-8111-111111111111';
  const bob='22222222-2222-4222-8222-222222222222';
  const pending='33333333-3333-4333-8333-333333333333';
  await db.exec(`insert into auth.users values ('${alice}','alice@example.test',now(),false),('${bob}','bob@example.test',now(),false),('${pending}','pending@example.test',null,false);
    insert into collect_private.email_members(email) values ('alice@example.test'),('pending@example.test');
    insert into collect_private.allowed_emails(email,max_items,max_storage_bytes,search_per_minute,search_per_day)
      values ('alice@example.test',2,4194304,2,3),('pending@example.test',2,4194304,2,3);`);
  await db.exec(await readFile(path.join(root,'supabase/migrations',migrations.find(f=>f.includes('email_signup_gate'))),'utf8'));
  async function asUser(owner, sql) {
    await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','${owner}',false);`);
    try { return await db.query(sql); } finally { await db.exec('reset role;'); }
  }
  async function denied(owner,sql,pattern) { await assert.rejects(asUser(owner,sql),pattern); }
  assert.equal((await asUser(alice,'select public.collection_access_allowed() as allowed')).rows[0].allowed,true);
  assert.equal((await asUser(bob,'select public.collection_access_allowed() as allowed')).rows[0].allowed,false);
  assert.equal((await asUser(pending,'select public.collection_access_allowed() as allowed')).rows[0].allowed,false);
  await denied(bob,`insert into public.items(name,category) values ('Blocked','其他')`,/权限|policy/i);
  await denied(pending,`insert into public.items(name,category) values ('Unverified','其他')`,/权限|policy/i);
  await asUser(alice,`insert into public.items(id,name,category) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A','游戏'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','B','其他')`);
  await denied(alice,`insert into public.items(name,category) values ('Over quota','其他')`,/上限/);
  assert.equal((await asUser(bob,'select * from public.items')).rows.length,0);
  assert.equal((await asUser(alice,'select * from public.items')).rows.length,2);
  await denied(alice,`update public.items set user_id='${bob}'`,/policy/);
  await denied(alice,`insert into collect_private.allowed_emails(email) values ('intruder@example.test')`,/permission denied/);
  await db.exec(`update collect_private.allowed_emails set enabled=false where email='alice@example.test'`);
  assert.equal((await asUser(alice,'select * from public.items')).rows.length,0);
  await db.exec(`update collect_private.allowed_emails set enabled=true where email='alice@example.test'`);
  assert.equal((await asUser(alice,'select * from public.items')).rows.length,2);
  const cover=`${alice}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`;
  const cover2=`${alice}/wallpaper/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg`;
  const cover3=`${alice}/wallpaper/cccccccc-cccc-4ccc-8ccc-cccccccccccc.jpg`;
  await denied(alice,`insert into storage.objects(bucket_id,name,metadata) values ('item-covers','${cover}','{"size":2097152}')`,/policy/);
  await asUser(alice,`select public.reserve_collection_cover('${cover}')`);
  await asUser(alice,`select public.reserve_collection_cover('${cover}')`); // Idempotent reservation.
  await asUser(alice,`select public.reserve_collection_cover('${cover2}')`);
  await denied(alice,`select public.reserve_collection_cover('${cover3}')`,/上限/);
  await asUser(alice,`insert into storage.objects(bucket_id,name,metadata) values ('item-covers','${cover}','{"size":2097152}')`);
  await asUser(alice,`select public.release_collection_cover('${cover}')`); // Existing objects keep their reservation.
  await denied(alice,`select public.reserve_collection_cover('${cover3}')`,/上限/);
  assert.equal((await asUser(bob,'select * from storage.objects')).rows.length,0);
  await asUser(alice,`delete from storage.objects where name='${cover}'`);
  await asUser(alice,`select public.release_collection_cover('${cover}')`);
  await asUser(alice,`select public.reserve_collection_cover('${cover3}')`);
  await denied(alice,`select public.reserve_collection_cover('${bob}/wallpaper/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg')`,/路径/);
  assert.equal((await asUser(alice,'select public.take_collection_search_slot() as allowed')).rows[0].allowed,true);
  assert.equal((await asUser(alice,'select public.take_collection_search_slot() as allowed')).rows[0].allowed,true);
  assert.equal((await asUser(alice,'select public.take_collection_search_slot() as allowed')).rows[0].allowed,false);
  await denied(bob,'select public.take_collection_search_slot()',/权限/);
  await db.exec(`set role supabase_auth_admin;`);
  const hook = await db.query(`select public.before_collection_user_created('{"user":{"email":" ALICE@example.test ","is_anonymous":false}}') as result`);
  assert.deepEqual(hook.rows[0].result,{});
  const blocked = await db.query(`select public.before_collection_user_created('{"user":{"email":"bob@example.test"}}') as result`);
  assert.equal(blocked.rows[0].result.error.http_code,403);
  await db.exec('reset role;');
  // Renaming at the exact category cap still works atomically.
  await db.exec(`update collect_private.allowed_emails set max_categories=5 where email='alice@example.test';`);
  await asUser(alice,`select public.rename_collection_category('游戏','已改名游戏')`);
  assert.equal((await asUser(alice,`select category from public.items where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'`)).rows[0].category,'已改名游戏');
  const definerPublic = await db.query(`select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and prosecdef`);
  assert.deepEqual(definerPublic.rows,[]);
  console.log('PASS: complete migration chain; allowlist, email confirmation, ownership, revocation, quotas, Storage reservations, signup hook, search throttling, atomic category rename, private function privileges.');
} catch (error) {
  console.error('FAIL:',error.message, error.where || '', error.query || '');
  process.exitCode = 1;
} finally { await db.close(); }
