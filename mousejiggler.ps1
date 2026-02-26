# ==============================
# KeepAwakeGUI.ps1 (self-bypass)
# ==============================

# If execution policy blocks script, relaunch itself with -ExecutionPolicy Bypass
if (-not $env:KEEP_AWAKE_BYPASS) {
    $env:KEEP_AWAKE_BYPASS = "1"
    $psExe = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path $psExe)) { $psExe = "powershell.exe" }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )

    Start-Process -FilePath $psExe -ArgumentList $args -WindowStyle Normal
    exit
}

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
$form.Size = New-Object System.Drawing.Size(320,240)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = "Interval (seconds):"
$label.Location = New-Object System.Drawing.Point(20,20)
$label.AutoSize = $true
$form.Controls.Add($label)

$intervalBox = New-Object System.Windows.Forms.NumericUpDown
$intervalBox.Location = New-Object System.Drawing.Point(160,18)
$intervalBox.Minimum = 5
$intervalBox.Maximum = 3600
$intervalBox.Value = 30
$intervalBox.Width = 100
$form.Controls.Add($intervalBox)

$group = New-Object System.Windows.Forms.GroupBox
$group.Text = "Move pattern"
$group.Location = New-Object System.Drawing.Point(20,55)
$group.Size = New-Object System.Drawing.Size(260,80)
$form.Controls.Add($group)

$radioLR = New-Object System.Windows.Forms.RadioButton
$radioLR.Text = "Left / Right (±1 px)"
$radioLR.Location = New-Object System.Drawing.Point(10,20)
$radioLR.Checked = $true
$radioLR.AutoSize = $true
$group.Controls.Add($radioLR)

$radioDiag = New-Object System.Windows.Forms.RadioButton
$radioDiag.Text = "Diagonal (+1,+1 px)"
$radioDiag.Location = New-Object System.Drawing.Point(10,45)
$radioDiag.AutoSize = $true
$group.Controls.Add($radioDiag)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Status: stopped"
$status.Location = New-Object System.Drawing.Point(20,145)
$status.AutoSize = $true
$form.Controls.Add($status)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start"
$startButton.Location = New-Object System.Drawing.Point(40,175)
$startButton.Width = 100
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop"
$stopButton.Location = New-Object System.Drawing.Point(170,175)
$stopButton.Width = 100
$stopButton.Enabled = $false
$form.Controls.Add($stopButton)

$timer = New-Object System.Windows.Forms.Timer
$moveRight = $true

$timer.Add_Tick({
    $p = New-Object MouseMover+POINT
    [MouseMover]::GetCursorPos([ref]$p) | Out-Null

    if ($radioLR.Checked) {
        if ($moveRight) {
            [MouseMover]::SetCursorPos($p.X + 1, $p.Y) | Out-Null
        } else {
            [MouseMover]::SetCursorPos($p.X - 1, $p.Y) | Out-Null
        }
        $moveRight = -not $moveRight
    } else {
        [MouseMover]::SetCursorPos($p.X + 1, $p.Y + 1) | Out-Null
    }
})

$startButton.Add_Click({
    $timer.Interval = [int]$intervalBox.Value * 1000
    $timer.Start()
    $startButton.Enabled = $false
    $stopButton.Enabled = $true
    $status.Text = "Status: running (every $([int]$intervalBox.Value)s)"
})

$stopButton.Add_Click({
    $timer.Stop()
    $startButton.Enabled = $true
    $stopButton.Enabled = $false
    $status.Text = "Status: stopped"
})

$form.Add_FormClosing({
    if ($timer.Enabled) { $timer.Stop() }
})

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
