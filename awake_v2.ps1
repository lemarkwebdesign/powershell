# Definicja flag systemowych
$KeepAliveCode = @"
using System;
using System.Runtime.InteropServices;

public class User32 {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);

    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_DISPLAY_REQUIRED = 0x00000002;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
}
"@

Add-Type -TypeDefinition $KeepAliveCode

Write-Host "Blokada wygaszacza aktywna. Ekran NIE zgaśnie." -ForegroundColor Cyan
Write-Host "Zamknij to okno, aby przywrócić normalne ustawienia."

# Pętla podtrzymująca stan aktywności co 30 sekund
try {
    while($true) {
        # Informujemy system, że ekran i system są wymagane
        [User32]::SetThreadExecutionState([User32]::ES_CONTINUOUS -bor [User32]::ES_DISPLAY_REQUIRED -bor [User32]::ES_SYSTEM_REQUIRED)
        Start-Sleep -Seconds 30
    }
}
finally {
    # Przywrócenie domyślnego stanu po zamknięciu (opcjonalne, system sam to wyczyści po zamknięciu procesu)
    [User32]::SetThreadExecutionState([User32]::ES_CONTINUOUS)
}
