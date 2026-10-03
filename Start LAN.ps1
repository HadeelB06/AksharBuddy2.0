param([switch]$BackendOnly, [switch]$CheckOnly, [switch]$Usb)
$ErrorActionPreference = 'Stop'
$backendRoot = Join-Path $PSScriptRoot 'AksharBuddy\backend'
$pythonCandidates = @((Join-Path $backendRoot '.venv\Scripts\python.exe'), (Join-Path (Split-Path $PSScriptRoot -Parent) 'AksharAlly-verification-env\Scripts\python.exe'))
$pythonPath = $pythonCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $pythonPath) { throw 'Run Setup AksharBuddy.ps1 once to install backend requirements.' }
$addresses = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127|169\.254)\.' -and $_.AddressState -eq 'Preferred' })
Write-Host 'Connect phone and laptop to the SAME Wi-Fi or hotspot. Internet is not needed after setup.'
foreach ($address in $addresses) { Write-Host "Settings > Laptop connection: http://$($address.IPAddress):5000 ($($address.InterfaceAlias))" }
if ($CheckOnly) { Write-Host "Python: $pythonPath"; exit 0 }
$logRoot = Join-Path $PSScriptRoot 'local-logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$healthy = $false
try {
    $health = Invoke-RestMethod 'http://127.0.0.1:5000/health' -TimeoutSec 3
    if ($health.version -ne 'lan-repair-1') { throw 'OLD_BACKEND' }
    $healthy = $health.service -eq 'aksharbuddy'
} catch {
    if ($_.Exception.Message -eq 'OLD_BACKEND') { throw 'An older backend is running on port 5000. Close that backend before starting this repair version. No process was stopped.' }
}
if (-not $healthy) {
    $scriptPath = Join-Path $backendRoot 'run_local.py'
    Start-Process -FilePath $pythonPath -ArgumentList @('-B', '-u', ('"' + $scriptPath + '"')) -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logRoot 'backend.log') -RedirectStandardError (Join-Path $logRoot 'backend-error.log') | Out-Null
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Seconds 2
        try { $health=Invoke-RestMethod 'http://127.0.0.1:5000/health' -TimeoutSec 2; if ($health.version -eq 'lan-repair-1') { $healthy=$true; break } } catch { }
    }
}
if (-not $healthy) { throw "Backend did not start. See $logRoot\backend-error.log" }
Write-Host 'Backend ready. Open AksharBuddy on your phone. USB is not required.'
Write-Host 'If connection fails: use a Private Windows network and run Enable LAN Firewall.ps1 as Administrator once.'
if (-not $Usb -or $BackendOnly) { exit 0 }
$adb = @('C:\platform-tools\adb.exe', 'C:\Android\Sdk\platform-tools\adb.exe', (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $adb) { throw 'Install Android platform tools for optional USB development.' }
$devices = @(& $adb devices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if ($devices.Count -ne 1) { throw 'For -Usb only: connect one unlocked phone and accept USB debugging.' }
& $adb -s $devices[0] reverse tcp:5000 tcp:5000
if ($LASTEXITCODE -ne 0) { throw 'USB port forwarding failed.' }
Write-Host 'Optional USB fallback ready. Set the app backend URL to http://127.0.0.1:5000 while using USB.'
