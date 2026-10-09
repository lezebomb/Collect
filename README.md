# 收藏柜

一个私人数字收藏 App。支持邮箱账号、云同步、封面、收藏管理、搜索筛选、统计和备份。

2026-10-10：新增 **HarmonyOS 1.0.2(3)** 版本，目标为 Mate 80 Pro Max / HarmonyOS 6.1.0.135 / API 24。已完成 Release 编译、87 项自动化测试与官方模拟器验证。目标手机的设备签名和真机验收仍待完成，当前发布 HAP 未签名。

- [给手机持有人的完整安装教程](docs/harmonyos-recipient-guide.md)：准备工具、取 UDID、USB 安装与验收。
- [开发者异地签名教程](docs/harmonyos-developer-guide.md)：开发者账号、目标设备 Profile、源码构建与交付。
- [下载 HAP 与安装工具 ZIP](https://github.com/lezebomb/Collect/releases/tag/harmony-v1.0.2-preview)，[鸿蒙验证记录](docs/harmonyos-verification.md)。

生产服务器已限制为管理员指定的两个已验证邮箱，直接数据库、Storage 和搜索请求都执行限制；其他人下载或修改公开客户端也无法访问该项目数据。真实成员地址和签名材料不提交到 GitHub，详细状态见 [SECURITY.md](SECURITY.md)。

此前的 Android 优化和微信接入代码保留在仓库；微信小程序当前暂缓。历史记录见 [手机更新记录](docs/phone-install-2026-10-08.md)、[微信接入说明](docs/wechat-and-private-access.md) 和 [小程序模块](miniprogram/README.md)。

## 技术结构

- Flutter：Android 与独立 HarmonyOS 适配层；包含 iOS 工程骨架。
- Supabase Auth：邮箱密码登录，SDK 在设备上保持会话。
- Supabase Postgres：`public.items`，每行绑定 `user_id` 并启用 RLS。
- Supabase Storage：私有 `item-covers` bucket。数据库的 `cover_image` 保存稳定的 Storage 物品 URL；显示时按用户身份签发一小时的访问链接。

代码按 `lib/core`、`models`、`services`、`repositories`、`screens`、`widgets` 分层。数据库定义在 [supabase/schema.sql](supabase/schema.sql)。

## 运行前准备

1. 使用自己的 Supabase 项目。新环境先运行 `supabase/schema.sql` 与基础功能迁移，再按 [SECURITY.md](SECURITY.md) 选择独立邮箱限制或高级配额协议。高级配额迁移未部署到当前生产；不要盲目执行全部迁移。
2. 启用 Email provider，准备获准且邮箱已验证的账号；密码恢复使用官方邮件流程。Auth Redirect URLs 中加入 `collect://auth/recovery`。维护成员需要服务器管理员权限。
3. 复制 `config/app_config.example.json` 为 `config/local.json`，填入项目 URL 和 **Publishable Key**。不要在移动端使用 Secret 或 `service_role` key；本地配置已忽略。当前独立邮箱方案使用 `COLLECTION_PRIVATE_ACCESS=false`、`COLLECTION_EMAIL_ALLOWLIST=true`、`COLLECTION_ALLOW_REGISTRATION=false`。
4. 安装 Flutter SDK 和 Android SDK，运行：

   ```powershell
   flutter pub get
   flutter run --dart-define-from-file=config/local.json
   ```

   当前工作区中也有临时 Flutter SDK：`.tooling/flutter/bin/flutter.bat`。这个目录不纳入版本管理。

项目尚未绑定 Supabase 时也能启动，但只会显示配置提示。

资料搜索使用 `supabase/functions/catalog-search/index.ts` 调用 Tavily。在 Edge Functions Secrets 中设置 `TAVILY_API_KEY`，密钥不进入客户端或仓库。函数自行验证 bearer 用户并调用成员/限流 RPC，再访问 Tavily；当前部署由函数内部验 JWT。不要删除内部认证检查。同一表单内相同关键词会缓存结果；服务不可用时可用其他图片来源。

图片预览与选中下载共用有大小上限的缓存，避免重复请求同一图片。部分图片站点可能限制访问或超时，失败的预览显示为损坏图片，可选择其他来源。拍照仅提取文字，不理解画面；可以勾选组成物品名称的多行文字再搜索，避免混入分级标志等包装文字，也可自行修改搜索关键词。

## 数据与图片权限

`items` 的查询、插入、更新、删除策略均限定 `auth.uid() = user_id`，并叠加服务端成员检查。设置和分类也执行这两层限制。封面按 `<user_id>/<item_id>/<uuid>.<extension>` 存入私有 bucket，Storage 同时检查所属账号与成员资格。客户端保存对象 URL，显示时获取会过期的签名链接。

应用从不使用 `service_role` key。删除物品时先删数据库记录再清理封面；若 Storage 临时失败，可能留下孤立文件，可重试或在后台清理，但物品记录不会变成无法读取的坏数据。

## 功能

- 展柜按添加时间、购入时间、价格和名称排序，可按分类筛选并搜索名称或描述。
- 添加时可手动填写，也可拍照识别包装上的文字。资料搜索展示图片、名称和来源；选中后分别勾选是否使用封面、是否使用结果名称。默认只使用图片，保留自己的名称，描述由用户自己填写。游戏候选来自 [GameTDB](https://www.gametdb.com/)、[CheapShark](https://www.cheapshark.com/) 和 Steam；通用图片来自 [Tavily](https://www.tavily.com/)、[Bing 图片](https://www.bing.com/images/search)、[Openverse](https://openverse.org/) 与 [Wikimedia Commons](https://commons.wikimedia.org/)，书籍资料来自 [Google Books](https://books.google.com/) 和 [Open Library](https://openlibrary.org/)。搜索源失效时可以换词重搜或选本机图片。
- 账号创建时预置游戏、周边、配件、主机和其他，之后所有分类均可添加或删除。删除分类定义不会修改已有收藏，编辑旧收藏仍能选择其原分类；备份分别保留分类定义和物品自身分类。游戏可填写 Nintendo/PC 平台、内容类型、实体/数字版和游玩状态。
- 收藏物品均视为已拥有，不再保存通用收藏状态或评分。
- 价格默认人民币，支持美元、港币、日元、欧元及英镑。外币的人民币折算额用于跨币种统计，可按当前汇率估算或手动填写。保存后的折算额不会随汇率波动自动变化。
- 统计可按分类、年份筛选，包含总投入、在手物品、类型投入占比、各类型数量、月度消费和游戏游玩状态。
- 设置中可分别控制展柜卡片的价格、拥有天数、日均花费显示，并设置壁纸。
- 备份导出为 ZIP，内含 `backup.json`、`images/`、`wallpaper/`，可恢复物品、封面、分类、壁纸和展示设置。旧版 JSON 备份仍可导入。同账号导入按物品 ID 合并，同 ID 记录覆盖，其他记录保留；跨账号导入生成新 ID。备份文件含私人图片，请妥善保存。

## 验证

三个 Tab 通过 `IndexedStack` 保留状态，收藏列表及设置/分类在当前会话中复用，主动刷新或备份导入才重新查询。设置开关即时更新、串行保存，失败恢复最后一次成功值；分类操作也会在失败时回退。

私有图片的签名链接有效 60 分钟、内存复用 55 分钟，同一对象的并发签名请求合并。`cached_network_image 3.4.1` 和 `flutter_cache_manager 3.4.1` 按账号与 Storage 路径缓存图片，缩略图按显示宽度解码，退出会话清理缓存。系统可能回收磁盘缓存，首次加载和真正刷新仍需网络。

首页搜索可展开/收起，分类横向排列、排序在圆角面板中选择。普通竖屏按可用高度安排两列三行，放大系统字体、壁纸和展开搜索会占用更多空间。卡片名称完整换行并按空间缩放，辅助文字也按宽度适配。搜索、下载与识别采用页内进度提示；直接点击大封面可选相册或拍照。

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=config/local.json
```

当前鸿蒙验证：分析无问题、87 项测试通过、API 24 Release HAP 编译和模拟器安装成功；系统存储/图片/文件接口结果及真机待测项见 [验证记录](docs/harmonyos-verification.md)。此前 Android 检查见历史记录。

两列三行布局以 320×700、360×780、390×844 三种逻辑尺寸及六件内存测试收藏验证，未写入测试收藏到数据库。大量高清图片滚动、120 Hz 帧率和真实续签仍需目标设备观察，续签过期边界已通过自动测试。
