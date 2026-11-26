# Opens the Command Center remote as its own phone-shaped window.
#
# Uses Edge or Chrome in app mode (no address bar, no tabs), sized like a phone.
# A dedicated browser profile keeps it separate from your normal browsing.

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$configPath = Join-Path $root 'agent.config.json'
if (-not (Test-Path $configPath)) {
    Write-Error "agent.config.json is missing next to remote.ps1"
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$port = if ($config.port) { [int]$config.port } else { 8765 }
$token = [string]$config.token
$url = "http://127.0.0.1:$port/remote?token=$token"

$candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
$browser = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($browser) {
    $profile = Join-Path $env:LOCALAPPDATA 'CommandCenter\remote-profile'
    Start-Process -FilePath $browser -ArgumentList @(
        "--app=$url",
        '--window-size=432,900',
        '--window-position=100,70',
        "--user-data-dir=$profile"
    )
} else {
    # No Chromium browser: fall back to the default one, which still works.
    Start-Process $url
}
