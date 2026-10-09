// Standalone server membership tests; local Postgres only, no cloud requests.
import {readFile, readdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=process.cwd();
const {PGlite}=await import(pathToFileURL(path.join(root,'.tooling/verification/node_modules/@electric-sql/pglite/dist/index.js')).href);
const db=new PGlite();
try {
  const prior=await readFile('scripts/verify_access.mjs','utf8');
  await db.exec(prior.match(/await db\.exec\(`([\s\S]*?)`\);/)[1]);
  await db.exec(await readFile('supabase/schema.sql','utf8'));
  const migrationFiles=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
  for(const file of migrationFiles.filter(f=>!f.includes('private_access_and_quotas')&&!f.includes('email_signup_gate'))) {
    await db.exec(await readFile(path.join('supabase/migrations',file),'utf8'));
  }
  const alice='11111111-1111-4111-8111-111111111111';
  const bob='22222222-2222-4222-8222-222222222222';
  const pending='33333333-3333-4333-8333-333333333333';
  await db.exec(`insert into auth.users values ('${alice}','alice@example.test',now(),false),('${bob}','bob@example.test',now(),false),('${pending}','pending@example.test',null,false);
    insert into collect_private.email_members(email) values ('alice@example.test'),('pending@example.test');`);
  await db.exec(await readFile(path.join('supabase/migrations',migrationFiles.find(f=>f.includes('email_signup_gate'))),'utf8'));
  await assert.rejects(db.exec("insert into auth.users values ('44444444-4444-4444-8444-444444444444','outsider@example.test',now(),false)"),/获准邮箱/);
  async function asUser(id,sql) {
    await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','${id}',false);`);
    try{return await db.query(sql);} finally {await db.exec('reset role');}
  }
  assert.equal((await asUser(alice,'select public.collection_email_access_allowed() as ok')).rows[0].ok,true);
  for(const id of [bob,pending]) {
    assert.equal((await asUser(id,'select public.collection_email_access_allowed() as ok')).rows[0].ok,false);
    await assert.rejects(asUser(id,"insert into public.items(name,category) values ('Denied','其他')"),/policy/);
  }
  await asUser(alice,"insert into public.items(name,category) values ('Allowed','其他')");
  assert.equal((await asUser(bob,'select * from public.items')).rows.length,0);
  await assert.rejects(asUser(alice,`update public.items set user_id='${bob}'`),/policy/);
  await assert.rejects(asUser(alice,'select * from collect_private.email_members'),/permission denied/);
  const cover=`${alice}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`;
  await asUser(alice,`insert into storage.objects(bucket_id,name,metadata) values ('item-covers','${cover}','{"size":100}')`);
  assert.equal((await asUser(bob,'select * from storage.objects')).rows.length,0);
  await assert.rejects(asUser(bob,`insert into storage.objects(bucket_id,name) values ('item-covers','${bob}/x.jpg')`),/policy/);
  for(let n=0;n<6;n++) assert.equal((await asUser(alice,'select public.take_email_collection_search_slot() as ok')).rows[0].ok,true);
  assert.equal((await asUser(alice,'select public.take_email_collection_search_slot() as ok')).rows[0].ok,false);
  await assert.rejects(asUser(bob,'select public.take_email_collection_search_slot()'),/权限/);
  await db.exec("update collect_private.email_members set enabled=false where email='alice@example.test'");
  assert.equal((await asUser(alice,'select * from public.items')).rows.length,0);
  assert.equal((await asUser(alice,'select * from storage.objects')).rows.length,0);
  assert.equal((await db.query('select count(*) as n from public.items')).rows[0].n,1);
  console.log('PASS: standalone membership, confirmed email, direct API denial, account ownership, private member list, revocation, search limits, and legacy uploads.');
} finally {await db.close();}
