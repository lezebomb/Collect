param([string]$HapPath, [string]$HdcPath, [string]$DeviceId, [string]$StudioPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hdc-tools.ps1')
$HdcPath = Resolve-HarmonyHdc -HdcPath $HdcPath -StudioPath $StudioPath
$DeviceId = Resolve-HarmonyPhone -HdcPath $HdcPath -DeviceId $DeviceId
if (-not $HapPath) {
    $taskCandidates = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'output') -Filter '*signed.hap' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'unsigned' } | Sort-Object LastWriteTime -Descending
    $HapPath = ($taskCandidates | Select-Object -First 1).FullName
}
if (-not $HapPath) { throw '还没有已签名 HAP。请等开发者为这台手机完成签名，再把签名包放入 harmony\output。' }
$taskHap = Get-Item -LiteralPath $HapPath
if ($taskHap.Extension -ne '.hap' -or $taskHap.Name -match 'unsigned') { throw '请选择已完成 HarmonyOS 设备签名的 HAP，未签名包不能安装。' }
$taskResult = & $HdcPath -t $DeviceId install -r $taskHap.FullName 2>&1
$taskResult | Write-Output
if ($LASTEXITCODE -ne 0 -or (($taskResult -join "`n") -notmatch 'success|Success')) { throw '安装未成功。请检查证书、设备 UDID、开发者模式和日志。' }
& $HdcPath -t $DeviceId shell aa start -a EntryAbility -b app.privatecollection.shou_cang_gui
if ($LASTEXITCODE -ne 0) { throw '安装成功，但应用启动失败。' }
