// Offline transaction tests only. No network or production database access.
import {readFile, readdir} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const root=process.cwd();
const runtime=process.env.COLLECT_PGLITE_PATH || path.join(root,'.tooling/verification/node_modules/@electric-sql/pglite/dist/index.js');
const {PGlite}=await import(pathToFileURL(runtime).href);
const existingTest=await readFile(path.join(root,'scripts/verify_access.mjs'),'utf8');
const setup=existingTest.match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
const rollout=await readFile(process.argv[2] || path.join(root,'build/wechat-package/private-access-deploy.sql'),'utf8');
const match=rollout.match(/values \('([^']+)', 500, 60,/);
assert.ok(match,'Generate the rollout SQL with scripts/build_private_access_sql.py first');
const adminEmail=match[1];
for(const scenario of ['missing','unverified','verified']) {
  const db=new PGlite();
  try {
    await db.exec(setup);
    await db.exec(await readFile(path.join(root,'supabase/schema.sql'),'utf8'));
    for(const file of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')&&!f.includes('private_access_and_quotas')).sort()) {
      await db.exec(await readFile(path.join(root,'supabase/migrations',file),'utf8'));
    }
    await db.exec(`insert into collect_private.email_members(email) values ('${adminEmail}')`);
    if(scenario!=='missing') {
      await db.exec(`insert into auth.users(id,email,email_confirmed_at) values ('11111111-1111-4111-8111-111111111111','${adminEmail}',${scenario==='verified'?'now()':'null'})`);
    }
    if(scenario==='verified') {
      await db.exec(rollout);
      assert.equal((await db.query('select count(*) as count from collect_private.allowed_emails')).rows[0].count,1);
      await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);`);
      assert.equal((await db.query('select public.collection_access_allowed() as allowed')).rows[0].allowed,true);
      await db.exec('reset role;');
      console.log('PASS: verified administrator, migration and allowlist committed atomically, authenticated RPC allowed.');
    } else {
      await assert.rejects(db.exec(rollout),/administrator account must exist/i);
      await db.exec('rollback');
      assert.equal((await db.query("select to_regclass('collect_private.allowed_emails') as schema")).rows[0].schema,null);
      assert.equal((await db.query('select count(*) as count from auth.users')).rows[0].count,scenario==='missing'?0:1);
      console.log(`PASS: ${scenario} administrator, transaction rolled back, original accounts retained.`);
    }
  } finally { await db.close(); }
}
