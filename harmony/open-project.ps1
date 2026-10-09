$ErrorActionPreference = 'Stop'
$taskProfile = Join-Path $PSScriptRoot 'app\ohos\build-profile.json5'
if (-not (Test-Path -LiteralPath $taskProfile)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'app\ohos\build-profile.template.json5') -Destination $taskProfile
}
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskConfig = Join-Path $PSScriptRoot 'local-tools.json'
$taskStudios = @((Join-Path $taskRoot '.tooling\deveco'),'C:\Program Files\Huawei\DevEco Studio','C:\Huawei\DevEco Studio','D:\DevEco Studio')
if (Test-Path -LiteralPath $taskConfig) { $taskStudios = @((Get-Content -Raw $taskConfig | ConvertFrom-Json).studioPath) + $taskStudios }
$taskExe = $taskStudios | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'bin\devecostudio64.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $taskExe) { throw '请先安装 DevEco Studio，或用设置工具路径.cmd指定安装目录。' }
# This launcher is deliberately interactive: the user opens the signing editor.
Start-Process -FilePath $taskExe -ArgumentList ('"' + (Join-Path $PSScriptRoot 'app\ohos') + '"')
