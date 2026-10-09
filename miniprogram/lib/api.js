'use strict';
const config = require('../config');
const SESSION_KEY = 'dearshelf:session';
let session = null;
let loaded = false;
let epoch = 0;
let refreshing = null;
const listeners = new Set();

function configured() {
  return /^https:\/\/[a-z0-9.-]+$/i.test(config.supabaseUrl) &&
    !config.supabaseUrl.includes('YOUR_') && config.publishableKey &&
    config.publishableKey.startsWith('sb_publishable_') && !config.publishableKey.includes('YOUR_');
}
function current() {
  if (!loaded) {
    loaded = true;
    try { session = wx.getStorageSync(SESSION_KEY) || null; } catch (_) { session = null; }
  }
  return session;
}
function saveSession(value) {
  session = value; loaded = true;
  if (value) wx.setStorageSync(SESSION_KEY, value);
  else wx.removeStorageSync(SESSION_KEY);
}
function subscribe(callback) { listeners.add(callback); return () => listeners.delete(callback); }
function clearSession() {
  const owner = current() && current().user && current().user.id;
  epoch++;
  saveSession(null);
  if (owner) {
    try {
      const draft=wx.getStorageSync(`dearshelf:${owner}:draft`);
      if(draft && draft.filePath) wx.getFileSystemManager().removeSavedFile({filePath:draft.filePath,fail:()=>{}});
    } catch(_) {}
    ['snapshot','draft'].forEach(key => { try { wx.removeStorageSync(`dearshelf:${owner}:${key}`); } catch (_) {} });
  }
  listeners.forEach(fn => fn());
}
function transport(route, { method = 'GET', data, token, headers = {}, responseType = 'text' } = {}) {
  if (!configured()) return Promise.reject(new Error('请先填写 miniprogram/config.js 的 Supabase 配置'));
  return new Promise((resolve, reject) => wx.request({
    url: config.supabaseUrl + route, method, data, responseType, timeout:15000,
    header: { apikey:config.publishableKey, ...(token ? { Authorization:`Bearer ${token}` } : {}), ...headers },
    success(res) {
      if (res.statusCode >= 200 && res.statusCode < 300) return resolve(res.data);
      const body = res.data || {};
      const error = new Error(body.message || body.msg || body.error_description || body.error || `请求失败 (${res.statusCode})`);
      error.status = res.statusCode; reject(error);
    },
    fail() { const error = new Error('网络请求未完成。保存操作可能已成功，请刷新确认后再重试。'); error.transport = true; reject(error); },
  }));
}
async function token(force = false) {
  const state = current();
  if (!state) throw new Error('请先登录');
  if (!force && state.expires_at > Date.now()/1000 + 60) return state.access_token;
  if (!refreshing) {
    const generation = epoch;
    refreshing = transport('/auth/v1/token?grant_type=refresh_token', {
      method:'POST', data:{ refresh_token:state.refresh_token },
    }).then(value => {
      if (generation !== epoch) throw new Error('登录会话已改变');
      value.expires_at = value.expires_at || Date.now()/1000 + value.expires_in;
      saveSession(value); return value.access_token;
    }).catch(error => {
      if (generation === epoch && [400,401,403].includes(error.status)) clearSession();
      throw error;
    }).finally(() => { refreshing = null; });
  }
  return refreshing;
}
async function request(route, options = {}) {
  const generation = epoch;
  let bearer = await token();
  let value;
  try { value = await transport(route, { ...options, token:bearer }); }
  catch (error) {
    // A rejected JWT never executes a mutation. Retrying here is safe.
    if (error.status !== 401) throw error;
    bearer = await token(true);
    value = await transport(route, { ...options, token:bearer });
  }
  if (generation !== epoch) throw new Error('登录会话已改变');
  return value;
}
async function login(email, password) {
  const generation = ++epoch;
  const value = await transport('/auth/v1/token?grant_type=password', {method:'POST',data:{email:email.trim().toLowerCase(),password}});
  if (generation !== epoch) throw new Error('登录会话已改变');
  value.expires_at = value.expires_at || Date.now()/1000 + value.expires_in;
  saveSession(value);
  try { await ensureAccess(); } catch (error) { clearSession(); throw error; }
  return value.user;
}
async function ensureAccess() {
  if (await request('/rest/v1/rpc/collection_access_allowed', {method:'POST',data:{}}) !== true) {
    throw new Error('此邮箱尚未获准使用，或尚未完成邮箱验证，请联系管理员');
  }
}
async function logout() {
  const state = current();
  clearSession();
  if (state) transport('/auth/v1/logout', {method:'POST',token:state.access_token}).catch(() => {});
}
function owner() {
  const value = current(); if (!value || !value.user) throw new Error('请先登录');
  if (!/^[0-9a-f-]{36}$/i.test(value.user.id)) throw new Error('登录身份无效，请重新登录');
  return value.user.id;
}
function rpc(name, data = {}) { return request('/rest/v1/rpc/' + name, {method:'POST',data}); }
function signup(email, password) {
  if (!config.allowRegistration) throw new Error('此应用采用邀请制，请联系管理员开通账号');
  return transport('/auth/v1/signup',{method:'POST',data:{email:email.trim().toLowerCase(),password}});
}
module.exports = { config, configured, current, owner, login, logout, request, rpc, ensureAccess, signup, subscribe, clearSession };
