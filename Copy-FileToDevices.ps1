Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ======= USTAWIENIA =======
$DevicesFileName = "devices.txt"        # IP/host 1 na linię
$LocalFileName   = "payload.bin"        # plik w folderze skryptu
$RemotePath      = "/var/tmp/payload.bin"
$PscpPath        = "pscp.exe"           # albo pełna ścieżka: C:\Tools\PuTTY\pscp.exe
$ConnectTimeout  = 10                   # sekundy
# ==========================

$ScriptDir   = Split-Path -Parent $PSCommandPath
$DevicesPath = Join-Path $ScriptDir $DevicesFileName
$LocalPath   = Join-Path $ScriptDir $LocalFileName

if (-not (Test-Path $DevicesPath)) { throw "Brak pliku z hostami: $DevicesPath" }
if (-not (Test-Path $LocalPath))   { throw "Brak pliku do skopiowania: $LocalPath" }

# Sprawdź czy pscp jest dostępny
try { $null = Get-Command $PscpPath -ErrorAction Stop }
catch { throw "Nie znaleziono pscp.exe. Dodaj PuTTY do PATH albo ustaw pełną ścieżkę w `$PscpPath`." }

# Wczytaj listę urządzeń
$Devices = Get-Content -LiteralPath $DevicesPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

if (-not $Devices -or $Devices.Count -eq 0) { throw "devices.txt jest pusty (albo same komentarze)." }

# Zapytaj raz o dane
$username = Read-Host "Podaj login SSH"
$securePass = Read-Host "Podaj hasło SSH (będzie użyte przez pscp -pw)" -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
)

if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
    throw "Login/hasło nie może być puste."
}

# Przygotuj logi
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir   = Join-Path $ScriptDir "out_$RunStamp"
New-Item -ItemType Directory -Path $OutDir | Out-Null

$CsvPath = Join-Path $OutDir "results.csv"
$ErrLog  = Join-Path $OutDir "errors.log"

$results = New-Object System.Collections.Generic.List[object]

Write-Host "Start: kopiuję '$LocalFileName' do $($Devices.Count) urządzeń (1 po drugim)..." -ForegroundColor Cyan
Write-Host "Remote path: $RemotePath"
Write-Host "Logi: $OutDir"
Write-Host ""

foreach ($d in $Devices) {
    $start = Get-Date
    Write-Host "[$($start.ToString("HH:mm:ss"))] $d ..." -NoNewline

    $status = "UNKNOWN"
    $msg = ""
    $exitCode = $null

    try {
        # (opcjonalnie) szybki test portu 22 – nie przerywa całości jak brak, tylko zapisuje błąd
        $t = Test-NetConnection -ComputerName $d -Port 22 -WarningAction SilentlyContinue
        if (-not $t.TcpTestSucceeded) {
            throw "Port 22 unreachable"
        }

        $args = @(
            "-batch",                 # bez interakcji
            "-pw", $password,         # UWAGA: hasło w argumentach procesu
            "-l", $username,
            "-timeout", "$ConnectTimeout",
            $LocalPath,
            "$d`:$RemotePath"
        )

        $p = Start-Process -FilePath $PscpPath -ArgumentList $args -NoNewWindow -Wait -PassThru
        $exitCode = $p.ExitCode

        if ($exitCode -eq 0) {
            $status = "OK"
            $msg = "Copied"
            Write-Host " OK" -ForegroundColor Green
        } else {
            $status = "FAILED"
            $msg = "pscp exit code $exitCode"
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
        device     = $d
        status     = $status
        exit_code  = $exitCode
        seconds    = $sec
        message    = $msg
        started_at = $start.ToString("s")
        finished_at= $end.ToString("s")
    }) | Out-Null

    if ($status -ne "OK") {
        "{0} | {1} | {2}" -f $end.ToString("s"), $d, $msg | Add-Content -Encoding UTF8 -Path $ErrLog
    }
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvPath

$ok   = ($results | Where-Object status -eq "OK").Count
$fail = ($results | Where-Object status -ne "OK").Count

Write-Host ""
Write-Host "DONE. OK=$ok FAILED=$fail" -ForegroundColor Cyan
Write-Host "CSV: $CsvPath"
Write-Host "ERR: $ErrLog"
