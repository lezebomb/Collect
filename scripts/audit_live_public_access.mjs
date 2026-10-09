// Read-only production probes. Never logs configuration keys or user records.
import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const config=JSON.parse(await readFile('config/local.json','utf8'));
const base=config.SUPABASE_URL;
const headers={apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'};
const report={};
for(const table of ['items','user_preferences','user_categories']) {
  const response=await fetch(`${base}/rest/v1/${table}?select=*&limit=1`,{headers});
  const body=await response.json();
  assert.ok([401,403].includes(response.status)||(response.ok&&Array.isArray(body)&&body.length===0),`${table}: anonymous read unexpectedly succeeded`);
  report[`anonymous_${table}`]='DENIED';
}
const membership=await fetch(`${base}/rest/v1/rpc/collection_email_access_allowed`,{method:'POST',headers,body:'{}'});
assert.ok([401,403].includes(membership.status),'Anonymous membership RPC must be denied');
report.anonymous_membership='DENIED';
const search=await fetch(`${base}/functions/v1/catalog-search`,{method:'POST',headers,body:'{"query":"security probe"}'});
assert.equal(search.status,401,'Search must reject a request without a user session');
report.anonymous_paid_search='DENIED';
const settings=await fetch(`${base}/auth/v1/settings`,{headers});
if(settings.ok) {
  const auth=await settings.json();
  report.auth_public_signup_disabled=auth.disable_signup===true;
}
await writeFile('.tooling/live-public-access-audit.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
