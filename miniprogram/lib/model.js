'use strict';
const currencies = ['CNY','USD','HKD','JPY','EUR','GBP'];
function uuid() {
  // IDs identify records; authorization always uses the verified JWT + RLS.
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.floor(Math.random()*16); return (c === 'x' ? r : (r & 3) | 8).toString(16);
  });
}
function amount(value) {
  if (value === '' || value === null || value === undefined) return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0 || n > 9999999999.99) throw new Error('价格需为有效的非负金额');
  return Math.round(n * 100) / 100;
}
function fields(form) {
  const name = String(form.name || '').trim(); const category = String(form.category || '').trim();
  if (!name || name.length > 120) throw new Error('名称需为 1–120 个字');
  if (!category || category.length > 60) throw new Error('请填写 1–60 个字的分类');
  const description = String(form.description || '').trim();
  if (description.length > 20000) throw new Error('描述不能超过 20000 个字');
  const price = amount(form.price); const currency = form.currency || 'CNY';
  if (!currencies.includes(currency)) throw new Error('币种无效');
  const priceCny = price === null ? null : currency === 'CNY' ? price : amount(form.price_cny);
  if (price !== null && priceCny === null) throw new Error('请填写人民币折算额，以便统计');
  const date = form.purchase_date || null;
  if (date && (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(date)) || new Date(date).toISOString().slice(0,10) !== date)) throw new Error('购入日期无效');
  const result = { name,category,description,price,currency,price_cny:priceCny,purchase_date:date,updated_at:new Date().toISOString() };
  ['game_platform','game_content_type','game_edition','game_play_status'].forEach(key => { result[key] = form[key] || null; });
  const options = {game_platform:['Nintendo','PC'],game_content_type:['本体','DLC','本体+DLC'],game_edition:['实体版','数字版'],game_play_status:['吃灰中','游玩中','已通关','全成就']};
  Object.keys(options).forEach(key=>{if(result[key] && !options[key].includes(result[key])) throw new Error('游戏字段选项无效');});
  if (result.game_platform === 'PC') result.game_edition = '数字版';
  return result;
}
function cny(item) { return item.currency === 'CNY' || !item.currency ? item.price : item.price_cny; }
function stats(items, category = '', year = '') {
  const selected = items.filter(item => (!category || item.category === category) && (!year || (item.purchase_date || item.created_at).slice(0,4) === String(year)));
  let cents = 0; let unpriced = 0; const groups = {}; const months = {}; const games = {};
  selected.forEach(item => {
    const n = cny(item); if (n === null || n === undefined) unpriced++; else cents += Math.round(Number(n)*100);
    groups[item.category] = (groups[item.category] || 0) + 1;
    const month = (item.purchase_date || item.created_at).slice(0,7);
    months[month] = (months[month] || 0) + (n == null ? 0 : Math.round(Number(n)*100));
    if (item.game_platform || item.category === '游戏') { const status = item.game_play_status || '未填写'; games[status] = (games[status] || 0) + 1; }
  });
  return { count:selected.length, total:(cents/100).toFixed(2), unpriced,
    groups:Object.keys(groups).map(name => ({name,count:groups[name]})),
    months:Object.keys(months).sort().reverse().map(name => ({name,total:(months[name]/100).toFixed(2)})),
    games:Object.keys(games).map(name => ({name,count:games[name]})) };
}
function display(item, prefs = {}) {
  const start = new Date((item.purchase_date || item.created_at).slice(0,10) + 'T00:00:00');
  const today = new Date(); today.setHours(0,0,0,0);
  const days = Math.max(0, Math.round((today-start)/86400000));
  const converted = cny(item);
  return { ...item, priceText: item.price == null ? '' : `${item.currency || 'CNY'} ${Number(item.price).toFixed(2)}`,
    daysText: prefs.show_owned_days ? `${days} 天` : '',
    dailyText: prefs.show_daily_cost && converted != null && days > 0 ? `¥${(converted/days).toFixed(2)}/天` : '' };
}
module.exports = { uuid,fields,amount,cny,stats,display,currencies };
