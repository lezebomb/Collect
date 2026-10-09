# Dearshelf 原生微信小程序模块

此目录可独立导入微信开发者工具，也可以作为分包接入已有个人主体小程序。与 Flutter 应用共用 Supabase 账号、收藏、分类、展示设置和私有封面。

当前已实现：邮箱密码登录、白名单检查、列表与本机缓存、搜索/分类/排序、单件新增编辑删除、批量删除/改分类、相册/拍照封面压缩上传、草稿、人民币折算额、游戏字段、按分类/年份统计、分类添加删除改名、展示开关、壁纸、JSON 清单导入导出。

Flutter 的封面裁剪编辑器、ML Kit 拍照文字识别、多来源图片资料搜索、自动汇率及含图片的完整 ZIP 备份继续在 Flutter 应用中使用。本模块没有假装提供这些平台依赖功能；JSON 清单不包含图片，也不能代替完整备份。

## 独立检查

1. 公开源码的 `config.js` 使用占位配置；填写自己的 Supabase HTTPS URL 和 Publishable Key，并保持 `allowRegistration: false`。也可以用下述打包脚本从被忽略的本地配置生成包。
2. `project.config.json` 已填入 Geek Mia 的 AppID `wxc1459acced9a2a5d`。
3. 在微信后台配置后端域名，执行访问控制迁移并加入白名单，详见 [接入说明](../docs/wechat-and-private-access.md)。
4. 用微信开发者工具导入本目录。实际编译、登录、文件选择及相机行为需要工具和后续真机验证。

## 接入已有小程序

1. 将本目录复制为已有小程序项目的 `dearshelf/` 目录，保留 `lib/`、`pages/`、`config.js`、`app.wxss`。原项目自己的 `app.js`、`app.json`、`project.config.json` 不要被覆盖。
2. 将复制后的 `dearshelf/config.js` 中 `routePrefix` 改为 `'/dearshelf'`。
3. 在原项目 `app.json` 的 `subPackages` 数组中加入以下一项。已有分包要保留。

```json
{
  "root": "dearshelf",
  "name": "dearshelf",
  "pages": [
    "pages/login/index", "pages/collection/index", "pages/form/index",
    "pages/detail/index", "pages/stats/index", "pages/settings/index"
  ]
}
```

4. 在现有入口按钮的处理函数中调用：

```javascript
wx.navigateTo({ url: '/dearshelf/pages/login/index' });
```

每个模块页面自行引入共享样式，不需要修改现有应用的全局样式。分包仍属于已有小程序，账号数据权限由 Supabase 验证。

## 本地检查

在 Flutter 项目根目录运行：

```powershell
node --test miniprogram/tests/client.test.cjs
python scripts/verify_miniprogram.py
```

这些检查覆盖 JS、页面结构、事件绑定、会话刷新、数据隔离、图片签名、保存响应丢失等逻辑。它们不替代微信开发者工具的 WXML/WXSS 编译或真机体验。

## 生成已配置的交付包

从项目根目录运行以下命令，将本机公开后端配置写入交付包：

```powershell
python scripts/build_wechat_package.py --config config/local.json --appid wxc1459acced9a2a5d
```

结果位于 `build/wechat-package/`：`dearshelf-standalone.zip` 可解压并独立导入开发者工具；`dearshelf-subpackage.zip` 用于后续合并现有项目；`subpackage-entry.json` 是要追加到原 `app.json` 的分包项。脚本只读取 Supabase URL 和 Publishable Key，拒绝 Secret Key 和 service_role key。打包不执行上传或数据库迁移。

此交付继续要求服务端白名单、验证邮箱及配额接口。当前管理员邮箱尚未开通收藏柜账号，正式上线前需要按接入说明完成账号及后端初始化。

独立语法编译可复现如下。编译器是微信发布的封装版本；此检查不包含后台域名、隐私指引、开发者工具模拟器或真机验收。

```powershell
npm install --prefix .tooling/wechat-compiler --ignore-scripts --no-audit --no-fund --save-exact miniprogram-compiler@0.2.3
node scripts/verify_wechat_compiler.cjs
python scripts/build_private_access_sql.py --admin-email owner@example.com
node scripts/verify_private_rollout.mjs
```

`private-access-deploy.sql` 位于交付目录中的客户端 ZIP 旁，是只供管理员执行的后端脚本，不属于小程序前端包。管理员账号不存在或邮箱未验证时，整个部署事务回滚。
