# Dearshelf 鸿蒙版安装入口

目标：HUAWEI Mate 80 Pro Max，HarmonyOS 6.1.0.135 / API 24。鸿蒙版沿用 Flutter 收藏业务、原 Supabase 云端和 ZIP/JSON 备份格式。

## 请按你的角色选择教程

- **手机持有人**：[从下载工具到手机安装、登录与验收的完整教程](harmonyos-recipient-guide.md)。只需 Windows 电脑、USB 数据线、华为 DevEco 的 hdc 工具和开发者发来的设备签名 HAP。
- **开发者**：[异地手机签名与源码构建教程](harmonyos-developer-guide.md)。收到手机 UDID 后，用自己的华为开发者账号完成签名，将 HAP 发给手机持有人。
- **测试范围**：[验证记录](harmonyos-verification.md)；**服务器权限**：[安全说明](../SECURITY.md)。

手机上的华为账号与签名开发者账号可以不同。App 登录使用已获授权的收藏柜邮箱账号。

## 当前交付状态（2026-10-10）

鸿蒙版 1.0.2(3) 已完成 API 24 Release 编译、87 项自动化测试和官方模拟器验证。模拟器的私有存储、JPEG 方向、透明 PNG 与图片恢复、系统文件导出/导入已经通过。现有模拟器的 OCR 服务不可用，目标手机的拍照、相册、OCR 和真实账号完整流程仍待验收。

下载入口：[GitHub 发布页](https://github.com/lezebomb/Collect/releases/tag/harmony-v1.0.2-preview)。包含未签名 HAP、校验文件和安装工具 ZIP。**目前没有目标手机 UDID 和华为调试签名，发布页的 unsigned HAP 不能安装到真机。** 必须先按上述两份教程完成设备签名。

原有收藏功能保留；服务器已启用两个已验证邮箱的独立白名单、账号数据隔离和付费搜索限流。白名单约束直接作用于数据库和 Storage，修改公开客户端也不能绕过。注册入口默认隐藏。

## 已有工具的本机测试命令

在仓库根目录运行；其他安装路径追加 `-StudioPath '实际 DevEco 安装目录'`。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\harmony\build.ps1 -Unsigned

. .\harmony\env.ps1
node .\scripts\prepare_harmony.mjs
Set-Location .\harmony\app
& $HarmonyFlutter analyze --no-pub
& $HarmonyFlutter test --no-pub
```

业务源码位于根目录 `lib`，构建时生成到 `harmony/app/lib`；平台实现位于 `harmony/adapter` 和 `harmony/app/ohos/entry/src/main/ets/platform`。本地签名配置不会被生成脚本覆盖，也不会提交到 GitHub。
