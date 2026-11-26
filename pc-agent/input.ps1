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
#   {"t":"type","text":"hello"}       type a whole string as Unicode keystrokes

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CCInput {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, int data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public InputUnion U; }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint count, INPUT[] inputs, int size);

    const uint INPUT_KEYBOARD = 1;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint KEYEVENTF_UNICODE = 0x0004;

    // Types text as Unicode keystrokes so any character reaches the focused
    // control. Newline and tab are sent as real keys; the clipboard is not used.
    public static uint TypeText(string text) {
        uint sent = 0;
        if (text == null) return sent;
        int size = Marshal.SizeOf(typeof(INPUT));
        foreach (char ch in text) {
            if (ch == '\r') continue;
            ushort vk = 0;
            ushort scan = ch;
            uint flags = KEYEVENTF_UNICODE;
            if (ch == '\n') { vk = 0x0D; scan = 0; flags = 0; }
            else if (ch == '\t') { vk = 0x09; scan = 0; flags = 0; }

            INPUT down = new INPUT();
            down.type = INPUT_KEYBOARD;
            down.U.ki.wVk = vk;
            down.U.ki.wScan = scan;
            down.U.ki.dwFlags = flags;
            INPUT up = new INPUT();
            up.type = INPUT_KEYBOARD;
            up.U.ki.wVk = vk;
            up.U.ki.wScan = scan;
            up.U.ki.dwFlags = flags | KEYEVENTF_KEYUP;
            sent += SendInput(1, new INPUT[] { down }, size);
            sent += SendInput(1, new INPUT[] { up }, size);
        }
        return sent;
    }
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
        'type' {
            $text = [string]$message.text
            $sent = [CCInput]::TypeText($text)
            # Two inputs per character (down + up); anything less means the
            # keystrokes were refused (for example by an elevated foreground
            # window) and the phone should hear about it.
            if ($sent -lt (2 * $text.Length)) {
                [Console]::Error.WriteLine("typing: only $sent of $($text.Length * 2) keystroke inputs were accepted")
            }
        }
    }
}
