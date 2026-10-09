param([string]$StudioPath, [ValidateSet('debug','release')][string]$Mode = 'release',
    [ValidateSet('ohos-arm64','ohos-x64','ohos-arm64,ohos-x64')][string]$TargetPlatform = 'ohos-arm64',
    [switch]$Unsigned)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1') -StudioPath $StudioPath
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskApp = Join-Path $PSScriptRoot 'app'
if (-not $env:HOS_SDK_HOME) { throw '请先安装 DevEco Studio，或用 -StudioPath 指定安装目录。' }
$taskConfig = Join-Path $taskRoot '.tooling\phone-preview.json'
if (-not (Test-Path -LiteralPath $taskConfig)) { $taskConfig = Join-Path $taskRoot 'config\local.json' }
if (-not (Test-Path -LiteralPath $taskConfig)) { throw '缺少现有 App 的运行配置。' }
Push-Location $taskRoot
try {
    & node (Join-Path $taskRoot 'scripts\prepare_harmony.mjs')
    if ($LASTEXITCODE) { throw '准备源码失败。' }
    Push-Location $taskApp
    try {
        & $script:HarmonyFlutter pub get
        if ($LASTEXITCODE) { throw '依赖下载失败。' }
        $taskProfile = Get-Content -LiteralPath (Join-Path $taskApp 'ohos\build-profile.json5') -Raw
        $taskBuildArgs = @('build', 'hap', "--$Mode", '--target-platform', $TargetPlatform, "--dart-define-from-file=$taskConfig")
        $taskUnsignedBuild = $Unsigned -or $taskProfile -notmatch 'signingConfig["'']?\s*:'
        if ($taskUnsignedBuild) {
            $taskBuildArgs += '--no-codesign'
            Write-Output '构建未签名 HAP；真机安装前仍需为目标手机完成华为签名。'
        }
        & $script:HarmonyFlutter @taskBuildArgs
        if ($LASTEXITCODE) { throw 'HAP 构建失败。请保留日志。' }
        $taskHaps = Get-ChildItem -LiteralPath (Join-Path $taskApp 'build\ohos\hap') -Filter '*.hap' -File |
            Where-Object { ($_.Name -match 'unsigned') -eq $taskUnsignedBuild } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $taskHaps) { throw '构建完成但没有发现 HAP。' }
        $taskOutput = Join-Path $PSScriptRoot 'output'
        New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
        $taskSuffix = if ($taskUnsignedBuild) { 'unsigned' } else { 'signed' }
        foreach ($taskHap in $taskHaps) {
            Copy-Item -LiteralPath $taskHap.FullName -Destination (Join-Path $taskOutput "Dearshelf-$Mode-$($TargetPlatform.Replace(',','+'))-$taskSuffix.hap")
        }
        Get-ChildItem -LiteralPath $taskOutput -Filter '*.hap' | Get-FileHash -Algorithm SHA256
    } finally { Pop-Location }
} finally { Pop-Location }
