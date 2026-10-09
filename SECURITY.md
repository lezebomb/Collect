# 安全与服务端访问控制

2026-10-10：现有 Collect 服务器已启用独立的精确邮箱白名单。目前只有管理员指定的两个已验证邮箱获准访问；真实邮箱只存放在服务器的私有表，不在公开源码或安装工具 ZIP 中。

## 已实施的限制

- 身份由 Supabase Auth 验证；服务端检查 `auth.users` 中实际邮箱、验证状态及是否匿名，不使用客户端传入的邮箱或可修改的 user metadata。
- `items`、`user_preferences`、`user_categories` 同时执行账号所属关系与 restrictive 成员策略。已登录但不在名单内的账号也不能访问。
- `item-covers` 为私有 bucket，封面路径保留账号隔离并增加成员检查。客户端仅持有 Publishable Key 与自己的会话；管理员 key 和 Tavily 密钥不会打入 App。
- `auth.users` 的 BEFORE INSERT 触发器阻止名单外邮箱和匿名用户创建新 Auth 账号。当前 Auth 的全局 `disable_signup` 开关仍为 false；实际注册限制由数据库触发器强制执行，不能仅凭这个开关判断注册是否开放。App 注册按钮默认隐藏。
- `catalog-search` 在调用 Tavily 前验证用户并执行服务端限流：每账号每分钟 6 次、每日 100 次（北京时间日期）。匿名请求拒绝；并发计数在数据库串行更新。
- 私有函数固定空 `search_path`，只开放必要的 authenticated 调用入口；客户端没有名单表和计数表的直接权限。

撤权对新的数据库、Storage 签名和搜索请求生效。已下载的本地数据以及到期前的已签发图片链接无法远程收回。账号密码也需由持有人妥善保管；白名单不能代替密码验证。

## 生产已部署与可选方案

生产使用以下独立迁移和当前 `catalog-search` 函数：

1. `20261009162155_email_membership_gate.sql`
2. `20261009162951_email_signup_gate.sql`

较早的 `20261007164804_private_access_and_quotas.sql` 是**可选的完整收藏/图片配额与上传预留方案，目前未部署到生产**。它会要求客户端改用图片预留 RPC。不要对现有服务器盲目执行整个目录的 `supabase db push`；先核对迁移差异及客户端协议。当前发布构建采用 `COLLECTION_PRIVATE_ACCESS=false`（关闭可选预留协议）、`COLLECTION_EMAIL_ALLOWLIST=true`（启用独立成员检查），服务器白名单仍强制生效。

自己部署新项目时，先应用 `schema.sql` 与 2026-10-07 之前的功能迁移；再在同一受控事务中应用独立成员迁移、写入自己的精确邮箱和部署注册触发器。准备已验证的成员账号后再开放客户端使用。不要复制生产成员名单；维护示例见 [email-members.example.sql](supabase/admin/email-members.example.sql)。使用高级配额方案前单独完成该协议的客户端升级与验证。

## 验证和已知边界

已完成本地 Postgres 权限测试，覆盖名单内/外、未验证邮箱、直接 API 绕过、跨账号隔离、成员撤销、Storage 上传兼容、搜索限流及名单外注册拒绝。线上在回滚事务中验证实际 authenticated 角色：指定两个账号通过，其余已有账号不能读取收藏；名单外 Auth 插入被拒绝。匿名 REST、成员 RPC 和搜索 HTTP 请求已检查拒绝，无真实收藏被测试修改。

公开前扫描了 Git 历史和待发布文件。`config/local.json`、环境文件、华为签名配置/密钥/证书、微信本地配置、设备 UDID、诊断与构建缓存均忽略。扫描能发现已知格式泄露，不能证明系统没有任何漏洞。

Supabase Advisor 中两个 `RLS Enabled No Policy` 信息项对应私有名单/计数表：这是有意的拒绝直接访问，且没有客户端表权限，不应添加开放策略。[说明](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)。另外，当前项目的 **Leaked Password Protection 未开启**；现有工具没有可用的 Auth 设置修改接口，此项未改动，可在项目 Auth 设置按[官方密码安全文档](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)启用。

## 发现问题时

不要在公开 Issue 放密码、会话 token、签名材料、真实邮箱名单、设备 UDID 或收藏备份。请通过仓库维护者约定的私下渠道提供可复现步骤、脱敏日志和影响范围。
