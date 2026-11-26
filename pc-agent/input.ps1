# Command Center input helper.
#
# Reads one JSON command per line on stdin and applies it as a real Windows
# mouse or keyboard event. The agent keeps this process alive so a touch on the
# iPhone becomes a pointer move in a few milliseconds instead of a process
# launch per event.
#
#   {"t":"move","x":0.42,"y":0.31}   normalised 0..1 over the whole virtual desktop
#   {"t":"down","b":1}               press left (b:2 = right)
#   {"t":"up","b":1}
#   {"t":"click","b":1,"x":..,"y":..} optional coordinates first
#   {"t":"scroll","d":-3}            wheel steps, positive = up
#   {"t":"key","vk":13}              one virtual-key tap

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CCInput {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, int data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
"@

$LEFT_DOWN = 0x0002
$LEFT_UP = 0x0004
$RIGHT_DOWN = 0x0008
$RIGHT_UP = 0x0010
$WHEEL = 0x0800
$KEY_UP = 0x0002

function Move-Pointer([double]$x, [double]$y) {
    $width = [CCInput]::GetSystemMetrics(78)
    $height = [CCInput]::GetSystemMetrics(79)
    if ($width -le 0) { $width = [CCInput]::GetSystemMetrics(0) }
    if ($height -le 0) { $height = [CCInput]::GetSystemMetrics(1) }
    [CCInput]::SetCursorPos([int][Math]::Round($x * $width), [int][Math]::Round($y * $height)) | Out-Null
}

function Press-Button([int]$button, [bool]$down) {
    if ($button -eq 2) {
        $flag = if ($down) { $RIGHT_DOWN } else { $RIGHT_UP }
    } else {
        $flag = if ($down) { $LEFT_DOWN } else { $LEFT_UP }
    }
    [CCInput]::mouse_event($flag, 0, 0, 0, [UIntPtr]::Zero)
}

while ($null -ne ($line = [Console]::In.ReadLine())) {
    if (-not $line.Trim()) { continue }
    try { $message = $line | ConvertFrom-Json } catch { continue }

    $button = 1
    if ($null -ne $message.b) { $button = [int]$message.b }

    switch ([string]$message.t) {
        'move' { Move-Pointer -x ([double]$message.x) -y ([double]$message.y) }
        'down' { Press-Button -button $button -down $true }
        'up' { Press-Button -button $button -down $false }
        'click' {
            if ($null -ne $message.x) { Move-Pointer -x ([double]$message.x) -y ([double]$message.y) }
            Press-Button -button $button -down $true
            Press-Button -button $button -down $false
        }
        'scroll' { [CCInput]::mouse_event($WHEEL, 0, 0, [int]$message.d, [UIntPtr]::Zero) }
        'key' {
            $vk = [byte][int]$message.vk
            [CCInput]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
            [CCInput]::keybd_event($vk, 0, $KEY_UP, [UIntPtr]::Zero)
        }
    }
}
