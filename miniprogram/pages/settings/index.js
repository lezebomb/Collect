const api=require('../../lib/api'); const repo=require('../../lib/repository'); const ui=require('../../lib/page'); const media=require('../../lib/media');
Page({
  data:{prefs:{},categories:[],email:'',newCategory:'',busy:true,error:'',ready:false},
  async onShow() {
    this.setData({busy:true,error:'',ready:false});
    try {
      if(!await ui.guard(this)) return;
      const [prefs,categories]=await Promise.all([repo.preferences(),repo.categories()]);
      this.setData({prefs,categories,email:api.current().user.email,ready:true});
    } catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  input(e) { this.setData({newCategory:e.detail.value}); },
  async toggle(e) {
    if(this.data.busy || !this.data.ready) return;
    const before=this.data.prefs; this.setData({busy:true,error:'',prefs:{...before,[e.currentTarget.dataset.key]:e.detail.value}});
    try { this.setData({prefs:await repo.savePreferences(this.data.prefs)}); }
    catch(error) { this.setData({prefs:before,error:error.message}); } finally { this.setData({busy:false}); }
  },
  async addCategory() {
    if(this.data.busy || !this.data.ready) return; this.setData({busy:true,error:''});
    try { await repo.addCategory(this.data.newCategory); this.setData({categories:await repo.categories(),newCategory:''}); }
    catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  async removeCategory(e) {
    const name=e.currentTarget.dataset.name;
    if(this.data.busy || !await ui.confirm(`删除分类“${name}”？已有收藏保留原分类。`)) return;
    this.setData({busy:true,error:''});
    try { await repo.removeCategory(name); this.setData({categories:await repo.categories()}); }
    catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  async renameCategory(e) {
    if(this.data.busy) return;
    const oldName=e.currentTarget.dataset.name;
    const result=await new Promise(resolve=>wx.showModal({title:'重命名分类',editable:true,placeholderText:oldName,success:resolve,fail:()=>resolve({confirm:false})}));
    if(!result.confirm || !result.content.trim()) return;
    this.setData({busy:true,error:''});
    try { await repo.renameCategory(oldName,result.content.trim()); this.setData({categories:await repo.categories()}); }
    catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  async wallpaper(e) {
    if(this.data.busy || !this.data.ready) return;
    this.setData({busy:true,error:''}); let uploaded=null;
    try {
      if(!e.currentTarget.dataset.remove) { const source=await media.chooseImage(); if(!source) return; uploaded=await repo.upload(await media.compact(source),'wallpaper'); }
      const old=this.data.prefs.wallpaper_url;
      const prefs=await repo.savePreferences({...this.data.prefs,wallpaper_url:uploaded});
      this.setData({prefs}); if(old && old!==uploaded) repo.queueCleanup(old);
    } catch(error) {
      if(uploaded && !error.transport && error.status) repo.queueCleanup(uploaded);
      this.setData({error:error.message});
    } finally { this.setData({busy:false}); }
  },
  async importList() {
    if(this.data.busy || !this.data.ready) return;
    const chosen=await new Promise(resolve=>wx.chooseMessageFile({count:1,type:'file',extension:['json'],success:resolve,fail:()=>resolve(null)}));
    if(!chosen) return;
    this.setData({busy:true,error:''});
    try {
      const file=chosen.tempFiles[0]; if(file.size>5*1024*1024) throw new Error('清单不能超过 5 MB');
      const text=await new Promise((resolve,reject)=>wx.getFileSystemManager().readFile({filePath:file.path,encoding:'utf8',success:r=>resolve(r.data),fail:()=>reject(new Error('无法读取清单'))}));
      const root=JSON.parse(text.replace(/^\uFEFF/,''));
      if(!root.items || !await ui.confirm(`导入清单中的 ${root.items.length} 件收藏？此操作会新增收藏。`)) return;
      const saved=await repo.importList(root); ui.toast(`已导入 ${saved.length} 件收藏`);
    } catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  async exportList() {
    if(this.data.busy || !this.data.ready) return;
    this.setData({busy:true,error:''});
    try {
      const items=await repo.items(true);
      const keys=['name','category','description','purchase_date','price','currency','price_cny','game_platform','game_content_type','game_edition','game_play_status'];
      const data=JSON.stringify({format:'dearshelf-item-list',version:1,items:items.map(item=>{const row={};keys.forEach(key=>row[key]=item[key]);return row;})},null,2);
      const filePath=wx.env.USER_DATA_PATH+'/Dearshelf-items.json';
      await new Promise((resolve,reject)=>wx.getFileSystemManager().writeFile({filePath,data,encoding:'utf8',success:resolve,fail:reject}));
      if(wx.shareFileMessage) await new Promise((resolve,reject)=>wx.shareFileMessage({filePath,fileName:'Dearshelf-items.json',success:resolve,fail:reject}));
      else throw new Error('当前微信版本不支持文件分享，请更新微信或使用现有 Flutter 应用导出');
    } catch(error) { this.setData({error:error.message || '导出未完成'}); } finally { this.setData({busy:false}); }
  },
  async logout() { if(this.data.busy || !await ui.confirm('退出登录并清除本机收藏缓存和草稿？')) return; await api.logout(); wx.reLaunch({url:ui.url('login')}); },
});
