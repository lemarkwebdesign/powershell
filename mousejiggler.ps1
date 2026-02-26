Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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

$form = New-Object System.Windows.Forms.Form
$form.Text = "Keep Awake Mouse Mover"
$form.Size = New-Object System.Drawing.Size(300,220)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Interval (seconds):"
$label.Location = New-Object System.Drawing.Point(20,20)
$form.Controls.Add($label)

$intervalBox = New-Object System.Windows.Forms.NumericUpDown
$intervalBox.Location = New-Object System.Drawing.Point(150,18)
$intervalBox.Minimum = 5
$intervalBox.Maximum = 600
$intervalBox.Value = 30
$form.Controls.Add($intervalBox)

$radioLR = New-Object System.Windows.Forms.RadioButton
$radioLR.Text = "Left / Right"
$radioLR.Location = New-Object System.Drawing.Point(20,60)
$radioLR.Checked = $true
$form.Controls.Add($radioLR)

$radioDiag = New-Object System.Windows.Forms.RadioButton
$radioDiag.Text = "Diagonal"
$radioDiag.Location = New-Object System.Drawing.Point(20,85)
$form.Controls.Add($radioDiag)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start"
$startButton.Location = New-Object System.Drawing.Point(40,130)
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop"
$stopButton.Location = New-Object System.Drawing.Point(150,130)
$stopButton.Enabled = $false
$form.Controls.Add($stopButton)

$timer = New-Object System.Windows.Forms.Timer
$moveRight = $true

$timer.Add_Tick({
    $point = New-Object MouseMover+POINT
    [MouseMover]::GetCursorPos([ref]$point) | Out-Null

    if ($radioLR.Checked) {
        if ($moveRight) {
            [MouseMover]::SetCursorPos($point.X + 1, $point.Y)
        } else {
            [MouseMover]::SetCursorPos($point.X - 1, $point.Y)
        }
        $moveRight = -not $moveRight
    }
    else {
        [MouseMover]::SetCursorPos($point.X + 1, $point.Y + 1)
    }
})

$startButton.Add_Click({
    $timer.Interval = [int]$intervalBox.Value * 1000
    $timer.Start()
    $startButton.Enabled = $false
    $stopButton.Enabled = $true
})

$stopButton.Add_Click({
    $timer.Stop()
    $startButton.Enabled = $true
    $stopButton.Enabled = $false
})

$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()
