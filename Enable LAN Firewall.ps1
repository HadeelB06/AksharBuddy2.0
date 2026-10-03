# Run once as Administrator on your trusted Private Wi-Fi/hotspot network.
$ErrorActionPreference = 'Stop'
$name = 'AksharBuddy-Local-LAN-5000'
if (-not (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $name -DisplayName 'AksharBuddy local Wi-Fi backend' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5000 -Profile Private -RemoteAddress LocalSubnet | Out-Null
}
Write-Host 'Port 5000 is allowed from the local subnet on Private networks only.'
