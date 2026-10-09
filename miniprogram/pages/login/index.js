const api = require('../../lib/api');
const ui = require('../../lib/page');
Page({
  data:{email:'',password:'',busy:false,error:'',register:false,allowRegistration:api.config.allowRegistration},
  input(e) { this.setData({[e.currentTarget.dataset.key]:e.detail.value}); },
  toggle() { this.setData({register:!this.data.register,error:''}); },
  async submit() {
    if (this.data.busy) return;
    this.setData({busy:true,error:''});
    try {
      if (!this.data.email.includes('@') || this.data.password.length < 6) throw new Error('请填写有效邮箱和至少 6 位密码');
      if (this.data.register) { await api.signup(this.data.email,this.data.password); this.setData({register:false,error:'请完成邮箱验证后再登录。'}); }
      else { await api.login(this.data.email,this.data.password); this.setData({password:''}); ui.home(); }
    } catch (error) { this.setData({error:error.message}); }
    finally { this.setData({busy:false}); }
  },
  async onShow() {
    if (api.current()) {
      this.setData({busy:true});
      try { await api.ensureAccess(); ui.home(); } catch (error) { this.setData({error:error.message}); }
      finally { this.setData({busy:false}); }
    }
  },
  async logout() { await api.logout(); this.setData({error:'',password:''}); },
});
