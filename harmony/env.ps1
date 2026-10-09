param([string]$StudioPath)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$env:PUB_CACHE = Join-Path $taskRoot '.tooling\ph'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'core.longpaths'
$env:GIT_CONFIG_VALUE_0 = 'true'
$script:HarmonyFlutter = Join-Path $taskRoot '.tooling\flutter-ohos\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $script:HarmonyFlutter)) {
    throw '鸿蒙 Flutter SDK 尚未下载。参见 harmony/README.md。'
}
$env:Path = (Split-Path $script:HarmonyFlutter -Parent) + ';' + $env:Path
if (-not $StudioPath -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'local-tools.json'))) {
    $taskTools = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'local-tools.json') | ConvertFrom-Json
    $StudioPath = $taskTools.studioPath
}
if (-not $StudioPath) {
    $taskCandidates = @(
        (Join-Path $taskRoot '.tooling\deveco'),
        (Join-Path $taskRoot '.tooling\command-line-tools'),
        'C:\Program Files\Huawei\DevEco Studio',
        'C:\Huawei\DevEco Studio',
        'D:\DevEco Studio'
    )
    $StudioPath = $taskCandidates | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ 'sdk')
    } | Select-Object -First 1
}
if ($StudioPath) {
    $env:DEVECO_SDK_HOME = Join-Path $StudioPath 'sdk'
    $env:HOS_SDK_HOME = $env:DEVECO_SDK_HOME
    $env:DEVECO_CLI_STUDIO_PATH = $StudioPath
    $taskNode = @((Join-Path $StudioPath 'tools\node'),
        (Join-Path $StudioPath 'tool\node')) | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ 'node.exe')
    } | Select-Object -First 1
    if ($taskNode) { $env:NODE_HOME = $taskNode }
    if (Test-Path -LiteralPath (Join-Path $StudioPath 'jbr\bin\java.exe')) {
        $env:JAVA_HOME = Join-Path $StudioPath 'jbr'
    }
    $taskBins = @($taskNode, (Join-Path $StudioPath 'tools\ohpm\bin'),
        (Join-Path $StudioPath 'tools\hvigor\bin'),
        (Join-Path $StudioPath 'bin'))
    if ($env:JAVA_HOME) { $taskBins += Join-Path $env:JAVA_HOME 'bin' }
    $env:Path = (($taskBins | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) -join ';') + ';' + $env:Path
}
