Add-Type @"
using System;
using System.Runtime.InteropServices;

public class MouseMover {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
}
"@

Write-Host "Keep Awake started. Press Ctrl+C to stop."

$moveRight = $true
$intervalSeconds = 30  # zmień jeśli chcesz

while ($true) {
    $point = New-Object MouseMover+POINT
    [MouseMover]::GetCursorPos([ref]$point) | Out-Null

    if ($moveRight) {
        [MouseMover]::SetCursorPos($point.X + 1, $point.Y)
    } else {
        [MouseMover]::SetCursorPos($point.X - 1, $point.Y)
    }

    $moveRight = -not $moveRight
    Start-Sleep -Seconds $intervalSeconds
}
