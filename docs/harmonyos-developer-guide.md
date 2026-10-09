# 开发者：给异地手机签名并交付

手机持有人先完成[她的安装准备和 UDID 获取](harmonyos-recipient-guide.md)。本教程由开发者执行，不要求她注册开发者或登录你的华为账号。目标是为她的 Mate 80 Pro Max / HarmonyOS 6.1.0.135 / API 24 生成可 USB 安装的 HarmonyOS 调试 HAP。

## 1. 准备开发者账号和工程

用自己的实名华为账号进入[开发者联盟](https://developer.huawei.com/consumer/cn/)，按页面要求完成个人开发者注册。然后登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)。

当前开发电脑已经安装工具并完成构建，工作目录为 `D:\Collect`，可直接进入第 2 步。另一台电脑从零准备时：

1. 下载并安装 Windows DevEco Studio **6.1.1**，准备 API 24 SDK；经过验证的具体版本见 [TOOLCHAIN.md](../harmony/TOOLCHAIN.md)。同时安装 Git for Windows，下载或克隆本仓库到短路径，例如 `D:\Collect`。
2. 在仓库根目录运行以下命令，将安装目录替换为实际路径。脚本下载锁定版本的 Flutter-OH，准备依赖与工程；初次下载需要网络。

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\harmony\set-tools.ps1 -StudioPath 'C:\Program Files\Huawei\DevEco Studio'
   powershell -NoProfile -ExecutionPolicy Bypass -File .\harmony\setup.ps1
   ```

3. 复制 `config/app_config.example.json` 为 `config/local.json`，填入对应 Supabase URL 和 Publishable Key。当前服务器使用 `COLLECTION_PRIVATE_ACCESS=false`、`COLLECTION_EMAIL_ALLOWLIST=true`、`COLLECTION_ALLOW_REGISTRATION=false`。前一个开关控制可选图片预留协议，独立邮箱限制仍由服务器强制执行。
4. 先运行 `harmony\build.ps1 -Unsigned` 完成原生依赖生成，再双击 `harmony\打开鸿蒙工程.cmd`。等待工程同步。不要使用普通 Flutter SDK 构建鸿蒙工程。

公开源码没有配置真实成员邮箱、签名密钥或管理员密钥。使用他人的后端必须获得授权；自己部署时见仓库 [安全说明](../SECURITY.md)。

## 2. 获取目标 UDID 并登记应用

收到她私下发送的 `device-info.txt`，确认型号、API 24 与 UDID。截图中的 IMEI、序列号不能替代 UDID。将文件保存在私有目录。

在 AGC 创建 HarmonyOS 应用/APP ID，包名必须与工程一致：

```text
app.privatecollection.shou_cang_gui
```

应用名称可用 Dearshelf / 收藏柜。在 AGC 的“证书、APP ID和Profile”下登记目标调试设备，填写她提供的 UDID。这里只准备指定设备调试，不需要先向应用市场提交审核。[华为调试 Profile 文档](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)。

本工程锁定 API 24。华为文档说明，仅从 API 26 起，自动签名支持仅凭 AGC 注册设备启动签名，因此异地手机使用下面的**手动签名**流程。如果手机实际连接你的开发电脑，才可选择含该手机信息的自动签名。[自动签名说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)。

## 3. 准备相互配套的密钥、证书与 Profile

在 DevEco 主菜单 **Build → Generate Key and CSR** 创建密钥库 `.p12` 与证书请求 `.csr`；记录密码和 alias，保存到私有目录，例如仓库外的签名目录。

用该 CSR 在 AGC 申请并下载 **HarmonyOS 调试证书** `.cer`。再创建**调试类型**的 Profile，选择本应用、同一调试证书，以及刚登记的她的设备，下载 `.p7b`。不要使用发布证书、另一套密钥或只有模拟器 UDID 的 Profile。以上文件必须配套。[华为手动签名教程](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-manual)，[申请调试证书](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-cert-0000002283256797)。

## 4. 在工程中配置手动签名

打开 **File → Project Structure → Project → Signing Configs**。取消 **Automatically generate signature** 和 **Associate with registered application**；若显示 **Support HarmonyOS**，使用 HarmonyOS 签名。

填入配套的 `.p12`、其密码和 alias、`.p7b`、`.cer`。界面中对应名称通常为 Store file / Store password / Key alias / Key password / Profile file / Certpath file；算法为 `SHA256withECDSA`。点击 **Apply / OK**。此处按华为界面填写自己的签名材料，完整字段说明以[官方手动签名页面](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-manual)为准。

签名信息保存在 `harmony/app/ohos/build-profile.json5`。该文件已忽略；公开仓库只提供无凭据的 `build-profile.template.json5`。密钥、密码材料和设备文件保留本地，不上传 GitHub，也不发给手机持有人。

## 5. 构建 ARM64 手机包并交付

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\harmony\build.ps1
Get-FileHash .\harmony\output\Dearshelf-release-ohos-arm64-signed.hap -Algorithm SHA256
```

应得到 `harmony/output/Dearshelf-release-ohos-arm64-signed.hap`。检查构建确实使用签名配置，保留包与 SHA-256。构建脚本在没有签名时会明确生成 `unsigned.hap`，不能将它当作签名包交付。

私下发给她：签名 HAP、它的校验值，以及[手机持有人教程](harmonyos-recipient-guide.md)。她从发布页下载安装工具 ZIP，准备好 USB 后，将 HAP 拖到 `harmony\安装收到的HAP.cmd`。她不需要源码构建工具，也不需要你的开发者账号密码。

## 6. 验收与后续更新

收到安装和功能检查结果后，重点核对拍照、相册、裁切、系统 OCR、登录持久化、找回密码返回 App、云端读写与 ZIP 往返。现有模拟器不能证明这台固件的全部功能；[验证记录](harmonyos-verification.md)列出了已测范围。

更新保持相同包名和签名，提高版本号，重新构建并覆盖安装。保管原密钥；换签名可能导致无法覆盖旧包。证书或 Profile 到期、设备更换、Profile 新增设备时，需下载有效 Profile 并重新签名。以实际签名材料显示的有效期为准。
