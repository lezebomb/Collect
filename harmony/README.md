# Dearshelf 鸿蒙版本

目标设备：HUAWEI Mate 80 Pro Max，HarmonyOS 6.1.0.135（截图 API 24）。

此目录保存鸿蒙适配层。构建脚本将当前 `lib/` 和测试复制到独立构建目录，继续使用相同收藏业务逻辑、Supabase 项目及 ZIP 备份格式，不修改安卓工程。

1.0.2(3) 已完成 Release 编译、87 项自动化测试和官方 API 24 模拟器验证。交付状态见 [安装入口](../docs/harmonyos-install.md)，实际测试范围见 [验证记录](../docs/harmonyos-verification.md)。未签名 HAP 需要开发者账号和目标手机 UDID 完成 HarmonyOS 调试签名后，才能安装到华为真机。

- 手机持有人：[完整安装教程](../docs/harmonyos-recipient-guide.md)，只安装 DevEco/hdc 并运行工具脚本。
- 开发者：[从源码构建到异地签名的教程](../docs/harmonyos-developer-guide.md)。新电脑运行 `setup.ps1` 下载锁定版本 Flutter-OH。
- [GitHub 下载页](https://github.com/lezebomb/Collect/releases/tag/harmony-v1.0.2-preview)提供安装工具 ZIP 和未签名预览包。

邮箱限制在服务器执行；当前构建使用独立邮箱限制，保留旧客户端图片上传协议。真实成员地址、本地配置、签名凭据与设备 UDID 不进入公开仓库。
