# Command Center window switcher helper.
#
#   windows.ps1 -List              JSON array of the PC's open windows
#   windows.ps1 -Activate <hwnd>   bring that window to the front, restoring it
#                                  if it was minimised
#
# Only real, visible, non-cloaked application windows are listed, newest on top.
# That is what makes a phone tap land on the window you can see, instead of on a
# ghost window left behind by a store app.

param(
    [switch]$List,
    [long]$Activate = 0
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CCWindows
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attach, uint attachTo, bool join);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int DWMWA_CLOAKED = 14;

    private static bool IsCloaked(IntPtr hWnd)
    {
        int cloaked;
        if (DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, sizeof(int)) != 0) return false;
        return cloaked != 0;
    }

    public static List<string> List()
    {
        var found = new List<string>();
        EnumWindows((hWnd, lParam) =>
        {
            if (!IsWindowVisible(hWnd)) return true;
            if (IsCloaked(hWnd)) return true;

            int style = GetWindowLong(hWnd, GWL_EXSTYLE);
            if ((style & WS_EX_TOOLWINDOW) != 0) return true;

            int length = GetWindowTextLength(hWnd);
            if (length <= 0) return true;

            RECT rect;
            if (GetWindowRect(hWnd, out rect))
            {
                if (rect.Right - rect.Left < 40 || rect.Bottom - rect.Top < 24) return true;
            }

            var title = new StringBuilder(length + 2);
            GetWindowText(hWnd, title, title.Capacity);

            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);

            // "hwnd\tpid\tminimized\ttitle"
            found.Add(string.Join("\t", new string[] {
                hWnd.ToInt64().ToString(),
                pid.ToString(),
                (IsIconic(hWnd) ? "1" : "0"),
                title.ToString()
            }));
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static bool Activate(long handle)
    {
        IntPtr hWnd = new IntPtr(handle);
        if (hWnd == IntPtr.Zero) return false;

        if (IsIconic(hWnd)) ShowWindow(hWnd, 9);   // SW_RESTORE
        else ShowWindow(hWnd, 5);                  // SW_SHOW

        // Windows only lets the foreground process take focus, so borrow the
        // current foreground thread's input state for the two calls it needs.
        IntPtr foreground = GetForegroundWindow();
        uint foregroundThread = 0;
        if (foreground != IntPtr.Zero)
        {
            uint ignored;
            foregroundThread = GetWindowThreadProcessId(foreground, out ignored);
        }
        uint thisThread = GetCurrentThreadId();
        bool joined = foregroundThread != 0 && foregroundThread != thisThread
            && AttachThreadInput(foregroundThread, thisThread, true);

        BringWindowToTop(hWnd);
        bool ok = SetForegroundWindow(hWnd);

        if (joined) AttachThreadInput(foregroundThread, thisThread, false);
        return ok;
    }
}
"@

if ($Activate -ne 0) {
    $worked = [CCWindows]::Activate($Activate)
    [pscustomobject]@{ ok = $worked; hwnd = $Activate } | ConvertTo-Json -Compress
    exit 0
}

$windows = @()
# EnumWindows walks front to back, so the list is already in z-order.
foreach ($row in [CCWindows]::List()) {
    $parts = $row -split "`t", 4
    if ($parts.Count -lt 4) { continue }

    $pidValue = 0
    [void][int]::TryParse($parts[1], [ref]$pidValue)
    $processName = ''
    try { $processName = (Get-Process -Id $pidValue -ErrorAction Stop).ProcessName } catch { }

    $windows += [pscustomobject]@{
        hwnd      = [long]$parts[0]
        pid       = $pidValue
        minimized = $parts[2] -eq '1'
        process   = $processName
        title     = $parts[3].Trim()
    }
}

ConvertTo-Json -InputObject @($windows) -Compress -Depth 3
