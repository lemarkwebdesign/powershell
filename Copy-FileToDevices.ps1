Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# CONFIG (set once and forget)
# =========================
$DevicesFileName = "devices.txt"
$LocalFileName   = "payload.bin"
$RemotePath      = "/var/tmp/payload.bin"
$PscpPath        = "pscp.exe"
$Port            = 22
$Protocol        = "scp"   # "scp" or "sftp"
# =========================

function ConvertTo-PlainText([Security.SecureString]$Secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Invoke-PscpWithAutoYes {
    param(
        [string]$PscpPath,
        [string]$Device,
        [int]$Port,
        [string]$Username,
        [string]$Password,
        [string]$LocalPath,
        [string]$RemotePath,
        [string]$Protocol
    )

    $args = New-Object System.Collections.Generic.List[string]
    $args.Add("-v")
    $args.Add("-no-sanitise-stderr")
    $args.Add("-P");  $args.Add("$Port")
    $args.Add("-l");  $args.Add($Username)
    $args.Add("-pw"); $args.Add($Password)

    if ($Protocol -eq "sftp") { $args.Add("-sftp") } else { $args.Add("-scp") }

    $args.Add($LocalPath)
    $args.Add("$Device`:$RemotePath")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PscpPath
    $psi.Arguments = ($args -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    # Auto-accept first-time host key prompt
    $p.StandardInput.WriteLine("y")
    $p.StandardInput.Close()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Args     = $psi.Arguments
    }
}

# Paths relative to the script location
$ScriptDir   = Split-Path -Parent $PSCommandPath
$DevicesPath = Join-Path $ScriptDir $DevicesFileName
$LocalPath   = Join-Path $ScriptDir $LocalFileName

if (-not (Test-Path -LiteralPath $DevicesPath)) { throw "Missing devices list file: $DevicesPath" }
if (-not (Test-Path -LiteralPath $LocalPath))   { throw "Missing local file to copy: $LocalPath" }

try { $null = Get-Command $PscpPath -ErrorAction Stop }
catch { throw "pscp.exe not found. Put it in PATH or set `$PscpPath` to a full path." }

# Load devices (ALWAYS as an array to avoid StrictMode Count issues)
$Devices = @(
    Get-Content -LiteralPath $DevicesPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") } |
        Sort-Object -Unique
)

if ($Devices.Count -eq 0) { throw "No devices found in $DevicesPath" }

# Prompt once for credentials
$Username   = Read-Host "Enter SSH username"
$SecurePass = Read-Host "Enter SSH password (will be passed to pscp -pw)" -AsSecureString
$Password   = ConvertTo-PlainText $SecurePass

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    throw "Username/password cannot be empty."
}

# Logging
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir   = Join-Path $ScriptDir "out_$RunStamp"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$CsvPath = Join-Path $OutDir "results.csv"
$ErrLog  = Join-Path $OutDir "errors.log"

$results = New-Object System.Collections.Generic.List[object]

Write-Host "Starting copy to $($Devices.Count) devices (sequential)..." -ForegroundColor Cyan
Write-Host "Protocol   : $Protocol"
Write-Host "Local file : $LocalPath"
Write-Host "Remote path: $RemotePath"
Write-Host "Output dir : $OutDir"
Write-Host ""

foreach ($Device in $Devices) {
    $start = Get-Date
    Write-Host "[$($start.ToString('HH:mm:ss'))] $Device ..." -NoNewline

    $status = "UNKNOWN"
    $exit   = $null
    $msg    = ""
    $stderrFinal = ""

    try {
        $t = Test-NetConnection -ComputerName $Device -Port $Port -WarningAction SilentlyContinue
        if (-not $t.TcpTestSucceeded) { throw "Port $Port unreachable" }

        $r = Invoke-PscpWithAutoYes -PscpPath $PscpPath -Device $Device -Port $Port `
                                    -Username $Username -Password $Password `
                                    -LocalPath $LocalPath -RemotePath $RemotePath -Protocol $Protocol

        $exit = $r.ExitCode
        $stderrFinal = $r.StdErr

        if ($r.ExitCode -eq 0) {
            $status = "OK"
            $msg = "Copied"
            Write-Host " OK" -ForegroundColor Green
        } else {
            $status = "FAILED"
            $msg = "pscp exit code $($r.ExitCode)"
            Write-Host " FAILED" -ForegroundColor Red
        }
    }
    catch {
        $status = "FAILED"
        $msg = $_.Exception.Message
        Write-Host " FAILED" -ForegroundColor Red
    }

    $end = Get-Date
    $sec = [math]::Round(($end - $start).TotalSeconds, 2)

    $results.Add([pscustomobject]@{
        device      = $Device
        status      = $status
        exit_code   = $exit
        seconds     = $sec
        message     = $msg
        protocol    = $Protocol
        stderr      = ($stderrFinal -replace "\r","" -replace "\n"," | ").Trim()
        started_at  = $start.ToString("s")
        finished_at = $end.ToString("s")
    }) | Out-Null

    if ($status -ne "OK") {
        $line = "{0} | {1} | exit={2} | {3}" -f $end.ToString("s"), $Device, $exit, ($stderrFinal.Trim())
        Add-Content -Encoding UTF8 -LiteralPath $ErrLog -Value $line
    }
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $CsvPath

$ok   = @($results | Where-Object { $_.status -eq "OK" }).Count
$fail = @($results | Where-Object { $_.status -ne "OK" }).Count

Write-Host ""
Write-Host "DONE. OK=$ok FAILED=$fail" -ForegroundColor Cyan
Write-Host "Results CSV : $CsvPath"
Write-Host "Errors log  : $ErrLog"
