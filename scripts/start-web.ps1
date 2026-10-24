param([ValidateRange(1024,65535)][int]$Port = 8080, [switch]$Build, [switch]$Background)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$clientRoot = Join-Path $projectRoot 'apps/client'
$webRoot = Join-Path $clientRoot 'build/web'
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    throw "포트 $Port 은 이미 사용 중이다. -Port로 다른 포트를 지정한다."
}
if ($Build -or -not (Test-Path (Join-Path $webRoot 'main.dart.js'))) {
    Push-Location $clientRoot
    try {
        & (Join-Path $projectRoot '.tools/flutter/bin/flutter.bat') build web --release --no-web-resources-cdn
        if ($LASTEXITCODE -ne 0) { throw 'Flutter 웹 빌드가 실패했다.' }
    } finally { Pop-Location }
}
$python = (Get-Command python -ErrorAction Stop).Source
$serverScript = Join-Path $PSScriptRoot 'local-web-server.py'
if ($Background) {
    $localDir = Join-Path $projectRoot '.local'
    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
    $serverArgs = @(('"' + $serverScript + '"'), "$Port", '--directory', ('"' + $webRoot + '"'))
    $server = Start-Process -FilePath $python -ArgumentList $serverArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $localDir 'web.stdout.log') -RedirectStandardError (Join-Path $localDir 'web.stderr.log')
    $server.Id | Set-Content (Join-Path $localDir 'web.pid')
    Write-Output "VoiceMate http://127.0.0.1:$Port/ (PID $($server.Id))"
} else {
    Write-Output "VoiceMate http://127.0.0.1:$Port/"
    & $python $serverScript $Port --directory $webRoot
}
