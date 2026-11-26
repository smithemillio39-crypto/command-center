# End-to-end check for /input {"t":"type"}.
#
# Opens a small top-most window with a focused text box, asks the running agent
# to type into it through the same HTTP path the phone uses, then prints what
# the box actually received. Nothing else on the desktop is touched.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File test-type.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Foreground {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr handle, System.Text.StringBuilder text, int count);
    public static string Title(IntPtr handle) {
        var buffer = new System.Text.StringBuilder(256);
        GetWindowText(handle, buffer, buffer.Capacity);
        return buffer.ToString();
    }
}
"@

$port = 8765
$token = ''
$configPath = Join-Path $PSScriptRoot 'agent.config.json'
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($config.port) { $port = [int]$config.port }
    if ($config.token) { $token = [string]$config.token }
}

$script:sent = 'not sent'
$script:received = ''
$script:timer = $null

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Command Center typing check'
$form.ClientSize = New-Object System.Drawing.Size(420, 120)
$form.TopMost = $true
$form.StartPosition = 'CenterScreen'

$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.Dock = [System.Windows.Forms.DockStyle]::Fill
$box.Font = New-Object System.Drawing.Font('Consolas', 11)
$form.Controls.Add($box)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({
    $script:timer.Stop()
    $script:focus = [Foreground]::Title([Foreground]::GetForegroundWindow())
    try {
        $body = @{ t = 'type'; text = 'typing ok 42' } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "http://127.0.0.1:$port/input?token=$token" -Method Post `
            -Body $body -ContentType 'application/json' | Out-Null
        $script:sent = 'accepted'
    } catch {
        $script:sent = "failed: $($_.Exception.Message)"
    }
    # The helper compiles its native bindings on first use, so allow a few
    # seconds before deciding nothing arrived.
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and -not $box.Text) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
    $script:received = $box.Text
    $form.Close()
})
$script:timer = $timer

$form.Add_Shown({
    [Foreground]::SetForegroundWindow($form.Handle) | Out-Null
    $form.Activate()
    $box.Focus()
    $box.Select()
    $script:timer.Start()
})

[void]$form.ShowDialog()
$form.Dispose()

Write-Output "focus  : $($script:focus)"
Write-Output "api    : $($script:sent)"
Write-Output "typed  : $($script:received)"
if ($script:received -eq 'typing ok 42') {
    Write-Output 'TYPE OK'
    exit 0
}
Write-Output 'TYPE FAILED'
exit 1
