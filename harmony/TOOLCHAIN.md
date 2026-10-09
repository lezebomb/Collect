# 已验证的工具链

- DevEco Studio Windows 6.1.1.418（用户从华为官方下载）。安装器 Authenticode 状态 Valid，发行者 Huawei Technologies Co., Ltd.
- 官方 SDK HarmonyOS 6.1.1.125 / API 24，目标 API 24，最低 API 18。
- Flutter-OH 稳定 tag `3.41.10-ohos-1.0.0`，提交 `244a0e8abb3085e8675589b13e219af8c41cb7aa`。
- Dart 3.11.5，鸿蒙 Engine `ab1841593ed352873a3d26cb41e942e90b813be0`。
- Flutter-OH 来源：https://gitcode.com/CPF-Flutter/flutter_flutter.git
- DevEco 安装目录：`D:\Collect\.tooling\deveco`；Flutter-OH：`D:\Collect\.tooling\flutter-ohos`。
- 官方手机模拟器 HarmonyOS 6.1.1(24)，镜像软件版本 6.1.0.126，分辨率 1320 × 2848、密度 540。实例名 `Dearshelf_API24`。

本项目锁定上述 SDK 组合。不要直接更新 Flutter-OH 后沿用旧的原生缓存；不同版本可能要求更高的编译 SDK。

## 重跑系统接口测试

启动现有模拟器并连接后，在 `D:\Collect` 执行：

```powershell
& .\.tooling\deveco\tools\emulator\Emulator.exe -start Dearshelf_API24
& .\.tooling\deveco\sdk\default\openharmony\toolchains\hdc.exe tconn 127.0.0.1:5555
powershell -NoProfile -ExecutionPolicy Bypass -File .\harmony\test-native.ps1
```

测试会短暂在本地模拟器中替换 App 为独立诊断入口，再恢复 `output` 中可用于模拟器的正式入口包。脚本拒绝真实手机目标。

报告保存到 `.tooling\harmony-native-smoke-result.json`。`UNAVAILABLE_IN_THIS_EMULATOR` 表示未能在该镜像验证该能力，不能计为通过。
