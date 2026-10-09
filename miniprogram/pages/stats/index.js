const repo=require('../../lib/repository'); const model=require('../../lib/model'); const ui=require('../../lib/page');
Page({
  data:{summary:null,categories:['全部'],years:['全部'],categoryIndex:0,yearIndex:0,busy:true,error:''},
  async onShow() {
    this.setData({busy:true,error:''});
    try {
      if(!await ui.guard(this)) return;
      this.items=await repo.items();
      this.setData({categories:['全部',...new Set(this.items.map(row=>row.category))],years:['全部',...new Set(this.items.map(row=>(row.purchase_date || row.created_at).slice(0,4)))].sort((a,b)=>a==='全部'?-1:b==='全部'?1:b.localeCompare(a))});
      this.render();
    } catch(error) { this.setData({error:error.message}); } finally { this.setData({busy:false}); }
  },
  filter(e) { this.setData({[e.currentTarget.dataset.key]:Number(e.detail.value)}); this.render(); },
  render() { this.setData({summary:model.stats(this.items || [],this.data.categoryIndex?this.data.categories[this.data.categoryIndex]:'',this.data.yearIndex?this.data.years[this.data.yearIndex]:'')}); },
});
