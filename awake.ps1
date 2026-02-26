Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Awake {
  [DllImport("kernel32.dll")]
  public static extern uint SetThreadExecutionState(uint esFlags);

  public const uint ES_CONTINUOUS       = 0x80000000;
  public const uint ES_SYSTEM_REQUIRED  = 0x00000001;
  public const uint ES_DISPLAY_REQUIRED = 0x00000002;
}
"@

# Utrzymuj ekran + system aktywne (dopóki działa ta sesja PowerShell)
[Awake]::SetThreadExecutionState([Awake]::ES_CONTINUOUS -bor [Awake]::ES_SYSTEM_REQUIRED -bor [Awake]::ES_DISPLAY_REQUIRED) | Out-Null
Write-Host "Awake ON (screen/system). Stop with CTRL+C."

try { while ($true) { Start-Sleep -Seconds 60 } }
finally {
  # Przywróć normalne zachowanie po zamknięciu
  [Awake]::SetThreadExecutionState([Awake]::ES_CONTINUOUS) | Out-Null
  Write-Host "Awake OFF."
}
