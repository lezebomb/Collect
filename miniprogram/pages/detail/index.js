const repo=require('../../lib/repository'); const model=require('../../lib/model'); const ui=require('../../lib/page');
Page({
  data:{item:null,coverUrl:'',busy:false,error:''},
  onLoad(options) { this.id=options.id; },
  async onShow() {
    this.setData({busy:true,error:''});
    try {
      if(!await ui.guard(this)) return;
      const item=await repo.getItem(this.id); this.setData({item:model.display(item,{show_owned_days:true,show_daily_cost:true})});
      const urls=await repo.covers([item.cover_image]); this.setData({coverUrl:urls[item.cover_image] || ''});
    } catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  edit() { if(this.data.item && !this.data.busy) ui.go('form',`?id=${this.id}`); },
  async remove() {
    if(this.data.busy || !this.data.item || !await ui.confirm('删除这件收藏？')) return;
    this.setData({busy:true,error:''});
    try { await repo.deleteItem(this.data.item); wx.navigateBack({delta:1,fail:ui.home}); }
    catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  preview() { if(this.data.coverUrl) wx.previewImage({urls:[this.data.coverUrl]}); },
});
