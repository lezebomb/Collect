# 给手机持有人的完整安装教程

适用：HUAWEI Mate 80 Pro Max，HarmonyOS 6.1.0.135 / API 24；本教程的电脑步骤适用于 Windows 10/11 x64。

你可以继续在手机上登录自己的华为账号。开发者用他的华为开发者账号为你的手机签名；App 内登录的是收藏柜邮箱账号，这三个账号的用途不同。签名需要你的手机 UDID。[华为调试 Profile 说明](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)。

## 1. 准备电脑、数据线和安装工具

你需要一台 Windows 电脑、一根支持数据传输的 USB 线，以及手机。

1. 在 [GitHub 发布页](https://github.com/lezebomb/Collect/releases/tag/harmony-v1.0.2-preview) 下载 `Dearshelf-Harmony-Install-Kit.zip`，完整解压，例如解压到 `C:\Dearshelf-Harmony`。不要在 ZIP 压缩包里面直接运行脚本。
2. 从 [华为官网下载 DevEco Studio](https://developer.huawei.com/consumer/cn/download/deveco-studio)，选择 Windows 6.1.1 版本并安装。需要登录下载时，可以使用你自己的华为账号。
3. 首次启动 DevEco Studio，按向导准备 HarmonyOS SDK 和工具。这里需要 SDK 中的 `hdc.exe`；本项目使用 API 24。你只负责安装现成的签名包，不需要另装 Flutter、Android Studio、Git、Node.js、Java 或手机模拟器，也不需要注册开发者。
4. 若脚本提示找不到 hdc，双击 `harmony\设置工具路径.cmd`，输入 DevEco 的安装目录，例如 `C:\Program Files\Huawei\DevEco Studio`。如果 SDK 保存在其他目录，也可以直接输入 `hdc.exe` 的完整路径；通常位于 SDK 的 `default\openharmony\toolchains\hdc.exe`。

完整源码也可从 [仓库](https://github.com/lezebomb/Collect) 的 **Code → Download ZIP** 下载；安装包的工具脚本都在 `harmony` 文件夹。普通安装使用上面的工具 ZIP 更方便。

## 2. 在手机开启 USB 调试

1. 打开“设置 → 关于本机”，连续快速点击软件版本号 7 次。
2. 按提示输入手机 PIN 并确认开启；系统要求重启时，等待重启完成。
3. 打开“设置 → 系统 → 开发者选项”，开启 USB 调试。
4. 用数据线连接电脑。解锁手机，在“允许 USB 调试”提示中点击允许。

菜单文字可能随系统略有不同。[华为开启开发者选项教程](https://consumer.huawei.com/cn/support/content/zh-cn02842747/)。

## 3. 获取这台手机的 UDID

双击解压目录中的 `harmony\获取手机信息.cmd`。成功后会生成 `harmony\device-info.txt`，包含 UDID、机型和 API 版本。请将这个文件私下交给开发者。

UDID 用于授权这台手机安装调试包，不是截图中的序列号或 IMEI。不要将它贴到公开 GitHub Issue。脚本不会读取你的收藏、照片或账号密码。若同时连接多台手机，先只保留这台手机。

## 4. 等待开发者签名

开发者收到 UDID 后，会用自己的开发者账号登记这台手机，生成调试 Profile，并发回已签名 `.hap` 文件。你不需要登录他的华为账号，也不需要得到签名私钥或证书密码。

发布页目前的 `unsigned.hap` 供构建和模拟器验证使用，不能装到你的手机。请等待为你这台手机生成的签名包；改文件名不能代替签名。

## 5. USB 安装签名 App

1. 将开发者发来的签名 `.hap` 保存在电脑上，保持手机解锁并连接 USB。
2. 把 `.hap` 文件拖到 `harmony\安装收到的HAP.cmd` 上。
3. 等窗口显示 `install bundle successfully`。脚本会启动 Dearshelf，之后可从手机桌面打开。

也可以将签名包放入 `harmony\output` 文件夹，再双击 `harmony\快速安装.cmd`。以后收到同一个开发者、同签名的新包，重复此步骤覆盖安装即可。

首次签名只授权指定设备；换手机需重新登记 UDID。证书或 Profile 到期时，需要开发者重新签名，实际到期时间以签名工具显示为准。

## 6. 登录和检查功能

使用你已获授权的收藏柜邮箱账号和原 App 密码登录；不要填写华为账号密码。服务器只接受开发者配置的两个已验证邮箱，其他人即使下载或修改客户端，也无法访问该项目的收藏数据或搜索服务。

按顺序检查：原有收藏和设置是否正常；新增一个测试收藏；编辑名称、分类与价格；相册选封面、裁切；相机拍照、文字识别和封面搜索；分类筛选、排序和统计；退出并重开后的登录状态与草稿；ZIP 导出，再导入测试备份；最后删除刚创建的测试收藏。图片和备份保留在你自己的设备，勿上传公开仓库。

目前开发者已完成 87 项自动化测试和官方 API 24 模拟器验证；目标 Mate 的拍照、OCR、真实账号完整流程仍需要你实际检查。

## 常见问题

| 提示 | 处理 |
| --- | --- |
| 找不到 hdc.exe | 完成 SDK 安装，再运行设置工具路径；可直接指定完整 hdc.exe 路径 |
| 没有连接真机 | 检查数据线、开发者选项与 USB 调试，重新插拔并在手机允许连接；必要时切换 USB 为“传输文件” |
| 没有签名包 / unsigned | 等开发者发回指定手机的签名 HAP |
| signature verification failed / UDID | 把完整报错交给开发者，重新检查签名 Profile 是否包含你的 UDID |
| install sign info inconsistent | 旧包和新包签名不同；先联系开发者核对，不要直接卸载，卸载会丢失本地草稿与缓存 |
| debug bundle can only be installed in developer mode | 重新开启开发者模式和 USB 调试 |
| 此应用仅向获准的邮箱开放 | 确认用的是收藏柜授权邮箱，邮箱已验证；由开发者检查服务器名单 |
| 暂时无法验证访问权限 | 检查网络后点击“重新检查”；持续失败时提供报错及时间给开发者 |
| OCR 不可用或拍照失败 | 提供操作步骤、系统版本及错误文字；目前仍待这台真机验证，不要把模拟器结果当作已经通过 |

官方错误说明：[华为 bm 工具与安装错误码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-v5/bm-tool-V5)。

## 开发者负责的事项

开发者注册自己的华为开发者账号；收到你的 UDID 后配置调试签名；发送签名 HAP；维护收藏柜的服务器白名单；根据你的验收结果修复问题。开发者的操作见 [异地签名教程](harmonyos-developer-guide.md)。
