# 收藏柜

一个私人数字收藏 App。支持邮箱账号、云同步、封面、收藏管理、搜索筛选、统计和备份。

## 技术结构

- Flutter：Android 优先；包含 iOS 工程骨架。
- Supabase Auth：邮箱密码登录，SDK 在设备上保持会话。
- Supabase Postgres：`public.items`，每行绑定 `user_id` 并启用 RLS。
- Supabase Storage：私有 `item-covers` bucket。数据库的 `cover_image` 保存稳定的 Storage 物品 URL；显示时按用户身份签发一小时的访问链接。

代码按 `lib/core`、`models`、`services`、`repositories`、`screens`、`widgets` 分层。数据库定义在 [supabase/schema.sql](supabase/schema.sql)。

## 运行前准备

1. 已创建专用 Supabase 项目 **Collect**（`lowwbbgyoqivzjmruzig`，`ap-southeast-1`），并应用了初始及 `collection_features` 迁移。新环境先运行 `supabase/schema.sql`，再运行 `supabase/migrations/20260930000000_collection_features.sql`。
2. 在 Supabase Auth 中启用 Email provider。若开启邮箱确认，注册后先打开邮件确认，再回到 App 登录。正式使用前配置自己的 SMTP 发件服务。
3. 当前工作区的 `config/local.json` 已填入 Collect 项目 URL 和 **Publishable Key**。在新设备上，复制 `config/app_config.example.json` 为 `config/local.json` 并填入对应值。不要在移动端使用 Secret 或 `service_role` key。`config/local.json` 已加入 `.gitignore`。
4. 安装 Flutter SDK 和 Android SDK，运行：

   ```powershell
   flutter pub get
   flutter run --dart-define-from-file=config/local.json
   ```

   当前工作区中也有临时 Flutter SDK：`.tooling/flutter/bin/flutter.bat`。这个目录不纳入版本管理。

项目尚未绑定 Supabase 时也能启动，但只会显示配置提示。

## 数据与图片权限

`items` 的查询、插入、更新、删除策略均限定 `auth.uid() = user_id`。封面按 `<user_id>/<item_id>/<uuid>.<extension>` 存入私有 bucket，Storage 策略限制每个人只能读、上传和删除自己目录中的对象。客户端保存的是可长期引用的对象 URL，不保存会过期的签名链接。

应用从不使用 `service_role` key。删除物品时先删数据库记录再清理封面；若 Storage 临时失败，可能留下孤立文件，可重试或在后台清理，但物品记录不会变成无法读取的坏数据。

## 功能

- 展柜按添加时间、购入时间、价格和名称排序，可按分类筛选并搜索名称或描述。
- 添加时可手动填写，也可拍照识别包装上的文字。名称旁的搜索按钮显示多张候选图片；选中后可选择保留原名称，或使用图片对应的标题。游戏图片来自 [GameTDB](https://www.gametdb.com/) 和 [CheapShark](https://www.cheapshark.com/)，其他候选来自 [Openverse](https://openverse.org/)、[Wikimedia Commons](https://commons.wikimedia.org/) 及 [Open Library](https://openlibrary.org/)。维基数据只协助匹配游戏的英文别名，不作为默认封面来源。图片和标题需人工核对；目录不可用时仍可手动填写或选取本机图片。
- 默认分类为游戏、周边、配件、主机和其他，可添加自定义分类。游戏可填写 Nintendo/PC 平台、内容类型、实体/数字版和游玩状态。
- 价格默认人民币，支持美元、港币、日元、欧元及英镑。外币的人民币折算额用于跨币种统计，可按当前汇率估算或手动填写。保存后的折算额不会随汇率波动自动变化。
- 统计可按分类、年份筛选，包含总投入、在手物品、类型投入占比、各类型数量、月度消费和游戏游玩状态。
- 设置中可分别控制展柜卡片的价格、拥有天数、日均花费显示，并设置壁纸。
- 备份导出为 JSON，包含物品、封面、分类、壁纸和展示设置。导入时按物品 ID 合并，同 ID 记录覆盖，其他记录保留。备份文件含私人图片，请妥善保存。

## 验证

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=config/local.json
```
