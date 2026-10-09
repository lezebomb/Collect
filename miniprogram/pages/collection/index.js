const api = require('../../lib/api'); const repo = require('../../lib/repository');
const model = require('../../lib/model'); const ui = require('../../lib/page');
Page({
  data:{rows:[],count:0,query:'',category:'',categories:[],sortIndex:0,sorts:['最新添加','最早添加','价格从高到低','价格从低到高','名称'],offset:0,pageNumber:1,pageCount:1,
    busy:false,error:'',syncing:false,selecting:false,selected:[],prefs:{},wallpaperUrl:''},
  async onShow() { await this.load(false); repo.flushCleanup().catch(()=>{}); },
  onHide() { this.loadVersion = (this.loadVersion || 0) + 1; },
  onUnload() { this.loadVersion = (this.loadVersion || 0) + 1; },
  async load(refresh) {
    const version = this.loadVersion = (this.loadVersion || 0) + 1;
    this.setData({syncing:true,error:''});
    try {
      if (!await ui.guard(this)) return;
      if (version !== this.loadVersion) return;
      this.all = this.all || repo.localSnapshot(); this.render();
      const [rows,categories,prefs] = await Promise.all([repo.items(refresh, rows=>{
        if (version===this.loadVersion) { this.all=rows; this.render(); }
      }),repo.categories(),repo.preferences()]);
      if (version !== this.loadVersion) return;
      this.all = rows; this.setData({categories,prefs}); this.render();
      if(prefs.wallpaper_url) { const urls=await repo.covers([prefs.wallpaper_url]); if(version===this.loadVersion) this.setData({wallpaperUrl:urls[prefs.wallpaper_url] || ''}); }
      else this.setData({wallpaperUrl:''});
    } catch (error) { if (version===this.loadVersion) this.setData({error:error.message}); }
    finally { if (version===this.loadVersion) this.setData({syncing:false}); }
  },
  render() {
    const query=this.data.query.trim().toLowerCase(); const category=this.data.category;
    const rows=(this.all || []).filter(row=>(!category || row.category===category) && (!query || (row.name+' '+row.description).toLowerCase().includes(query)));
    rows.sort((a,b)=>this.data.sortIndex===1 ? a.created_at.localeCompare(b.created_at)
      : this.data.sortIndex===2 ? (model.cny(b)||0)-(model.cny(a)||0)
      : this.data.sortIndex===3 ? (model.cny(a)||0)-(model.cny(b)||0)
      : this.data.sortIndex===4 ? a.name.localeCompare(b.name) : b.created_at.localeCompare(a.created_at));
    const offset=Math.min(this.data.offset,Math.max(0,Math.floor((rows.length-1)/30)*30));
    // Descriptions stay in JS memory for filtering; transmitting every full
    // record through setData would exceed WeChat's bridge payload limit.
    const visible=rows.slice(offset,offset+30).map(row=>{
      const value=model.display(row,this.data.prefs);
      return {id:row.id,name:row.name,category:row.category,cover_image:row.cover_image,
        priceText:value.priceText,daysText:value.daysText,dailyText:value.dailyText,selected:this.data.selected.includes(row.id)};
    });
    const renderVersion=this.renderVersion=(this.renderVersion || 0)+1;
    this.setData({rows:visible,count:rows.length,offset,pageNumber:Math.floor(offset/30)+1,pageCount:Math.max(1,Math.ceil(rows.length/30))});
    repo.covers(visible.map(row=>row.cover_image)).then(covers=>{
      if(renderVersion===this.renderVersion) this.setData({rows:visible.map(row=>({...row,coverUrl:covers[row.cover_image] || ''}))});
    }).catch(()=>{});
  },
  input(e) { this.setData({query:e.detail.value,offset:0}); this.render(); },
  category(e) { this.setData({category:e.currentTarget.dataset.value,offset:0}); this.render(); },
  sort(e) { this.setData({sortIndex:Number(e.detail.value),offset:0}); this.render(); },
  previous() { this.setData({offset:Math.max(0,this.data.offset-30)}); this.render(); wx.pageScrollTo({scrollTop:0}); },
  next() { if(this.data.pageNumber>=this.data.pageCount) return; this.setData({offset:this.data.offset+30}); this.render(); wx.pageScrollTo({scrollTop:0}); },
  async onPullDownRefresh() { await this.load(true); wx.stopPullDownRefresh(); },
  refresh() { this.load(true); },
  add() { ui.go('form'); }, stats() { ui.go('stats'); }, settings() { ui.go('settings'); },
  open(e) {
    const id=e.currentTarget.dataset.id;
    if (!this.data.selecting) return ui.go('detail',`?id=${id}`);
    const selected=this.data.selected.includes(id)?this.data.selected.filter(value=>value!==id):[...this.data.selected,id];
    if(selected.length>100) return ui.toast('每次最多选择 100 件');
    this.setData({selected}); this.render();
  },
  select() { this.setData({selecting:!this.data.selecting,selected:[]}); this.render(); },
  async removeSelected() {
    if(this.data.busy || !this.data.selected.length || !await ui.confirm(`删除选中的 ${this.data.selected.length} 件收藏？`)) return;
    this.setData({busy:true,error:''});
    try { await repo.deleteMany(this.data.selected); this.setData({selected:[],selecting:false}); await this.load(true); }
    catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  async moveSelected(e) {
    if(this.data.busy || !this.data.selected.length) return;
    this.setData({busy:true,error:''});
    try { await repo.bulkCategory(this.data.selected,this.data.categories[Number(e.detail.value)]); this.setData({selected:[],selecting:false}); await this.load(true); }
    catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
});
