param([string]$HdcPath, [string]$StudioPath, [string]$DeviceId)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hdc-tools.ps1')
$HdcPath = Resolve-HarmonyHdc -HdcPath $HdcPath -StudioPath $StudioPath
$DeviceId = Resolve-HarmonyPhone -HdcPath $HdcPath -DeviceId $DeviceId
$taskUdidText = (& $HdcPath -t $DeviceId shell bm get -u) -join "`n"
if ($LASTEXITCODE) { throw '读取 UDID 失败，请确认手机已允许 USB 调试。' }
$taskMatch = [regex]::Match($taskUdidText,'[a-zA-Z0-9]{32,}')
if (-not $taskMatch.Success) { throw '没有读到有效 UDID，请保留窗口中的错误信息。' }
$taskModel = ((& $HdcPath -t $DeviceId shell param get const.product.model) -join '').Trim()
$taskApi = ((& $HdcPath -t $DeviceId shell param get const.ohos.apiversion) -join '').Trim()
$taskReport = "UDID=$($taskMatch.Value)`r`nModel=$taskModel`r`nAPI=$taskApi`r`n"
$taskOutput = Join-Path $PSScriptRoot 'device-info.txt'
[IO.File]::WriteAllText($taskOutput,$taskReport,[Text.UTF8Encoding]::new($true))
Write-Output $taskReport
Write-Output "已保存到 $taskOutput。请私下发送此文件给开发者，用于这台手机的签名。"
