const test = require('node:test'); const assert = require('node:assert/strict'); const path = require('node:path');
const root = path.resolve(__dirname,'..');
function setup(handler,options={}) {
  for(const key of Object.keys(require.cache)) if(key.startsWith(root)) delete require.cache[key];
  const storage = new Map(); const calls=[];
  const owner='11111111-1111-4111-8111-111111111111';
  storage.set('dearshelf:session',{access_token:'token',refresh_token:'refresh',expires_at:Date.now()/1000+(options.expired?-1:1000),user:{id:owner,email:'alice@example.test'}});
  global.wx={getStorageSync:key=>storage.get(key),setStorageSync:(key,value)=>storage.set(key,value),removeStorageSync:key=>storage.delete(key),
    request:request=>{calls.push(request);Promise.resolve().then(()=>handler(request)).then(result=>{
      if(result && result.fail) request.fail({errMsg:'request:fail timeout'});
      else request.success({statusCode:result && result.status || 200,data:result && result.data});
    }).catch(error=>request.fail({errMsg:error.message}));},
    getFileSystemManager:()=>({readFile:({success})=>success({data:options.bytes || new Uint8Array([255,216,255,0]).buffer})})};
  const config=require('../config');config.supabaseUrl='https://test.supabase.co';config.publishableKey='sb_publishable_test';
  return {api:require('../lib/api'),repo:require('../lib/repository'),storage,calls,owner,config};
}
test('Concurrent authenticated requests share one refresh and scoped credentials', async()=>{
  const ctx=setup(request=>request.url.includes('/auth/v1/token')?{data:{access_token:'renewed',refresh_token:'new-refresh',expires_in:3600,user:{id:'11111111-1111-4111-8111-111111111111'}}}:{data:true},{expired:true});
  await Promise.all([ctx.api.ensureAccess(),ctx.api.ensureAccess(),ctx.api.ensureAccess()]);
  assert.equal(ctx.calls.filter(call=>call.url.includes('/auth/v1/token')).length,1);
  ctx.calls.filter(call=>call.url.includes('/rest/')).forEach(call=>assert.equal(call.header.Authorization,'Bearer renewed'));
});
test('Denied access rejects the session instead of opening a collection',async()=>{
  const ctx=setup(request=>request.url.includes('/auth/')?{data:{access_token:'token',refresh_token:'refresh',expires_in:3600,user:{id:'11111111-1111-4111-8111-111111111111'}}}:{data:false});
  await assert.rejects(ctx.api.login('alice@example.test','password'),/尚未获准/);
  assert.equal(ctx.api.current(),null);
});
test('Shared list loading, pagination and one batch signature request avoid repeated fetches',async()=>{
  const ctx=setup(request=>{
    if(request.url.includes('/object/sign')) return {data:request.data.paths.map(path=>({path,signedURL:`/object/sign/item-covers/${path}?token=signed`}))};
    return {data:[{id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',user_id:'11111111-1111-4111-8111-111111111111',name:'A',created_at:'2026-01-01'}]};
  });
  await Promise.all([ctx.repo.items(),ctx.repo.items()]);await ctx.repo.items();
  assert.equal(ctx.calls.length,1);assert.ok(ctx.calls[0].url.includes('user_id=eq.'+ctx.owner));
  const prefix=ctx.config.supabaseUrl+'/storage/v1/object/authenticated/item-covers/';
  const urls=[prefix+ctx.owner+'/a/one.jpg',prefix+ctx.owner+'/b/two.jpg'];
  const signed=await ctx.repo.covers(urls);await ctx.repo.covers(urls);
  assert.equal(ctx.calls.filter(call=>call.url.includes('/object/sign')).length,1);
  assert.equal(signed[urls[0]],ctx.config.supabaseUrl+'/storage/v1/object/sign/item-covers/'+ctx.owner+'/a/one.jpg?token=signed');
  assert.equal(ctx.repo.objectPath(prefix+'another-owner/a/x.jpg'),null);
});
test('Logout discards pending data and account-scoped local snapshots',async()=>{
  let finish;const ctx=setup(()=>new Promise(resolve=>{finish=resolve;}));
  const pending=ctx.repo.items();await new Promise(resolve=>setImmediate(resolve));
  ctx.storage.set(`dearshelf:${ctx.owner}:snapshot`,[{user_id:ctx.owner}]);
  ctx.api.clearSession();finish({data:[]});
  await assert.rejects(pending,/会话已改变/);
  assert.equal(ctx.storage.has(`dearshelf:${ctx.owner}:snapshot`),false);
});
test('Lost save response is reconciled by stable ID and does not issue a second INSERT',async()=>{
  let stored;const ctx=setup(request=>{
    if(request.method==='POST' && request.url.endsWith('/rest/v1/items')) {stored=request.data;return {fail:true};}
    return {data:[{...stored,created_at:'2026-01-01'}]};
  });
  const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const saved=await ctx.repo.save({name:'Game',category:'游戏',price:'10'},{id});
  assert.equal(saved.id,id);assert.equal(ctx.calls.filter(call=>call.method==='POST').length,1);
});
test('Quota reservation precedes upload and oversized files never reach the server',async()=>{
  const ctx=setup(()=>({data:null}));
  const url=await ctx.repo.upload('/tmp/picture.jpg','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  assert.ok(ctx.calls[0].url.endsWith('/rpc/reserve_collection_cover'));
  assert.ok(ctx.calls[1].data instanceof ArrayBuffer);
  assert.ok(url.includes('/authenticated/item-covers/'+ctx.owner+'/'));
  const large=setup(()=>({data:null}),{bytes:new ArrayBuffer(2*1024*1024+1)});
  await assert.rejects(large.repo.upload('/tmp/large.jpg','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),/2 MB/);assert.equal(large.calls.length,0);
});
test('Model validates currency and dates; statistics preserve unpriced and foreign totals',()=>{
  const model=require('../lib/model');
  assert.throws(()=>model.fields({name:'A',category:'游戏',purchase_date:'2026-02-30'}),/日期/);
  assert.throws(()=>model.fields({name:'A',category:'游戏',currency:'USD',price:10}),/折算/);
  assert.throws(()=>model.fields({name:'A',category:'游戏',game_platform:'invalid'}),/选项/);
  const summary=model.stats([{category:'游戏',currency:'USD',price:10,price_cny:70,created_at:'2026-01-01',game_platform:'PC'},
    {category:'其他',currency:'CNY',price:null,created_at:'2026-02-01'}]);
  assert.equal(summary.total,'70.00');assert.equal(summary.unpriced,1);assert.equal(summary.count,2);
});
test('Existing-app subpackage routes and relayed covers preserve the Flutter storage origin',async()=>{
  const ctx=setup(request=>({data:request.data.paths.map(path=>({path,signedURL:'/object/sign/item-covers/'+path+'?token=test'}))}));
  ctx.config.routePrefix='/dearshelf';ctx.config.storageOrigin='https://original.supabase.co';
  assert.equal(require('../lib/page').url('form','?id=one'),'/dearshelf/pages/form/index?id=one');
  const url=ctx.config.storageOrigin+'/storage/v1/object/authenticated/item-covers/'+ctx.owner+'/a/one.jpg';
  const result=await ctx.repo.covers([url]);
  assert.ok(result[url].startsWith(ctx.config.supabaseUrl+'/storage/v1/object/sign/'));
  assert.equal(ctx.repo.objectPath(url),ctx.owner+'/a/one.jpg');
});
test('Collection rendering paginates and excludes long descriptions from the UI bridge',async()=>{
  setup(()=>({data:[]}));
  let definition;global.Page=value=>{definition=value;};
  require('../pages/collection/index');delete global.Page;
  const page={data:{...definition.data,prefs:{show_price:true}},
    all:Array.from({length:500},(_,i)=>({id:String(i),name:'藏'.repeat(120),category:'游戏',description:'说明'.repeat(10000),created_at:'2026-01-01',price:10,currency:'CNY',cover_image:null})),
    setData(value){this.data={...this.data,...value};}};
  definition.render.call(page);
  assert.equal(page.data.rows.length,30);assert.equal(page.data.count,500);
  assert.equal(page.data.pageCount,17);assert.equal(page.data.rows[0].description,undefined);
  assert.ok(Buffer.byteLength(JSON.stringify(page.data))<50000);
  await new Promise(resolve=>setImmediate(resolve));
});
