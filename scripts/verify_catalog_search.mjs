// Exercise the actual Deno handler with local fetch stubs; never calls Tavily.
import assert from 'node:assert/strict';
let handler;
const secrets = { SUPABASE_URL:'https://test.supabase.co',SUPABASE_ANON_KEY:'test-key',TAVILY_API_KEY:'server-only-test-key' };
globalThis.Deno = { env:{get:name=>secrets[name]}, serve:fn=>{handler=fn;} };
await import('../supabase/functions/catalog-search/index.ts');
const request = (body={query:'test game'})=>new Request('https://example.test/catalog-search',{method:'POST',headers:{Authorization:'Bearer test-session','Content-Type':'application/json'},body:JSON.stringify(body)});
const originalFetch=globalThis.fetch;
try {
  assert.equal((await handler(new Request('https://example.test/catalog-search',{method:'POST'}))).status,401);
  let calls = [];
  function stub(permission) {
    calls=[];
    globalThis.fetch=async (url,options)=>{
      calls.push(String(url));
      if(String(url).endsWith('/auth/v1/user')) return Response.json({id:'owner',is_anonymous:false});
      if(String(url).endsWith('/take_email_collection_search_slot')) {
        assert.equal(options.headers.Authorization,'Bearer test-session');
        return permission==='denied' ? Response.json({message:'denied'},{status:403}) : Response.json(permission);
      }
      assert.equal(options.headers.Authorization,'Bearer server-only-test-key');
      return Response.json({images:['https://images.example.test/cover.jpg','http://unsafe.example.test/image.jpg']});
    };
  }
  stub(false); assert.equal((await handler(request())).status,429); assert.equal(calls.length,2);
  stub('denied'); assert.equal((await handler(request())).status,403); assert.equal(calls.length,2);
  stub(true); const result=await handler(request());assert.equal(result.status,200);
  const body=await result.json();assert.equal(body.candidates.length,1);assert.equal(body.configured,true);assert.equal(calls.length,3);
  assert.equal((await handler(request({query:'a'}))).status,400);
  assert.equal((await handler(request({query:'x'.repeat(5000)}))).status,413);
  assert.equal((await handler(new Request('https://example.test/catalog-search',{method:'POST',headers:{Authorization:'Bearer test-session'},body:'invalid json'}))).status,400);
  console.log('PASS: actual catalog handler rejects missing authentication, denies nonmembers, throttles before billing, and filters insecure image URLs.');
} catch(error) { console.error('FAIL:',error.message);process.exitCode=1; }
finally { globalThis.fetch=originalFetch;delete globalThis.Deno; }
