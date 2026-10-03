$ErrorActionPreference = 'Stop'
$backendRoot = Join-Path $PSScriptRoot 'AksharBuddy\backend'
$venvPython = Join-Path $backendRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    & py -3.13 -m venv (Join-Path $backendRoot '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Install Python 3.13, then run this setup again.' }
}
& $venvPython -m pip install -r (Join-Path $backendRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Backend dependencies could not be installed. Check internet access and the installer output.' }
& $venvPython -m pip check
if ($LASTEXITCODE -ne 0) { throw 'Dependency verification failed.' }
Write-Host 'Backend dependencies installed. Tesseract with English, Hindi and Marathi language data, plus Android platform tools, must also be installed.'
Write-Host 'On the prepared project laptop these tools are already available. Run Start AksharBuddy.ps1.'
