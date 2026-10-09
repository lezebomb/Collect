'use strict';
const api = require('./api');
const model = require('./model');
let cache = null; let pending = null; let revision = 0;
const signed = new Map(); const signing = new Map();
api.subscribe(() => { cache = null; pending = null; signed.clear(); signing.clear(); revision++; });
const own = () => 'user_id=eq.' + encodeURIComponent(api.owner());
const storageOrigin = () => api.config.storageOrigin || api.config.supabaseUrl;
const objectPath = url => {
  const prefix = storageOrigin() + '/storage/v1/object/authenticated/item-covers/';
  if (typeof url !== 'string' || !url.startsWith(prefix)) return null;
  const value = url.slice(prefix.length);
  return value.startsWith(api.owner() + '/') && !value.includes('..') ? value : null;
};
function invalidate() { cache = null; revision++; }
async function items(refresh = false, onPage) {
  const owner = api.owner();
  if (refresh) invalidate();
  if (cache && cache.owner === owner) return cache.rows;
  if (pending && pending.revision === revision && pending.owner === owner) return pending.promise;
  const start = revision;
  const promise = (async () => {
    const rows = []; let offset = 0;
    while (true) {
      const page = await api.request(`/rest/v1/items?${own()}&select=*&order=created_at.desc,id.desc&limit=200&offset=${offset}`);
      if (!Array.isArray(page)) throw new Error('收藏数据格式无效');
      rows.push(...page);
      if (onPage && revision === start && api.owner() === owner) onPage(rows.slice());
      if (page.length < 200) break;
      offset += 200;
    }
    if (revision !== start) return items();
    cache = {owner,rows};
    try { wx.setStorageSync(`dearshelf:${owner}:snapshot`,rows); } catch (_) {}
    return rows;
  })();
  const record = {owner,revision:start,promise}; pending = record;
  try { return await promise; } finally { if (pending === record) pending = null; }
}
function localSnapshot() {
  try {
    const value = wx.getStorageSync(`dearshelf:${api.owner()}:snapshot`);
    return Array.isArray(value) && value.every(row => row.user_id === api.owner()) ? value : [];
  } catch (_) { return []; }
}
async function getItem(id) {
  if (!/^[0-9a-f-]{36}$/i.test(id || '')) throw new Error('收藏 ID 无效');
  const rows = await api.request(`/rest/v1/items?${own()}&id=eq.${id}&select=*&limit=1`);
  if (!rows.length) throw new Error('收藏不存在或已删除'); return rows[0];
}
function categories() { return api.request(`/rest/v1/user_categories?${own()}&select=name&order=created_at.asc,name.asc`).then(rows => rows.map(row => row.name)); }
async function preferences() {
  const rows = await api.request(`/rest/v1/user_preferences?${own()}&select=*&limit=1`);
  return rows[0] || {show_price:false,show_owned_days:false,show_daily_cost:false,wallpaper_url:null};
}
function savePreferences(prefs) {
  return api.request('/rest/v1/user_preferences?on_conflict=user_id', {method:'POST',
    headers:{Prefer:'resolution=merge-duplicates,return=representation'},
    data:{user_id:api.owner(),show_price:!!prefs.show_price,show_owned_days:!!prefs.show_owned_days,
      show_daily_cost:!!prefs.show_daily_cost,wallpaper_url:prefs.wallpaper_url || null,updated_at:new Date().toISOString()},
  }).then(rows => rows[0]);
}
function addCategory(name) {
  name = name.trim(); if (!name || name.length > 60) throw new Error('分类名称需为 1–60 个字');
  return api.request('/rest/v1/user_categories?on_conflict=user_id,name',{method:'POST',headers:{Prefer:'resolution=ignore-duplicates'},data:{user_id:api.owner(),name}});
}
function removeCategory(name) { return api.request(`/rest/v1/user_categories?${own()}&name=eq.${encodeURIComponent(name)}`,{method:'DELETE'}); }
async function renameCategory(oldName, newName) {
  await api.rpc('rename_collection_category',{old_name:oldName,new_name:newName}); invalidate();
}
async function covers(urls) {
  const paths = [...new Set(urls.map(objectPath).filter(Boolean))];
  const missing = paths.filter(path => !signed.has(path) || signed.get(path).expires <= Date.now());
  const waits = [];
  for (let i=0; i<missing.length; i+=50) {
    const chunk = missing.slice(i,i+50).filter(path => !signing.has(path));
    if (!chunk.length) continue;
    const promise = api.request('/storage/v1/object/sign/item-covers', {method:'POST',data:{paths:chunk,expiresIn:3600}})
      .then(rows => {
        if (!Array.isArray(rows)) throw new Error('图片签名结果无效');
        rows.forEach(row => {
          const link = row.signedURL || row.signedUrl;
          if (row.error || !link || !chunk.includes(row.path)) return;
          const url = link.startsWith(storageOrigin()+'/storage/v1/')
            ? api.config.supabaseUrl + link.slice(storageOrigin().length)
            : link.startsWith('/object/') ? api.config.supabaseUrl + '/storage/v1' + link
            : link.startsWith('/') ? api.config.supabaseUrl + link : link;
          // Never show a signed URL from an untrusted host.
          if (url.startsWith(api.config.supabaseUrl + '/')) signed.set(row.path,{url,expires:Date.now()+55*60*1000});
        });
      }).finally(() => chunk.forEach(path => signing.delete(path)));
    chunk.forEach(path => signing.set(path,promise)); waits.push(promise);
  }
  await Promise.all([...waits,...missing.map(path=>signing.get(path)).filter(Boolean)]);
  const result = {};
  urls.forEach(url => { const path = objectPath(url); const value = signed.get(path); result[url] = value && value.expires > Date.now() ? value.url : ''; });
  return result;
}
function readFile(filePath) {
  return new Promise((resolve,reject) => wx.getFileSystemManager().readFile({filePath,success:r=>resolve(r.data),fail:()=>reject(new Error('图片读取失败，请重新选择'))}));
}
async function upload(filePath, id) {
  const bytes = await readFile(filePath);
  if (!(bytes instanceof ArrayBuffer) || bytes.byteLength > 2*1024*1024) throw new Error('图片不能超过 2 MB，请压缩或重新选择');
  const header = new Uint8Array(bytes);
  let ext, mime;
  if (header[0] === 0xff && header[1] === 0xd8) { ext='jpg'; mime='image/jpeg'; }
  else if (header[0] === 0x89 && header[1] === 0x50 && header[2] === 0x4e && header[3] === 0x47) { ext='png'; mime='image/png'; }
  else if (header[0] === 0x52 && header[1] === 0x49 && header[8] === 0x57 && header[9] === 0x45) { ext='webp'; mime='image/webp'; }
  else throw new Error('请选择 JPG、PNG 或 WebP 图片');
  const path = `${api.owner()}/${id}/${model.uuid()}.${ext}`;
  await api.rpc('reserve_collection_cover',{object_path:path});
  try { await api.request('/storage/v1/object/item-covers/' + path, {method:'POST',data:bytes,headers:{'Content-Type':mime,'x-upsert':'false'}}); }
  catch (error) {
    if (!error.transport) api.rpc('release_collection_cover',{object_path:path}).catch(() => {});
    throw error;
  }
  return storageOrigin() + '/storage/v1/object/authenticated/item-covers/' + path;
}
function queueCleanup(url) {
  if (!url) return;
  const owner = api.owner(); const key = `dearshelf:${owner}:cleanup`;
  try { const queue = wx.getStorageSync(key) || []; if (!queue.includes(url)) wx.setStorageSync(key,[...queue,url]); } catch (_) {}
  flushCleanup().catch(() => {});
}
let cleaning = false;
async function flushCleanup() {
  if (cleaning || !api.current()) return; cleaning = true;
  const owner = api.owner(); const key = `dearshelf:${owner}:cleanup`;
  try {
    const queue = wx.getStorageSync(key) || [];
    for (const url of queue.slice(0,8)) {
      const path = objectPath(url); if (!path) continue;
      try {
        await api.request('/storage/v1/object/item-covers',{method:'DELETE',data:{prefixes:[path]}});
        await api.rpc('release_collection_cover',{object_path:path});
        signed.delete(path);
        if (api.owner() === owner) wx.setStorageSync(key,(wx.getStorageSync(key) || []).filter(value=>value!==url));
      } catch (_) { break; }
    }
  } finally { cleaning = false; }
}
async function save(form, { id, initial, filePath, removeCover } = {}) {
  if (!id) throw new Error('缺少稳定的收藏 ID');
  const data = model.fields(form); let uploaded = null; let started = false;
  const oldCover = initial && initial.cover_image;
  try {
    if (filePath) uploaded = await upload(filePath,id);
    data.cover_image = uploaded || (removeCover ? null : oldCover || null);
    started = true;
    let rows;
    if (initial) rows = await api.request(`/rest/v1/items?${own()}&id=eq.${id}`,{method:'PATCH',data,headers:{Prefer:'return=representation'}});
    else rows = await api.request('/rest/v1/items',{method:'POST',data:{...data,id,user_id:api.owner()},headers:{Prefer:'return=representation'}});
    if (!rows || !rows.length) throw new Error('收藏不存在或没有更新权限，请刷新确认');
    invalidate(); if (oldCover && oldCover !== data.cover_image) queueCleanup(oldCover);
    return rows[0];
  } catch (error) {
    // Reconcile an interrupted response using the SAME ID. Never blindly retry.
    if (started) {
      try {
        const row = await getItem(id);
        if (Object.keys(data).filter(key=>key!=='updated_at').every(key=>row[key] === data[key])) {
          invalidate(); if (oldCover && oldCover !== data.cover_image) queueCleanup(oldCover); return row;
        }
      } catch (_) {}
    }
    if (uploaded && !error.transport && error.status) queueCleanup(uploaded);
    invalidate(); throw error;
  }
}
async function deleteItem(item) {
  const rows = await api.request(`/rest/v1/items?${own()}&id=eq.${item.id}&select=id,cover_image`,{method:'DELETE',headers:{Prefer:'return=representation'}});
  invalidate(); rows.forEach(row => queueCleanup(row.cover_image));
}
async function bulkCategory(ids, category) {
  if (!ids.length || ids.length > 100 || ids.some(id=>!/^[0-9a-f-]{36}$/i.test(id))) throw new Error('每次可处理 1–100 件收藏');
  await api.request(`/rest/v1/items?${own()}&id=in.(${ids.join(',')})`,{method:'PATCH',data:{category,updated_at:new Date().toISOString()}}); invalidate();
}
async function deleteMany(ids) {
  if (!ids.length || ids.length > 100 || ids.some(id=>!/^[0-9a-f-]{36}$/i.test(id))) throw new Error('每次可处理 1–100 件收藏');
  const rows = await api.request(`/rest/v1/items?${own()}&id=in.(${ids.join(',')})&select=id,cover_image`,{method:'DELETE',headers:{Prefer:'return=representation'}});
  invalidate(); rows.forEach(row=>queueCleanup(row.cover_image)); return rows.length;
}
async function importList(root, stableRows) {
  if (!root || root.format !== 'dearshelf-item-list' || root.version !== 1 || !Array.isArray(root.items) || !root.items.length || root.items.length > 500) throw new Error('请使用 Dearshelf 藏品清单模板，每次最多 500 件');
  const rows = stableRows || root.items.map(form => ({...model.fields(form),id:model.uuid(),user_id:api.owner(),cover_image:null}));
  try {
    const saved = await api.request('/rest/v1/items',{method:'POST',data:rows,headers:{Prefer:'return=representation'}}); invalidate(); return saved;
  } catch (error) {
    try {
      const confirmed = await api.request(`/rest/v1/items?${own()}&id=in.(${rows.map(row=>row.id).join(',')})&select=id`);
      if (confirmed.length === rows.length) { invalidate(); return confirmed; }
    } catch (_) {}
    error.importRows = rows; invalidate(); throw error;
  }
}
module.exports = { items,localSnapshot,getItem,categories,preferences,savePreferences,addCategory,removeCategory,renameCategory,
  covers,upload,save,deleteItem,bulkCategory,deleteMany,importList,invalidate,flushCleanup,queueCleanup,objectPath };
