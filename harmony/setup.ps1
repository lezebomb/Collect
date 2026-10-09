param([string]$StudioPath)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskFlutter = Join-Path $taskRoot '.tooling\flutter-ohos'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw '源码构建需要 Git for Windows。仅安装签名 HAP 的手机持有人不需要运行此脚本。' }
if (-not (Test-Path -LiteralPath $taskFlutter)) {
    New-Item -ItemType Directory -Path (Join-Path $taskRoot '.tooling') -Force | Out-Null
    & git -c core.longpaths=true clone --depth 1 --branch 3.41.10-ohos-1.0.0 https://gitcode.com/CPF-Flutter/flutter_flutter.git $taskFlutter
    if ($LASTEXITCODE) { throw 'Flutter-OH 下载失败，请检查网络后重试。' }
}
$taskCommit = (& git -C $taskFlutter rev-parse HEAD).Trim()
if ($taskCommit -ne '244a0e8abb3085e8675589b13e219af8c41cb7aa') { throw 'Flutter-OH 与已验证版本不符。请查阅 TOOLCHAIN.md；本脚本不会覆盖现有 SDK。' }
. (Join-Path $PSScriptRoot 'env.ps1') -StudioPath $StudioPath
if (-not $env:HOS_SDK_HOME) { throw '没有找到 DevEco Studio。请用 -StudioPath 指定安装目录。' }
Push-Location $taskRoot
try {
    & node (Join-Path $taskRoot 'scripts\prepare_harmony.mjs')
    if ($LASTEXITCODE) { throw '工程初始化失败。' }
    Push-Location (Join-Path $PSScriptRoot 'app')
    try {
        & $script:HarmonyFlutter pub get
        if ($LASTEXITCODE) { throw '依赖下载失败。' }
    } finally { Pop-Location }
    Write-Output '已准备源码与依赖。配置 config\local.json 后，运行 build.ps1 -Unsigned，或在 DevEco 配置设备签名。'
} finally { Pop-Location }
