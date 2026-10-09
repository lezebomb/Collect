const api = require('./api');
function url(page, query = '') { return `${api.config.routePrefix || ''}/pages/${page}/index${query}`; }
function go(page, query = '') { return wx.navigateTo({url:url(page,query)}); }
function home() { wx.reLaunch({url:url('collection')}); }
async function guard(page) {
  if (!api.current()) { wx.reLaunch({url:url('login')}); return false; }
  try { await api.ensureAccess(); return true; }
  catch (error) { if (page) page.setData({error:error.message}); return false; }
}
function confirm(content) { return new Promise(resolve=>wx.showModal({title:'请确认',content,success:r=>resolve(r.confirm),fail:()=>resolve(false)})); }
function toast(title) { wx.showToast({title,icon:'none'}); }
module.exports = { url,go,home,guard,confirm,toast };
