# Dearshelf 鸿蒙验证记录

验证日期：2026-10-09 至 2026-10-10。目标手机：HUAWEI Mate 80 Pro Max / HarmonyOS 6.1.0.135 / API 24。目前没有这台真机，也没有它的调试签名，因此交付状态为“已编译、已做模拟器验证，待设备签名和真机验收”。

## 环境与交付

- 官方 DevEco Studio 6.1.1.418，SDK HarmonyOS 6.1.1.125 / API 24。
- Flutter-OH `3.41.10-ohos-1.0.0`，Dart 3.11.5；完整版本见 `harmony/TOOLCHAIN.md`。
- 官方手机模拟器 HarmonyOS 6.1.1(24)，软件版本 6.1.0.126，x86_64，1320 × 2848、密度 540。
- 交付：`harmony/output/Dearshelf-release-ohos-arm64+ohos-x64-unsigned.hap`，含 ARM64 手机与 x64 模拟器代码，运行 `lib/main.dart` 正式入口。
- 包版本 1.0.2(3)，大小 54,270,274 字节；SHA-256：`C6F977F28454C90B2600EB4119C74EF2DF5C03A847D1CB0BA7803BCC07231A0C`。输出目录另附校验文件。
- 独立诊断入口 `harmony/smoke/native_smoke.dart` 只用于验证系统接口，不是交付 App 的入口。

## 实际完成的检查

| 检查 | 结果 | 证据与范围 |
| --- | --- | --- |
| Dart 静态分析 | 通过 | `.tooling/harmony-analyze.log`，No issues found |
| Dart 自动化测试 | 87 项通过 | `.tooling/harmony-tests.log`；79 项业务与权限测试 + 8 项鸿蒙适配层测试，在本机测试运行器中执行 |
| Release HAP 编译 | 通过 | `.tooling/harmony-build.log`；API 24 SDK 编译 ArkTS、打包 Flutter 与两种架构 |
| 官方模拟器安装与启动 | 通过 | 最新 1.0.2 正式入口经 hdc 安装、EntryAbility 启动；中文登录布局、注册入口隐藏、授权提示及空输入校验已检查 |
| 原生存储 | 通过 | 经真实 MethodChannel 读写私有目录，重新创建存储对象后读取最终值，并清理诊断键 |
| JPEG 方向校正 | 通过 | EXIF orientation=6 的 80 × 40 图片归一化后为 40 × 80 |
| PNG 透明度和图片恢复 | 通过 | 透明像素保留；待恢复图片标记可读取并确认消费 |
| 系统文件导出 | 通过 | 通过华为系统文件保存界面，将诊断 JSON 保存到模拟器 Download |
| 系统文件导入 | 通过 | 通过系统选择器重新选择该文件，读取内容与导出前完全一致 |
| 华为系统 OCR | 未在本镜像验证 | `UNAVAILABLE_IN_THIS_EMULATOR`，该镜像的文字识别运行服务不可用，不计为通过 |

原生结果：`.tooling/harmony-native-smoke-result.json`。最新登录截图：`.tooling/harmony-screenshots/final-login.jpeg`。原生测试使用诊断生成的图片和文件，没有创建真实云端收藏。测试截图、设备报告和日志不上传公开仓库。

测试过程中修复了透明 PNG 归一化后被错误写成不透明图片的问题；目前通过解码后的像素信息和源格式决定 PNG/JPEG 输出。文件导出、导入已通过系统界面完成真实往返。

## 保留功能与平台替换

收藏列表、增删改、筛选排序、分类、统计、封面处理、云端同步、草稿与 ZIP/JSON 格式沿用根目录 `lib` 业务代码。鸿蒙工程单独替换相册/相机、文件选择/保存、私有路径、登录持久化、找回密码链接和 OCR 的系统实现。本次另外按用户要求加入独立服务器成员检查，并默认隐藏注册按钮。

自动化覆盖包括原有数据与保存可靠性检查，以及鸿蒙登录存储持久化、PKCE 存储隔离、有序写入、取消选择、大文件通过临时路径导出及清理、OCR 文本过滤、图片恢复确认。它们不能证明真实云端账号与目标手机全部流程已经通过。

独立服务器白名单的本地 SQL 测试和线上只读/回滚权限审计均已完成：两个指定已验证账号通过，其他现有账号和匿名请求被拒绝；名单外新 Auth 用户插入失败。付费搜索限流的实际函数入口通过本地验证，匿名线上调用返回 401。完整范围和剩余 Auth 设置项见 [SECURITY.md](../SECURITY.md)。Windows PowerShell 5.1 已解析全部安装脚本；设备报告脚本已对显式模拟器目标运行，自动手机选择会排除模拟器。

## 仍需目标手机确认

- 用本人华为开发者账号及目标手机 UDID 完成 HarmonyOS 调试签名，再 USB 安装。
- Mate 的 6.1.0.135 固件运行、拍照、相册选图、裁切及 OCR 识别。
- 使用真实 App 账号检查云端收藏读写、封面搜索、分类统计、设置、ZIP 备份导入导出、重启后登录与草稿，以及邮件找回密码返回 App。

华为 [textRecognition 文档](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/core-vision-text-recognition-api) 声明 Phone 支持该文字识别接口；本项目按其要求传入 RGBA_8888 PixelMap。该声明不能代替目标手机实测。安装见 [手机持有人教程](harmonyos-recipient-guide.md)，签名见 [开发者异地教程](harmonyos-developer-guide.md)。
