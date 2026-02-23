Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# CONFIG (set once and forget)
# =========================
$DevicesFileName = "devices.txt"          # one IP/host per line
$LocalFileName   = "payload.bin"          # file located in the script folder
$RemotePath      = "/var/tmp/payload.bin" # destination path on the device
$PscpPath        = "pscp.exe"             # or full path to pscp.exe
$Port            = 22
$Protocol        = "scp"                  # "scp" or "sftp"
# =========================

function ConvertTo-PlainText([Security.SecureString]$Secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Invoke-Pscp {
    param(
        [string]$PscpPath,
        [string]$Device,
        [int]$Port,
        [string]$Username,
        [string]$Password,
        [string]$LocalPath,
        [string]$RemotePath,
        [string]$Protocol,
        [string]$HostKeyFingerprint # optional
    )

    $args = New-Object System.Collections.Generic.List[string]
    $args.Add("-batch")
    $args.Add("-no-sanitise-stderr")
    $args.Add("-P");  $args.Add("$Port")
    $args.Add("-l");  $args.Add($Username)
    $args.Add("-pw"); $args.Add($Password)

    if ($Protocol -eq "sftp") { $args.Add("-sftp") } else { $args.Add("-scp") }

    if ($HostKeyFingerprint) {
        $args.Add("-hostkey")
        $args.Add($HostKeyFingerprint)
    }

    $args.Add($LocalPath)
    $args.Add("$Device`:$RemotePath")

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

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Args     = $psi.Arguments
    }
}

function Extract-HostKeyFingerprint {
    param([string]$Text)

    # Example lines from PuTTY/pscp:
    # "The server's ssh-ed25519 key fingerprint is:"
    # "ssh-ed25519 255 SHA256:....."
    #
    # This regex finds the first line starting with "ssh-" that contains "SHA256:"
    $m = [regex]::Match($Text, "(?im)^\s*(ssh-[a-z0-9-]+\s+\d+\s+SHA256:[A-Za-z0-9+/=]+)\s*$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

# Paths relative to script location
$ScriptDir   = Split-Path -Parent $PSCommandPath
$DevicesPath = Join-Path $ScriptDir $DevicesFileName
$LocalPath   = Join-Path $ScriptDir $LocalFileName

if (-not (Test-Path -LiteralPath $DevicesPath)) { throw "Missing devices list file: $DevicesPath" }
if (-not (Test-Path -LiteralPath $LocalPath))   { throw "Missing local file to copy: $LocalPath" }

try { $null = Get-Command $PscpPath -ErrorAction Stop }
catch { throw "pscp.exe not found. Put it in PATH or set `$PscpPath` to a full path." }

$Devices = Get-Content -LiteralPath $DevicesPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

if (-not $Devices -or $Devices.Count -eq 0) { throw "No devices found in $DevicesPath" }

# Prompt ONCE
$Username   = Read-Host "Enter SSH username"
$SecurePass = Read-Host "Enter SSH password (will be passed to pscp -pw)" -AsSecureString
$Password   = ConvertTo-PlainText $SecurePass

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    throw "Username/password cannot be empty."
}

# Output
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
    $hostKeyUsed = $null

    try {
        # Optional quick port check
        $t = Test-NetConnection -ComputerName $Device -Port $Port -WarningAction SilentlyContinue
        if (-not $t.TcpTestSucceeded) { throw "Port $Port unreachable" }

        # Attempt 1 (no hostkey)
        $r1 = Invoke-Pscp -PscpPath $PscpPath -Device $Device -Port $Port -Username $Username -Password $Password `
                          -LocalPath $LocalPath -RemotePath $RemotePath -Protocol $Protocol -HostKeyFingerprint $null

        if ($r1.ExitCode -eq 0) {
            $status = "OK"
            $exit = 0
            $msg = "Copied"
            $stderrFinal = $r1.StdErr
            Write-Host " OK" -ForegroundColor Green
        }
        else {
            # If hostkey not cached, extract fingerprint and retry with -hostkey
            $fp = Extract-HostKeyFingerprint -Text ($r1.StdErr + "`n" + $r1.StdOut)
            if ($fp) {
                $hostKeyUsed = $fp

                $r2 = Invoke-Pscp -PscpPath $PscpPath -Device $Device -Port $Port -Username $Username -Password $Password `
                                  -LocalPath $LocalPath -RemotePath $RemotePath -Protocol $Protocol -HostKeyFingerprint $fp

                $exit = $r2.ExitCode
                $stderrFinal = $r2.StdErr

                if ($r2.ExitCode -eq 0) {
                    $status = "OK"
                    $msg = "Copied (auto hostkey)"
                    Write-Host " OK" -ForegroundColor Green
                } else {
                    $status = "FAILED"
                    $msg = "pscp exit code $($r2.ExitCode)"
                    Write-Host " FAILED" -ForegroundColor Red
                }
            }
            else {
                $status = "FAILED"
                $exit = $r1.ExitCode
                $msg = "pscp exit code $($r1.ExitCode)"
                $stderrFinal = $r1.StdErr
                Write-Host " FAILED" -ForegroundColor Red
            }
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
        device       = $Device
        status       = $status
        exit_code    = $exit
        seconds      = $sec
        message      = $msg
        auto_hostkey = [bool]$hostKeyUsed
        hostkey      = $hostKeyUsed
        stderr       = ($stderrFinal -replace "\r","" -replace "\n"," | ").Trim()
        started_at   = $start.ToString("s")
        finished_at  = $end.ToString("s")
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
