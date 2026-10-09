param([string]$StudioPath, [string]$DeviceId = '127.0.0.1:5555')
$ErrorActionPreference = 'Stop'
if ($DeviceId -notmatch '^127\.0\.0\.1:\d+$') {
    throw '此诊断脚本仅用于本地模拟器。不能用它覆盖真实手机上的 App。'
}
. (Join-Path $PSScriptRoot 'env.ps1') -StudioPath $StudioPath
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskHdc = Get-ChildItem -LiteralPath $env:HOS_SDK_HOME -Filter hdc.exe -Recurse -File | Select-Object -First 1
if (-not $taskHdc) { throw '没有找到华为 hdc 工具。' }
$taskTargets = @(& $taskHdc.FullName list targets)
if ($DeviceId -notin $taskTargets) {
    throw '请先启动 Dearshelf_API24 模拟器，并用 hdc tconn 127.0.0.1:5555 连接。'
}
Push-Location (Join-Path $PSScriptRoot 'app')
try {
    & node (Join-Path $taskRoot 'scripts\prepare_harmony.mjs')
    if ($LASTEXITCODE) { throw '准备测试源码失败。' }
    & $script:HarmonyFlutter build hap --debug --target-platform ohos-x64 --no-codesign --target lib/harmony_native_smoke.dart
    if ($LASTEXITCODE) { throw '原生测试包编译失败。' }
    $taskReportPath = '/data/app/el2/100/base/app.privatecollection.shou_cang_gui/haps/entry/files/native-smoke.json'
    & $taskHdc.FullName -t $DeviceId shell rm -f $taskReportPath
    try {
        & $taskHdc.FullName -t $DeviceId install -r (Join-Path $PSScriptRoot 'app\build\ohos\hap\entry-default-unsigned.hap')
        if ($LASTEXITCODE) { throw '模拟器测试包安装失败。' }
        & $taskHdc.FullName -t $DeviceId shell aa force-stop app.privatecollection.shou_cang_gui
        & $taskHdc.FullName -t $DeviceId shell aa start -a EntryAbility -b app.privatecollection.shou_cang_gui
        $taskReport = $null
        for ($taskAttempt = 0; $taskAttempt -lt 30; $taskAttempt++) {
            Start-Sleep -Seconds 2
            $taskText = (& $taskHdc.FullName -t $DeviceId shell cat $taskReportPath 2>$null) -join "`n"
            try { $taskReport = $taskText | ConvertFrom-Json } catch { continue }
            if ($taskReport) { break }
        }
        if (-not $taskReport) { throw '没有收到测试报告，请保留模拟器日志。' }
        $taskReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskRoot '.tooling\harmony-native-smoke-result.json') -Encoding UTF8
        $taskReport | ConvertTo-Json -Depth 4
        if (@($taskReport.PSObject.Properties | Where-Object { $_.Value -is [string] -and $_.Value.StartsWith('FAIL:') }).Count) {
            throw '存在原生接口测试失败。'
        }
        Write-Output '原生测试已完成。UNAVAILABLE_IN_THIS_EMULATOR 表示该能力仍待真机验证。'
    } finally {
        $taskRelease = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'output') -Filter '*release*unsigned.hap' -File |
            Where-Object { $_.Name -match 'ohos-x64' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($taskRelease) {
            & $taskHdc.FullName -t $DeviceId install -r $taskRelease.FullName
            & $taskHdc.FullName -t $DeviceId shell aa start -a EntryAbility -b app.privatecollection.shou_cang_gui
        }
    }
} finally { Pop-Location }
