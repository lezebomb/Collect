# 收藏柜

一个私人数字收藏 App。支持邮箱账号、云同步、封面、收藏管理、搜索筛选、统计和备份。

## 技术结构

- Flutter：Android 优先；包含 iOS 工程骨架。
- Supabase Auth：邮箱密码登录，SDK 在设备上保持会话。
- Supabase Postgres：`public.items`，每行绑定 `user_id` 并启用 RLS。
- Supabase Storage：私有 `item-covers` bucket。数据库的 `cover_image` 保存稳定的 Storage 物品 URL；显示时按用户身份签发一小时的访问链接。

代码按 `lib/core`、`models`、`services`、`repositories`、`screens`、`widgets` 分层。数据库定义在 [supabase/schema.sql](supabase/schema.sql)。

## 运行前准备

1. 已创建专用 Supabase 项目 **Collect**（`lowwbbgyoqivzjmruzig`，`ap-southeast-1`），并应用了初始、`collection_features`、`remove_collection_status_and_rating` 迁移。新环境先运行 `supabase/schema.sql`，再按顺序运行 `supabase/migrations/` 中的迁移。
2. 在 Supabase Auth 中启用 Email provider。若开启邮箱确认，注册后先打开邮件确认，再回到 App 登录。密码恢复使用官方邮件流程；在 Auth 的 Redirect URLs 中加入 `collect://auth/recovery`，正式使用前配置自己的 SMTP 发件服务。
3. 当前工作区的 `config/local.json` 已填入 Collect 项目 URL 和 **Publishable Key**。在新设备上，复制 `config/app_config.example.json` 为 `config/local.json` 并填入对应值。不要在移动端使用 Secret 或 `service_role` key。`config/local.json` 已加入 `.gitignore`。
4. 安装 Flutter SDK 和 Android SDK，运行：

   ```powershell
   flutter pub get
   flutter run --dart-define-from-file=config/local.json
   ```

   当前工作区中也有临时 Flutter SDK：`.tooling/flutter/bin/flutter.bat`。这个目录不纳入版本管理。

项目尚未绑定 Supabase 时也能启动，但只会显示配置提示。

资料搜索使用 `supabase/functions/catalog-search/index.ts` 中的轻量服务端函数调用 Tavily。部署该函数，并在 Supabase Edge Functions → Secrets 中设置 `TAVILY_API_KEY`；密钥不进入 Flutter 配置或代码仓库。函数在调用 Tavily 前向 Supabase Auth 验证用户身份。Tavily 使用 fast 搜索和图片候选，同一表单内相同关键词会缓存结果。未配置或暂时不可用时，其他图片来源仍可使用。

图片预览与选中下载共用有大小上限的缓存，避免重复请求同一图片。部分图片站点可能限制访问或超时，失败的预览显示为损坏图片，可选择其他来源。拍照仅提取文字，不理解画面；可以勾选组成物品名称的多行文字再搜索，避免混入分级标志等包装文字，也可自行修改搜索关键词。

## 数据与图片权限

`items` 的查询、插入、更新、删除策略均限定 `auth.uid() = user_id`。封面按 `<user_id>/<item_id>/<uuid>.<extension>` 存入私有 bucket，Storage 策略限制每个人只能读、上传和删除自己目录中的对象。客户端保存的是可长期引用的对象 URL，不保存会过期的签名链接。

应用从不使用 `service_role` key。删除物品时先删数据库记录再清理封面；若 Storage 临时失败，可能留下孤立文件，可重试或在后台清理，但物品记录不会变成无法读取的坏数据。

## 功能

- 展柜按添加时间、购入时间、价格和名称排序，可按分类筛选并搜索名称或描述。
- 添加时可手动填写，也可拍照识别包装上的文字。资料搜索展示图片、名称、简介和来源；选中后可仅使用图片，或显式填充简介、资料名称，默认保留自己的名称。游戏候选来自 [GameTDB](https://www.gametdb.com/)、[CheapShark](https://www.cheapshark.com/) 和 Steam；通用图片来自 [Tavily](https://www.tavily.com/)、[Bing 图片](https://www.bing.com/images/search)、[Openverse](https://openverse.org/) 与 [Wikimedia Commons](https://commons.wikimedia.org/)，书籍资料来自 [Google Books](https://books.google.com/) 和 [Open Library](https://openlibrary.org/)。搜索源失效时可以换词重搜或选本机图片。
- 默认分类为游戏、周边、配件、主机和其他，可添加自定义分类。游戏可填写 Nintendo/PC 平台、内容类型、实体/数字版和游玩状态。
- 收藏物品均视为已拥有，不再保存通用收藏状态或评分。
- 价格默认人民币，支持美元、港币、日元、欧元及英镑。外币的人民币折算额用于跨币种统计，可按当前汇率估算或手动填写。保存后的折算额不会随汇率波动自动变化。
- 统计可按分类、年份筛选，包含总投入、在手物品、类型投入占比、各类型数量、月度消费和游戏游玩状态。
- 设置中可分别控制展柜卡片的价格、拥有天数、日均花费显示，并设置壁纸。
- 备份导出为 ZIP，内含 `backup.json`、`images/`、`wallpaper/`，可恢复物品、封面、分类、壁纸和展示设置。旧版 JSON 备份仍可导入。同账号导入按物品 ID 合并，同 ID 记录覆盖，其他记录保留；跨账号导入生成新 ID。备份文件含私人图片，请妥善保存。

## 验证

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=config/local.json
```
