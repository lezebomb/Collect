# Dearshelf 品牌选定记录

用户已确认英文名称 **Dearshelf**，并选定南瓜猫窝中蜷睡小猫的第二版插画作为图标。此前的英文命名、抽象承托 Logo 和第一版写实猫窝属于探索历史，不再作为待选方案。

核心感受仍为：**为喜欢留位置，看见它们就开心。** 图标以暖橙南瓜猫窝、浅金色睡猫和薄荷背景表达舒适、亲近与安放，不含字母或文字。

## 已选美术与资源来源

- [选定插画原图](../assets/branding/dearshelf-pumpkin-cat.png)：保留用户确认的第二版图片。
- [透明前景](../assets/branding/dearshelf-pumpkin-cat-foreground.png)：使用 imagegen 内置工具移除外部薄荷背景，用于 Android Adaptive Icon；猫窝内部保留颜色。
- Android 背景色：`#C5FCF0`。
- [Android 导出脚本](../scripts/export_android_brand_icon.ps1)：使用 Windows 内置 System.Drawing 生成各密度 PNG，不新增应用依赖。

资源导出只进行尺寸与透明边距适配，不再重新设计图案。彩色 Adaptive Icon 使用 108 dp 画布，完整前景放在中央 66 dp 内，避免系统 Mask 裁掉南瓜、叶片或小猫。依据 [Android 官方 Adaptive Icon 指南](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。

重新导出：在 Windows PowerShell 中运行 `./scripts/export_android_brand_icon.ps1`。

## 本次手机应用范围

更新 Android 启动图标、系统显示名称与 Flutter 应用标题为 **Dearshelf**。保留原 applicationId、namespace、Dart package name、密码恢复链接、业务逻辑、数据库与备份格式。使用覆盖安装保留已有登录状态与收藏。

该图标安装阶段首页沿用“收藏柜”；后续已按用户要求改为 Dearshelf，见 [界面与草稿更新记录](ui_drafts_update.md)。中文功能正文保持原有语言。iOS 资源不在本次 Android 真机更新范围内。

原研究与概念文档保留为阶段性研究记录；本文件记录最新选择。

## 验证与安装结果

- `flutter analyze`：通过，无问题。
- `flutter test`：21 个现有测试全部通过。
- `flutter build apk --debug --dart-define-from-file=config/local.json`：通过。
- APK 元数据：显示名称 `Dearshelf`，原包名 `app.privatecollection.shou_cang_gui` 保持一致。
- 已在连接的 PLR110 / Android API 36 手机执行 `adb install -r`，返回 `Success`。
- 系统应用详情与桌面第三页均显示新名称和南瓜睡猫图标，图案完整可见。
- 升级后自动恢复原登录状态，原有 3 件收藏正常显示；稳定后展柜 UI 层级与升级前相同。
- 点击桌面新图标可正常打开应用。安装时间记录保留原 firstInstallTime，属于覆盖更新。
- 无新增应用依赖，无数据库 / 迁移、业务层、备份格式或应用身份变更。

构建产物：`build/app/outputs/flutter-apk/app-debug.apk`。本次未修改 iOS 资源。

## 透明前景处理提示词

使用 imagegen 内置工具，输入为选定插画原图；`transparent_background = true`。以下保留实际提示词，便于后续追溯。其他屏幕密度 PNG 由导出脚本生成。

```text
Use case: background-extraction.
Input image: EDIT TARGET, the user's approved final Dearshelf icon illustration.
The user has chosen THIS EXACT illustration. Make only a technical background removal for an Android adaptive-icon foreground.
Remove ONLY the flat pale mint-aqua background outside the pumpkin, leaf and stalk. Output genuine alpha transparency there. Retain the complete pumpkin-shaped cat cave, every contour of its lobes, its top stalk and green leaf, the arched opening, the kitten curled asleep inside, the interior and cream cushion. Retain the approved exact colors, positions, proportions, shapes, face, closed eyes, tabby stripes, tail, and rendering. The interior of the cat cave stays colored and opaque. Do NOT remove colors similar to the backdrop inside the subject, do not alter the art style, redraw or simplify the cat or pumpkin, do not add any stroke. No outside shadow or matte halo.
Preserve the same square canvas, original placement and scale. Do not crop the art. All foreground edges need clean alpha. No wordmark, labels, other elements or added content. This is asset preparation, not a new design proposal.
```
