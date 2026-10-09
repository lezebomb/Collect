function Resolve-HarmonyHdc {
    param([string]$HdcPath, [string]$StudioPath)
    $taskConfigPath = Join-Path $PSScriptRoot 'local-tools.json'
    if (Test-Path -LiteralPath $taskConfigPath) {
        $taskConfig = Get-Content -Raw -LiteralPath $taskConfigPath | ConvertFrom-Json
        if (-not $HdcPath) { $HdcPath = $taskConfig.hdcPath }
        if (-not $StudioPath) { $StudioPath = $taskConfig.studioPath }
    }
    if ($HdcPath) {
        if (-not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) { throw '配置的 hdc.exe 路径不存在，请重新运行设置工具路径。' }
        return (Resolve-Path -LiteralPath $HdcPath).Path
    }
    $taskRoot = Split-Path $PSScriptRoot -Parent
    $taskStudios = @($StudioPath, (Join-Path $taskRoot '.tooling\deveco'),
        'C:\Program Files\Huawei\DevEco Studio','C:\Huawei\DevEco Studio',
        'C:\DevEco Studio','D:\DevEco Studio') | Where-Object { $_ }
    foreach ($taskStudio in $taskStudios) {
        $taskSdk = Join-Path $taskStudio 'sdk'
        if (Test-Path -LiteralPath $taskSdk) {
            $taskTool = Get-ChildItem -LiteralPath $taskSdk -Filter hdc.exe -Recurse -File | Select-Object -First 1
            if ($taskTool) { return $taskTool.FullName }
        }
    }
    $taskCommand = Get-Command hdc.exe -ErrorAction SilentlyContinue
    if ($taskCommand) { return $taskCommand.Source }
    throw '未找到华为 hdc.exe。请安装 DevEco Studio 及 SDK，或先双击设置工具路径.cmd。'
}

function Resolve-HarmonyPhone {
    param([string]$HdcPath, [string]$DeviceId)
    $taskTargets = @(& $HdcPath list targets | Where-Object { $_.Trim() -and $_ -notmatch '\[Empty\]' } | ForEach-Object { $_.Trim() })
    if ($LASTEXITCODE) { throw 'hdc 连接检查失败。' }
    if (-not $DeviceId) {
        $taskPhones = @($taskTargets | Where-Object { $_ -notmatch '^(127\.0\.0\.1|localhost):\d+$' })
        if ($taskPhones.Count -eq 0) { throw '没有连接真机。请开启手机开发者模式和 USB 调试，用数据线连接，并在手机上允许连接。' }
        if ($taskPhones.Count -gt 1) { throw '请只连接一台手机，或用 -DeviceId 指定目标手机。' }
        $DeviceId = $taskPhones[0]
    }
    if ($DeviceId -notin $taskTargets) { throw '指定设备未连接。' }
    return $DeviceId
}
