# Tworzymy obiekt, który pozwoli nam sterować kursorem i klawiaturą
$Shell = New-Object -ComObject WScript.Shell

Write-Host "Mouse Jiggler jest aktywny." -ForegroundColor Green
Write-Host "Naciśnij Ctrl+C, aby zatrzymać."

# Pętla nieskończona
while($true) {
    # Pobieramy aktualną pozycję kursora
    $Pos = [System.Windows.Forms.Cursor]::Position
    
    # Przesuwamy o 1 piksel w prawo
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(($Pos.X + 1), $Pos.Y)
    Start-Sleep -Milliseconds 50
    
    # Przesuwamy z powrotem o 1 piksel w lewo
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($Pos.X, $Pos.Y)
    
    # Czekamy 60 sekund przed kolejnym "szturchnięciem"
    Start-Sleep -Seconds 60
}
