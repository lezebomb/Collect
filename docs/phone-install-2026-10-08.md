# 2026-10-08 手机更新记录

已在连接的 PLR110 Android 手机上覆盖安装并启动 Dearshelf 1.0.1（versionCode 2）。本次使用 Flutter Release 构建，Flutter 目标架构为 android-arm64，APK 大小 53,712,452 字节（51.2 MiB）。包名与旧版一致；安装前核对新旧签名证书相同，使用 `adb install -r` 更新，未卸载、清除数据或修改线上数据库。

旧 APK、应用私有数据（包括会话、草稿和缓存）已保存于本机 `.tooling/phone-backup/2026-10-08/`；该目录不进入 Git。新版 APK 位于 `build/app/outputs/flutter-apk/app-release.apk`，SHA-256 为 `cd68a8de6a8305a927e2b8562df11cf84dc9551449772f730db6e336dd63da00`。

## 本次兼容配置

只读检查确认，线上尚无 `collection_access_allowed`、图片预留/释放及搜索配额 RPC。为保证迁移前可使用，新版使用本机 `.tooling/phone-preview.json` 明确编译为 `COLLECTION_PRIVATE_ACCESS=false`；该文件从现有公开客户端配置生成，并被 Git 忽略。

此次预览保留原有登录、账号 RLS 隔离和私有图片访问，不启用新增的邮箱白名单与配额。源代码和示例配置默认要求私有模式，缺失接口或网络错误不会自动降级。正式启用访问限制时，需要先部署迁移、加入真实邮箱，再编译 `COLLECTION_PRIVATE_ACCESS=true` 并同步更新客户端，具体见 [接入说明](wechat-and-private-access.md)。微信部署本次未执行。

## 验证结果

- 完整 Flutter 测试 78 项通过；新增迁移前兼容模式、私有模式缺失 RPC 不放行、服务端拒绝和额度拒绝的测试。
- `flutter analyze` 无问题；Release APK 构建成功。补充了 OCR 插件未使用的 Devanagari、日语、韩语模型的精确 R8 缺失类规则；中文模型依赖保留，其他缺失类检查继续启用。
- 同签名覆盖安装成功；手机报告 `versionName=1.0.1`、`versionCode=2`，没有 DEBUGGABLE 标记。
- 原登录会话恢复，无需重新登录；展柜显示原 51 件收藏，当前可见封面正常。统计页、设置页和一件收藏详情已打开检查，展示开关和分类保持原值。
- 启动后应用进程持续运行，采集的该进程日志未发现崩溃或未处理的 Flutter 异常。手机已返回展柜首页。
- 更新前后云端数量均为 51 件收藏、2 个账号、42 个图片对象。本次未创建、修改或删除收藏。

本次是安装和启动验证，没有进行真机写入/换封面、拍照 OCR、备份导入和网络故障测试，也没有测量真实加载/保存耗时。保存与图片流程的可靠性目前由自动测试覆盖；实际速度仍需后续手机使用验证。`am start -W` 报告的 352 ms 只是 Activity 启动时间，不代表云端数据和图片全部加载完毕。

复现本次构建（需先准备上述本机配置）：

```powershell
flutter build apk --release --target-platform android-arm64 --build-name=1.0.1 --build-number=2 --dart-define-from-file=.tooling/phone-preview.json
```

Android Release 规则配置参见 [Android 构建类型文档](https://developer.android.com/build/build-variants#build-types)；各 OCR 模型依赖参见 [插件说明](https://github.com/flutter-ml/google_ml_kit_flutter/tree/master/packages/google_mlkit_text_recognition)。
