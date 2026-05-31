$JMeterPath = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\jmeter.bat"
$JmxPath = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\View Results Tree.jmx"
$TargetDir = "C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska"

# Tablica z konfiguracjami: Nazwa wariantu, Port, Nazwa pliku wyjsciowego
$Tests = @(
    @{ Name = "Spring-Boot-JVM";    Port = "8080"; Log = "wyniki-long-spring-jvm.jtl";    Report = "raport-long-spring-jvm" },
    @{ Name = "Spring-Boot-Native"; Port = "8081"; Log = "wyniki-long-spring-native.jtl"; Report = "raport-long-spring-native" },
    @{ Name = "Quarkus-JVM";        Port = "8082"; Log = "wyniki-long-quarkus-jvm.jtl";   Report = "raport-long-quarkus-jvm" },
    @{ Name = "Quarkus-Native";     Port = "8083"; Log = "wyniki-long-quarkus-native.jtl"; Report = "raport-long-quarkus-native" }
)

foreach ($Test in $Tests) {
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    Write-Host "[INFO] Inicjalizacja etapu badawczego: $($Test.Name)" -ForegroundColor Cyan
    Write-Host "[INFO] Konfiguracja: Port $($Test.Port), Czas pomiaru: 7200s (2h)" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------" -ForegroundColor Gray

    # Sciezki plikow wyjsciowych
    $LogFile = "$TargetDir\$($Test.Log)"
    $ReportDir = "$TargetDir\$($Test.Report)"

    # Czyszczenie potokow danych
    if (Test-Path $LogFile) {
        Write-Host "[DEBUG] Czyszczenie istniejacego repozytorium: $($Test.Log)" -ForegroundColor DarkYellow
        Remove-Item $LogFile -Force
    }

    Write-Host "[EXEC] Uruchomienie procedury obciazeniowej (Non-GUI Mode)..." -ForegroundColor Yellow

    # TUTAJ POPRAWKA: Prawidlowe przekazanie portu jako czystej liczby
    $CurrentPort = $Test.Port
    & $JMeterPath -n -t $JmxPath -l $LogFile "-Jport=$CurrentPort"

    Write-Host "[SUCCESS] Sekwencja pomiarowa ukonczona dla: $($Test.Name)" -ForegroundColor Green
    Write-Host "[EXEC] Agregacja danych i generowanie raportu..." -ForegroundColor Yellow
    & $JMeterPath -g $LogFile -o $ReportDir

    Write-Host "[INFO] Raport wygenerowany pod adresem: $ReportDir" -ForegroundColor White
    Write-Host "[INFO] Rozpoczeto 10-sekundowy interwal stabilizacyjny." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
}

Write-Host "================================================--" -ForegroundColor Green
Write-Host "[STATUS] Pelna sekwencja eksperymentu sfinalizowana." -ForegroundColor Green
Write-Host "================================================--" -ForegroundColor Green