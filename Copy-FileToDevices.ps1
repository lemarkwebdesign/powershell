Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# CONFIG (edit if needed)
# =========================
$DevicesFileName = "devices.txt"          # one IP/host per line
$LocalFileName   = "payload.bin"          # file located in the script folder
$RemotePath      = "/var/tmp/payload.bin" # destination path on the device
$PscpPath        = "pscp.exe"             # or full path: C:\Tools\PuTTY\pscp.exe
$Port            = 22                     # SSH port
$ForceSftp       = $false                 # set $true if SCP is flaky; pscp supports -sftp
# =========================

function ConvertTo-PlainText([Security.SecureString]$Secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Invoke-PscpCopy {
    param(
        [string]$PscpPath,
        [string]$Device,
        [int]$Port,
        [string]$Username,
        [string]$Password,
        [string]$LocalPath,
        [string]$RemotePath,
        [string]$HostKey,          # optional
        [bool]$ForceSftp
    )

    # Build argument list
    $args = New-Object System.Collections.Generic.List[string]
    $args.Add("-batch")
    $args.Add("-P");  $args.Add("$Port")
    $args.Add("-l");  $args.Add($Username)
    $args.Add("-pw"); $args.Add($Password)

    if ($ForceSftp) { $args.Add("-sftp") }

    if ($HostKey) {
        $args.Add("-hostkey")
        $args.Add($HostKey)
    }

    $args.Add($LocalPath)
    $args.Add("$Device`:$RemotePath")

    # Run pscp and capture stdout/stderr properly
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PscpPath
    $psi.Arguments = ($args -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        CmdLine  = $psi.Arguments
    }
}

# Resolve script directory + paths
$ScriptDir   = Split-Path -Parent $PSCommandPath
$DevicesPath = Join-Path $ScriptDir $DevicesFileName
$LocalPath   = Join-Path $ScriptDir $LocalFileName

if (-not (Test-Path -LiteralPath $DevicesPath)) { throw "Missing devices list file: $DevicesPath" }
if (-not (Test-Path -LiteralPath $LocalPath))   { throw "Missing local file to copy: $LocalPath" }

try { $null = Get-Command $PscpPath -ErrorAction Stop }
catch { throw "pscp.exe not found. Add PuTTY to PATH or set `$PscpPath` to a full path." }

# Load devices (ignore empty lines and comments)
$Devices = Get-Content -LiteralPath $DevicesPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

if (-not $Devices -or $Devices.Count -eq 0) { throw "No devices found in $DevicesPath" }

# Prompt once for credentials
$Username   = Read-Host "Enter SSH username"
$SecurePass = Read-Host "Enter SSH password (will be passed to pscp -pw)" -AsSecureString
$Password   = ConvertTo-PlainText $SecurePass

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    throw "Username/password cannot be empty."
}

# Logging outputs
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir   = Join-Path $ScriptDir "out_$RunStamp"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$CsvPath = Join-Path $OutDir "results.csv"
$ErrLog  = Join-Path $OutDir "errors.log"

$results = New-Object System.Collections.Generic.List[object]

Write-Host "Starting SCP copy to $($Devices.Count) devices (sequential)..." -ForegroundColor Cyan
Write-Host "Local file : $LocalPath"
Write-Host "Remote path: $RemotePath"
Write-Host "pscp       : $PscpPath (PuTTY 0.76 compatible)"
Write-Host "Output dir : $OutDir"
Write-Host ""

foreach ($Device in $Devices) {
    $start = Get-Date
    Write-Host "[$($start.ToString('HH:mm:ss'))] $Device ..." -NoNewline

    $status   = "UNKNOWN"
    $message  = ""
    $exitCode = $null
    $usedHostKey = $null

    try {
        # Optional: quick port check
        $t = Test-NetConnection -ComputerName $Device -Port $Port -WarningAction SilentlyContinue
        if (-not $t.TcpTestSucceeded) {
            throw "Port $Port unreachable"
        }

        # 1st attempt (no hostkey)
        $r1 = Invoke-PscpCopy -PscpPath $PscpPath -Device $Device -Port $Port -Username $Username -Password $Password `
                              -LocalPath $LocalPath -RemotePath $RemotePath -HostKey $null -ForceSftp:$ForceSftp

        if ($r1.ExitCode -eq 0) {
            $status = "OK"
            $message = "Copied"
            $exitCode = 0
            Write-Host " OK" -ForegroundColor Green
        }
        else {
            # If host key not cached, parse fingerprint and retry with -hostkey
            if ($r1.StdErr -match "The server's .* key fingerprint is:\s*\r?\n\s*(?<fp>ssh-[^\r\n]+)") {
                $usedHostKey = $Matches["fp"].Trim()

                $r2 = Invoke-PscpCopy -PscpPath $PscpPath -Device $Device -Port $Port -Username $Username -Password $Password `
                                      -LocalPath $LocalPath -RemotePath $RemotePath -HostKey $usedHostKey -ForceSftp:$ForceSftp

                $exitCode = $r2.ExitCode

                if ($r2.ExitCode -eq 0) {
                    $status = "OK"
                    $message = "Copied (auto hostkey)"
                    Write-Host " OK" -ForegroundColor Green
                } else {
                    $status = "FAILED"
                    $message = "pscp failed after hostkey retry. ExitCode=$($r2.ExitCode). Err=$($r2.StdErr.Trim())"
                    Write-Host " FAILED" -ForegroundColor Red
                }
            }
            else {
                $status = "FAILED"
                $exitCode = $r1.ExitCode
                $message = "pscp failed. ExitCode=$($r1.ExitCode). Err=$($r1.StdErr.Trim())"
                Write-Host " FAILED" -ForegroundColor Red
            }
        }
    }
    catch {
        $status = "FAILED"
        $message = $_.Exception.Message
        Write-Host " FAILED" -ForegroundColor Red
    }

    $end = Get-Date
    $sec = [math]::Round(($end - $start).TotalSeconds, 2)

    $results.Add([pscustomobject]@{
        device       = $Device
        status       = $status
        seconds      = $sec
        message      = $message
        auto_hostkey = [bool]($usedHostKey)
        hostkey      = $usedHostKey
        started_at   = $start.ToString("s")
        finished_at  = $end.ToString("s")
    }) | Out-Null

    if ($status -ne "OK") {
        "{0} | {1} | {2}" -f $end.ToString("s"), $Device, $message |
            Add-Content -Encoding UTF8 -LiteralPath $ErrLog
    }
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $CsvPath

$ok   = @($results | Where-Object { $_.status -eq "OK" }).Count
$fail = @($results | Where-Object { $_.status -ne "OK" }).Count

Write-Host ""
Write-Host "DONE. OK=$ok FAILED=$fail" -ForegroundColor Cyan
Write-Host "Results CSV : $CsvPath"
Write-Host "Errors log  : $ErrLog"
