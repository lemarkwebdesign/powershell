$wsh = New-Object -ComObject WScript.Shell
while($true) {
  $wsh.SendKeys('{SCROLLLOCK}')
  Start-Sleep -Milliseconds 100
  $wsh.SendKeys('{SCROLLLOCK}')
  Start-Sleep -Seconds 60
}
