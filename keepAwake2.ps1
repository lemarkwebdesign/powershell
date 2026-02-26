Add-Type @"
using System;
using System.Runtime.InteropServices;

public class InputSimulator
{
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT
    {
        public uint type;
        public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    const int INPUT_MOUSE = 0;
    const uint MOUSEEVENTF_MOVE = 0x0001;

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    public static void MoveMouse(int dx, int dy)
    {
        INPUT[] inputs = new INPUT[1];
        inputs[0].type = INPUT_MOUSE;
        inputs[0].mi.dx = dx;
        inputs[0].mi.dy = dy;
        inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE;
        SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@

Write-Host "RDP-compatible KeepAlive started. CTRL+C to stop."

$direction = 1

while ($true) {
    [InputSimulator]::MoveMouse($direction, 0)
    $direction = -$direction
    Start-Sleep -Seconds 5
}
