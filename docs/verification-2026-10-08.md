# 2026-10-08 验证记录

本轮修改性能、访问限制，以及共用 Supabase 的原生微信小程序分包。部署资料及步骤见 [接入说明](wechat-and-private-access.md)。

已完成：

- `flutter analyze`：无问题。
- `flutter test`：74 项通过；新增验证大图压缩/透明图保留、批量签名、慢清理不阻塞保存、响应丢失后的确认和封面保留。
- `flutter build apk --debug --dart-define-from-file=config/local.json`：成功，输出 `build/app/outputs/flutter-apk/app-debug.apk`。构建出现 Android SDK XML 版本兼容提示，未阻止构建；未安装到手机。
- `node --test miniprogram/tests/client.test.cjs`：9 项通过，覆盖刷新合并、拒绝未获准会话、列表与签名复用、账号退出、保存确认、上传预留、字段/统计、分包/转发域名、分页桥接负载。
- `python scripts/verify_miniprogram.py`：6 个页面的 JSON/JS/WXML 结构与事件绑定检查通过。这不是微信开发者工具实际编译。
- `node scripts/verify_catalog_search.mjs`：实际 Edge Function handler 在模拟网络下的身份校验、白名单拒绝、付费前限流、HTTPS 过滤、请求大小和无效 JSON 检查通过。
- `node scripts/verify_access.mjs`：本地 PGlite 完整迁移链通过；白名单/邮箱确认/跨账号隔离/撤权/收藏与存储额度/上传预留/注册 Hook/搜索限流/分类改名/函数权限通过。Auth 与 Storage 平台表是最小模拟结构，未连接正式 Supabase 项目。

随后用户连接手机，已追加 78 项 Flutter 测试、Release 构建和 Android 覆盖安装，并检查登录恢复、51 件收藏、封面、统计、设置与详情；结果和迁移前兼容配置见 [手机更新记录](phone-install-2026-10-08.md)。

未执行：线上 SQL 与 Edge Function 部署、现有小程序源码合并、Nginx/TLS 部署、微信开发者工具编译、上传/审核/发布、真机写入及真实网络性能测量。小程序 OCR、Flutter 裁剪、多来源资料搜索、自动汇率及完整 ZIP 备份尚未移植；这些功能继续保留在 Flutter 中。
