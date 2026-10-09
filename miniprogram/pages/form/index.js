const api=require('../../lib/api'); const repo=require('../../lib/repository');
const model=require('../../lib/model'); const ui=require('../../lib/page'); const media=require('../../lib/media');
Page({
  data:{form:{name:'',category:'',description:'',price:'',price_cny:'',currency:'CNY',purchase_date:'',game_platform:'',game_content_type:'',game_edition:'',game_play_status:''},
    categories:[],currencies:model.currencies,platforms:['','Nintendo','PC'],contentTypes:['','本体','DLC','本体+DLC'],editions:['','实体版','数字版'],playStatuses:['','吃灰中','游玩中','已通关','全成就'],
    coverUrl:'',filePath:'',removeCover:false,busy:true,error:'',editing:false},
  async onLoad(options) {
    this.id=options.id || model.uuid(); this.ready=false; this.saved=false;
    try {
      if(!await ui.guard(this)) return;
      const [categories,initial]=await Promise.all([repo.categories(),options.id ? repo.getItem(options.id) : Promise.resolve(null)]);
      this.initial=initial;
      const form=initial ? {...initial,price:initial.price == null?'':String(initial.price),price_cny:initial.price_cny == null?'':String(initial.price_cny)} : {...this.data.form,category:categories[0] || ''};
      this.setData({categories:[...new Set([...categories,form.category].filter(Boolean))],form,editing:!!initial});
      if(initial && initial.cover_image) { const urls=await repo.covers([initial.cover_image]); this.setData({coverUrl:urls[initial.cover_image] || ''}); }
      if(!initial) {
        const draft=wx.getStorageSync(`dearshelf:${api.owner()}:draft`);
        if(draft && await ui.confirm('恢复上次尚未保存的收藏草稿？')) {
          this.id=draft.id; this.setData({form:draft.form,filePath:draft.filePath || '',coverUrl:draft.filePath || ''});
        }
      }
      this.ready=true;
    } catch(error) { this.setData({error:error.message}); }
    finally { this.setData({busy:false}); }
  },
  input(e) { const key=e.currentTarget.dataset.key; this.setData({['form.'+key]:e.detail.value}); },
  pick(e) { const key=e.currentTarget.dataset.key; const values=this.data[e.currentTarget.dataset.options]; this.setData({['form.'+key]:values[Number(e.detail.value)]}); },
  date(e) { this.setData({'form.purchase_date':e.detail.value}); },
  clearDate() { this.setData({'form.purchase_date':''}); },
  async choose() {
    if(this.data.busy) return; this.setData({busy:true,error:''});
    try { const image=await media.chooseImage(); if(image) { const filePath=await media.compact(image); this.setData({filePath,coverUrl:filePath,removeCover:false}); } }
    catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  removeCover() { this.setData({removeCover:true,filePath:'',coverUrl:''}); },
  async keepDraft() {
    if(!this.ready || this.data.editing || this.saved || !api.current()) return;
    const owner=api.owner();
    if(!this.data.form.name.trim() && !this.data.form.description.trim() && !this.data.filePath && !this.data.form.price && !this.data.form.purchase_date) return;
    let filePath=this.data.filePath;
    if(filePath) {
      try { filePath=await new Promise((resolve,reject)=>wx.getFileSystemManager().saveFile({tempFilePath:filePath,success:r=>resolve(r.savedFilePath),fail:reject})); }
      catch(_) { filePath=''; }
    }
    try {
      if(!api.current() || api.owner()!==owner) return;
      const key=`dearshelf:${owner}:draft`;const previous=wx.getStorageSync(key);
      wx.setStorageSync(key,{id:this.id,form:this.data.form,filePath});
      if(previous && previous.filePath && previous.filePath!==filePath) {
        wx.getFileSystemManager().removeSavedFile({filePath:previous.filePath,fail:()=>{}});
      }
    } catch(_) {}
  },
  onUnload() { this.keepDraft().catch(()=>{}); },
  async save() {
    if(this.data.busy || !this.ready || this.saved) return;
    this.setData({busy:true,error:''});
    try {
      model.fields(this.data.form);
      await repo.save(this.data.form,{id:this.id,initial:this.initial,filePath:this.data.filePath,removeCover:this.data.removeCover});
      this.saved=true;
      if(!this.data.editing) {
        try {
          const key=`dearshelf:${api.owner()}:draft`;const old=wx.getStorageSync(key);
          wx.removeStorageSync(key);
          if(old && old.filePath) wx.getFileSystemManager().removeSavedFile({filePath:old.filePath,fail:()=>{}});
        } catch(_) {}
      }
      ui.toast('收藏已保存'); wx.navigateBack({delta:1,fail:ui.home});
    } catch(error) { this.setData({error:error.message}); }
    finally { this.setData({busy:false}); }
  },
});
