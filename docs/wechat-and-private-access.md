# 微信接入、性能优化与私有访问说明

更新时间：2026-10-08。代码及离线验证已完成；未变更线上数据库、部署 Edge Function 或上传小程序。随后已在 Android 手机安装兼容优化版，结果见 [手机更新记录](phone-install-2026-10-08.md)。

**2026-10-10 更新：微信方向暂缓，以下为历史准备记录。生产已部署独立邮箱限制与搜索限流，高级图片预留/配额方案仍未启用；请以 [SECURITY.md](../SECURITY.md) 和[鸿蒙安装入口](harmonyos-install.md)为准。**

## 为什么个人主体采用原生分包

微信官方 [web-view 文档](https://developers.weixin.qq.com/miniprogram/dev/component/web-view.html) 当前明确说明个人类型小程序不支持这个组件。因此 APK、Flutter 原生页面和 Flutter 网页均不能直接嵌入现有个人小程序。

本仓库已准备 `miniprogram/` 原生代码，可以作为原小程序内的收藏柜分包。它复用现有 Supabase 数据，不必另建一份数据库。具体复制、路由前缀和 `subPackages` 配置见 [小程序 README](../miniprogram/README.md)。现有小程序源代码尚未提供，因此本轮没有替你改动它的入口和配置。

已实现登录、列表/搜索/分类/排序、单件和批量管理、拍照/相册封面、压缩、草稿、价格及游戏字段、统计、展示开关、壁纸、分类管理、JSON 清单导入导出。ML Kit OCR、Flutter 自定义裁剪、多来源资料搜索、自动汇率和完整图片 ZIP 备份继续由现有 Flutter 应用提供，尚未移植到原生微信模块。这些功能不能通过复制 Flutter 插件获得，需要按微信能力分别实现和验证。

## 此轮优化

- 数据库确认保存或删除后，即可更新界面；旧封面、旧壁纸的清理移至后台。Flutter 和小程序均保留清理队列，后续打开时重试。
- 较大且不透明的图片压缩为 JPEG；Flutter 在 worker isolate 中编码，保留透明图片与小文件。新上传上限为 2 MiB，原始选图仍可到 10 MiB，必须经过压缩/裁剪后满足上传上限。已有大图片不删除，也不强制转换。
- Flutter 复用上传字节作为图片缓存，同一轮出现的私有封面合并签名；小程序按可见批次签名，缓存 55 分钟。
- 本地收藏快照短暂合并写入，避免首页多个请求先后完成时反复编码/写盘。数据库索引覆盖 `user_id, created_at, id` 的列表顺序。
- 保存响应丢失时按稳定 ID 查询确认。无法确认时保留可能已提交的封面，不盲目重复插入。明确失败时才清理无用封面。
- 备份导入分类改为批量写入；旧图片清理同样不阻塞导入进度。

这些修改减少请求、上传体积和保存后的等待，没有手机网络上的耗时对比数据。Supabase 所在区域、跨境链路和图片来源仍可能影响速度，需后续实测。

## 访问限制与容量保护

建议使用“管理员邀请 + 精确邮箱白名单 + 邮箱验证 + 服务端配额”。代码不在前端保存允许邮箱名单；修改小程序或抓包不能绕过数据库策略。客户端只使用 Publishable Key 和用户 JWT。

新迁移 `supabase/migrations/20261007164804_private_access_and_quotas.sql` 提供：

| 控制 | 默认值 / 行为 |
|---|---|
| 精确邮箱白名单 | 空名单拒绝所有用户；仅管理员可改 |
| 邮箱确认 | `auth.users.email_confirmed_at` 必须存在；拒绝匿名账号 |
| 用户隔离 | 保留 `user_id = auth.uid()` 策略，再叠加 restrictive 白名单策略 |
| 每人收藏上限 | 500 件，可逐人调整 |
| 每人分类上限 | 60 个，可逐人调整 |
| 每人图片额度 | 100 MiB，可逐人调整 |
| 每张新图片 | 2 MiB；私有 bucket；不可覆盖原 UUID 路径 |
| 付费搜索 | 每分钟 6 次、每天 100 次；可逐人调整 |
| 描述长度 | 新写入不超过 20000 字 |

上传前必须调用 `reserve_collection_cover`，预留一张图片的完整 2 MiB 最大容量。数据库对每个账号加锁，避免并发请求同时通过额度判断。未完成的上传预留也占空间，管理员可核对并回收。额度可能因此比“实际图片大小总和”更保守，不会因伪造客户端大小而超额。

撤销白名单后，新数据库读取、写入、Storage 签名与付费搜索请求立即被拒绝。已经发出的签名图片链接在其有效期内仍可打开，已经下载到设备的数据也无法远程收回。不要把签名 URL 放到分享链接或日志中。

白名单只约束本应用数据。要防止陌生人大量创建 Auth 账号和触发默认分类初始化，还必须关闭 Supabase 的公开注册，或启用下述 Before User Created Hook。只隐藏注册按钮不够。Hook 的官方行为见 [Supabase 文档](https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook)。

## 后续上线顺序

Flutter 默认使用 `COLLECTION_PRIVATE_ACCESS=true`，权限接口不存在或网络失败时不会自动放行。数据库迁移尚未部署时，手机预览可显式编译为 `--dart-define=COLLECTION_PRIVATE_ACCESS=false`：跳过新增权限检查与图片预留 RPC，继续使用原有登录、RLS 和私有 Storage。这个配置不会关闭数据库策略，不能绕过已部署的白名单；它也不提供新的白名单与配额。只用于迁移前的功能测试，不应作为正式私有版发布。启用新数据库策略时，必须同步切回 `true` 并更新客户端；否则新 Storage 策略会拒绝没有预留的新图片。

1. 先记录当前管理员邮箱，导出完整备份。确认邮箱已验证。
2. 在 Supabase Authentication 设置中关闭公开注册和匿名登录，保持邮箱确认。少量特定用户由管理员邀请/开通。若确实需要用户自行注册，改为启用 `public.before_collection_user_created` 作为 Before User Created Hook；它只允许白名单邮箱。小程序默认 `allowRegistration: false`。
3. 在测试项目执行新迁移并验证，再在正式项目部署。同一操作中立即加入管理员的精确邮箱；空名单会使所有现有账号暂时无法进入，但不会删除数据。已有项目不要重跑 `schema.sql` 和已经执行过的旧迁移。新项目才按 schema、所有旧迁移、新迁移的顺序初始化。
4. 按 `supabase/admin/allowlist.example.sql` 的方式添加其他邮箱及额度。示例邮箱必须替换，不能直接当真实名单使用。合计额度应低于项目可用空间，并为备份、日志和其他数据预留余量。
5. 重新部署 `catalog-search` Edge Function，它会使用用户 JWT 调用数据库配额 RPC。`TAVILY_API_KEY` 只存在服务端 Secrets。新客户端和新数据库迁移配套上线；旧客户端未做上传预留，启用新 Storage 策略后不能上传新图片。
6. 填写小程序 AppID 和公开配置，合并原项目入口和分包，使用微信开发者工具编译。配置合法域名、隐私保护指引、相册/相机说明、服务类目等微信后台项目，并核对当前后台要求。
7. 提供后续体验版和手机环境后，再测试 iOS/Android、网络失败、图片选择、文件分享、撤权和容量边界；最后提交微信审核和发布。

## 域名与转发准备

先在微信后台检查 Supabase 域名能否配置为合法请求域名，不能假设 `*.supabase.co` 自动符合后台要求。域名与 HTTPS 要求参见 [微信网络文档](https://developers.weixin.qq.com/miniprogram/dev/framework/ability/network.html)。

若需要自有域名，仓库提供 `deploy/nginx-supabase-relay.conf` 模板，把 HTTPS 请求转发到原 Supabase 项目。只转发用户自身的 JWT 与 Publishable Key，不使用管理员 key。需要你后续提供可用域名、相应备案信息、服务器及 TLS 证书；模板没有启动或部署。应先执行 `nginx -t`，再在测试环境验证 Auth、REST、Storage 的上传/签名/下载以及微信域名检查。公网原 Supabase API 的 RLS 同样受白名单保护，不能只靠网关拦截。

使用转发域名时，小程序配置例如：

```javascript
module.exports = {
  supabaseUrl: 'https://api.your-domain.example',
  storageOrigin: 'https://YOUR_PROJECT_REF.supabase.co',
  publishableKey: 'sb_publishable_YOUR_KEY',
  allowRegistration: false,
  routePrefix: '/dearshelf',
};
```

`storageOrigin` 保持原数据库中封面的地址来源，保障和 Flutter 互通；实际小程序 API 请求、图片签名和显示通过你的转发域名。所有示例值需替换。转发域名不会自动消除跨区域数据库延迟。

## 需要你后续提供

- 现有小程序的源代码目录或仓库，以及原生/uni-app/Taro 等技术栈、计划放置入口的位置。
- 小程序 AppID、开发者权限和当前服务类目。此方案使用邮箱登录，不需要把 AppSecret 发进聊天。
- Supabase 项目 URL、Publishable Key、已执行迁移的情况；正式部署时需在本机授权项目操作，不必提供数据库密码或 service_role key。
- 管理员邮箱、具体允许的邮箱名单，以及期望的每人收藏数、图片容量、搜索次数上限。
- 若需要自有后端域名：域名、可用服务器、HTTPS 和微信后台合法域名配置情况。
- 发布前需要的名称、隐私指引与后台设置。手机、体验成员和真机测试可以后续再提供。

## 验证与尚未覆盖的范围

Flutter 自动测试验证现有功能和新增图片压缩、保存响应丢失、后台清理不阻塞保存。小程序测试使用模拟微信 API 验证会话刷新、账号切换、批量签名、保存确认、上传预留、字段校验等；结构检查核对 6 个页面的 JS/WXML 和事件绑定。

SQL 使用本地 PGlite Postgres 引擎执行完整迁移链，并测试白名单、未验证邮箱、跨账号权限、撤权、收藏/图片额度、搜索限流、注册 Hook 和分类改名。其 `auth`、`storage` 平台表及认证角色使用最小模拟结构；这证明 SQL 的权限和事务逻辑通过离线验证，不代表正式 Supabase Storage API 已完成端到端验收。新环境安装方式及运行脚本：

```powershell
npm install --prefix .tooling/verification --ignore-scripts --no-audit --no-fund @electric-sql/pglite@0.5.8
node scripts/verify_access.mjs
node scripts/verify_catalog_search.mjs
node --test miniprogram/tests/client.test.cjs
python scripts/verify_miniprogram.py
flutter analyze
flutter test
```

尚未完成：正式迁移与函数部署、现有小程序源代码的实际合并、微信开发者工具编译、域名/TLS/转发部署、平台审核和手机测试。上线前需继续验证，不能把离线测试当作已部署或已通过微信审核。

## 2026-10-09 独立交付更新

用户已提供 Geek Mia 的 AppID，并选择先按独立小程序准备。源码和独立交付包均使用 `wxc1459acced9a2a5d`，当前公开后端 URL 与 Publishable Key 已填入；`allowRegistration` 保持关闭。打包脚本 `scripts/build_wechat_package.py` 生成独立项目及分包两个 ZIP，不读取 AppSecret、service_role、手机备份或登录会话。

以下为此前高级配额方案的准备记录：`scripts/build_private_access_sql.py` 可生成带已验证管理员检查的事务 SQL；缺少管理员账号时回滚。真实邮箱不进入公开文档。2026-10-10 已改用独立邮箱限制并在生产启用两个指定已验证账号；高级图片预留/配额方案仍未部署，当前状态以 [SECURITY.md](../SECURITY.md) 为准。

验证结果：9 项小程序逻辑测试和 6 页面结构检查通过；微信发布的 `miniprogram-compiler@0.2.3` 完成本地 WXML/WXSS 编译；完整权限迁移链与实际搜索处理函数的离线测试通过；新增部署事务验证覆盖管理员不存在、邮箱未验证及正常管理员三种情况。该编译器封装发布较早，本地编译不能替代当前微信开发者工具及真机验收。

浏览器扩展连接已恢复，能够列出已登录的微信小程序标签页；浏览器工具的站点安全策略明确拒绝自动访问微信公众平台，并禁止通过其他浏览器入口绕过。因此未读取或改动 Geek Mia 后台，未核实服务器合法域名、现有线上版本、隐私指引与类目，未上传代码或提交审核。Computer-use 的运行文件占用故障在新进程启动后复发，尚未完全修复。此前 Git 目录所有权修复保持有效。

后续发布条件包括：收藏柜管理员账号与私有权限部署、合法后端域名、微信开发者工具登录或本机 CI 上传密钥及 IP 白名单、隐私指引配置，以及模拟器/真机验证。CI 上传的官方说明见 [微信 miniprogram-ci](https://github.com/wechat-miniprogram/miniprogram-ci-dist)。上传密钥应存放在本机私有路径，不能进入小程序包或聊天。

Supabase 安全顾问的只读检查还提示：当前项目未启用泄露密码检测。可在套餐与账号条件允许时，按 [密码保护官方说明](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) 启用；本轮未更改 Authentication 设置。
