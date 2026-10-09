param([string]$StudioPath, [string]$HdcPath)
$ErrorActionPreference = 'Stop'
if (-not $StudioPath -and -not $HdcPath) {
    $taskInput = (Read-Host '输入 DevEco Studio 安装目录，或 hdc.exe 的完整路径').Trim().Trim('"')
    if ($taskInput.EndsWith('hdc.exe',[StringComparison]::OrdinalIgnoreCase)) { $HdcPath = $taskInput }
    else { $StudioPath = $taskInput }
}
if ($HdcPath -and -not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) { throw 'hdc.exe 路径不存在。' }
if ($StudioPath -and -not (Test-Path -LiteralPath (Join-Path $StudioPath 'sdk'))) { throw '安装目录内没有 sdk 文件夹，请检查是否已安装 HarmonyOS SDK。' }
@{studioPath=$StudioPath;hdcPath=$HdcPath} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'local-tools.json') -Encoding UTF8
Write-Output '工具路径已保存。现在可以双击获取手机信息或快速安装。'
