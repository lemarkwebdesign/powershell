Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# CONFIG (edit these lines)
# =========================
$DevicesFileName = "devices.txt"          # one IP/host per line
$LocalFileName   = "payload.bin"          # file located in the script folder
$RemotePath      = "/var/tmp/payload.bin" # destination path on the device
$PscpPath        = "pscp.exe"             # or full path e.g. C:\Tools\PuTTY\pscp.exe

# Optional: if you want to pin host key (recommended), set to the expected fingerprint string.
# Example value format depends on PuTTY version, leave $null to disable.
$HostKey = $null
# =========================

$ScriptDir   = Split-Path -Parent $PSCommandPath
$DevicesPath = Join-Path $ScriptDir $DevicesFileName
$LocalPath   = Join-Path $ScriptDir $LocalFileName

if (-not (Test-Path -LiteralPath $DevicesPath)) { throw "Missing devices list file: $DevicesPath" }
if (-not (Test-Path -LiteralPath $LocalPath))   { throw "Missing local file to copy: $LocalPath" }

try { $null = Get-Command $PscpPath -ErrorAction Stop }
catch { throw "pscp.exe not found. Add PuTTY to PATH or set `$PscpPath` to a full path." }

$Devices = Get-Content -LiteralPath $DevicesPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

if (-not $Devices -or $Devices.Count -eq 0) { throw "No devices found in $DevicesPath" }

$Username   = Read-Host "Enter SSH username"
$SecurePass = Read-Host "Enter SSH password (will be passed to pscp -pw)" -AsSecureString
$Password   = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
)

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    throw "Username/password cannot be empty."
}

$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir   = Join-Path $ScriptDir "out_$RunStamp"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$CsvPath = Join-Path $OutDir "results.csv"
$ErrLog  = Join-Path $OutDir "errors.log"

$results = New-Object System.Collections.Generic.List[object]

Write-Host "Starting SCP copy to $($Devices.Count) devices (sequential)..." -ForegroundColor Cyan
Write-Host "Local file : $LocalPath"
Write-Host "Remote path: $RemotePath"
Write-Host "Output dir : $OutDir"
Write-Host ""

foreach ($Device in $Devices) {
    $start = Get-Date
    Write-Host "[$($start.ToString('HH:mm:ss'))] $Device ..." -NoNewline

    $status   = "UNKNOWN"
    $message  = ""
    $exitCode = $null

    try {
        # Optional: quick port 22 test (if blocked, skip faster)
        $t = Test-NetConnection -ComputerName $Device -Port 22 -WarningAction SilentlyContinue
        if (-not $t.TcpTestSucceeded) {
            throw "Port 22 unreachable"
        }

        $args = @(
            "-batch",
            "-pw", $Password,
            "-l",  $Username
        )

        if ($HostKey) {
            $args += @("-hostkey", $HostKey)
        }

        $args += @(
            $LocalPath,
            "$Device`:$RemotePath"
        )

        $p = Start-Process -FilePath $PscpPath -ArgumentList $args -NoNewWindow -Wait -PassThru
        $exitCode = $p.ExitCode

        if ($exitCode -eq 0) {
            $status  = "OK"
            $message = "Copied"
            Write-Host " OK" -ForegroundColor Green
        } else {
            $status  = "FAILED"
            $message = "pscp exit code $exitCode"
            Write-Host " FAILED" -ForegroundColor Red
        }
    }
    catch {
        $status  = "FAILED"
        $message = $_.Exception.Message
        Write-Host " FAILED" -ForegroundColor Red
    }

    $end = Get-Date
    $sec = [math]::Round(($end - $start).TotalSeconds, 2)

    $results.Add([pscustomobject]@{
        device      = $Device
        status      = $status
        exit_code   = $exitCode
        seconds     = $sec
        message     = $message
        started_at  = $start.ToString("s")
        finished_at = $end.ToString("s")
    }) | Out-Null

    if ($status -ne "OK") {
        "{0} | {1} | {2}" -f $end.ToString("s"), $Device, $message |
            Add-Content -Encoding UTF8 -LiteralPath $ErrLog
    }
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $CsvPath

# Safe counting under StrictMode
$ok   = @($results | Where-Object { $_.status -eq "OK" }).Count
$fail = @($results | Where-Object { $_.status -ne "OK" }).Count

Write-Host ""
Write-Host "DONE. OK=$ok FAILED=$fail" -ForegroundColor Cyan
Write-Host "Results CSV : $CsvPath"
Write-Host "Errors log  : $ErrLog"
