# ==============================================================================
# EKSPERYMENT BADAWCZY: Analiza porównawcza wydajności architektur mikroserwisowych
# PROFIL TESTOWY: Mieszany profil obciążeniowy CRUD (70% GET, 20% POST, 10% DELETE)
# METODOLOGIA: Soak Test (Długodystansowa weryfikacja stabilności warstwy danych)
# ==============================================================================

$JMeterPath = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\jmeter.bat"
$JmxPath    = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\View Results Tree CRUD.jmx"
$TargetDir  = "C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska"

# Matryca konfiguracji wariantów technologicznych ( Soak Test )
$Tests = @(
    @{ Name = "Spring-Boot-JVM";    Port = "8080"; Log = "wyniki-crud-spring-jvm.jtl";    Report = "raport-crud-spring-jvm" },
    @{ Name = "Spring-Boot-Native"; Port = "8081"; Log = "wyniki-crud-spring-native.jtl"; Report = "raport-crud-spring-native" },
    @{ Name = "Quarkus-JVM";        Port = "8082"; Log = "wyniki-crud-quarkus-jvm.jtl";   Report = "raport-crud-quarkus-jvm" },
    @{ Name = "Quarkus-Native";     Port = "8083"; Log = "wyniki-crud-quarkus-native.jtl"; Report = "raport-crud-quarkus-native" }
)

Write-Host "[INIT] INICJALIZACJA PROJEKTU BADAWCZEGO: REPLICATED CRUD SOAK TEST (4x 2h)" -ForegroundColor Cyan

# Globalne czyszczenie starych katalogów raportów przed rozpoczęciem całego maratonu
Remove-Item -Recurse -Force "$TargetDir\raport-crud-*" -ErrorAction SilentlyContinue

foreach ($Test in $Tests) {
    $vName = $Test.Name
    $vPort = $Test.Port
    $vLog  = $Test.Log
    $vRep  = $Test.Report

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Gray
    Write-Host "[INFO] Przygotowanie srodowiska izolowanego dla obiektu: $vName" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Gray

    # AUTOMATYCZNE CZYSZCZENIE BAZY DANYCH PRZED KAŻDYM TESTEM
    Write-Host "[DOCKER] Zatrzymywanie kontenerow i usuwanie spuchnietego wolumenu bazy..." -ForegroundColor DarkYellow
    docker compose down -v
    docker volume rm badania-wydajnosciowe_praca-magisterska_postgres_data -ErrorAction SilentlyContinue
    docker volume prune -f

    Write-Host "[DOCKER] Uruchamianie czystej bazy danych oraz kontenerow aplikacji..." -ForegroundColor DarkGreen
    docker compose up -d --force-recreate

    $LogFile = "$TargetDir\$vLog"
    $ReportDir = "$TargetDir\$vRep"

    # Czyszczenie starych potoków danych (.jtl)
    if (Test-Path $LogFile) {
        Write-Host "[DEBUG] Wykryto stare logi JMetera. Czyszczenie pliku logu: $vLog" -ForegroundColor DarkYellow
        Remove-Item $LogFile -Force
    }

    # ZABEZPIECZENIE METODOLOGICZNE: Oczekiwanie na pełną gotowość bazy i rozgrzanie kontekstu frameworków
    Write-Host "[INFO] Oczekiwanie 30 sekund na pelna inicjalizacje gniazda TCP i Hibernate dla $vName..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 30

    Write-Host "[EXEC] Uruchomienie procedury obciazeniowej (Soak Test) w silniku JMeter CLI..." -ForegroundColor Yellow

    $pPort = "-Jport=" + $vPort
    & $JMeterPath -n -t $JmxPath -l $LogFile $pPort

    Write-Host "[SUCCESS] Sekwencja pomiarowa ukonczona pomyslnie dla: $vName" -ForegroundColor Green
    Write-Host "[EXEC] Agregacja metryk wydajnosciowych i generowanie struktur HTML..." -ForegroundColor Yellow

    # Czyszczenie katalogu docelowego raportu, jeśli system Windows go zablokował
    if (Test-Path $ReportDir) {
        Remove-Item -Recurse -Force $ReportDir -ErrorAction SilentlyContinue
    }
    & $JMeterPath -g $LogFile -o $ReportDir

    Write-Host "[INFO] Raport wygenerowany pod adresem: $ReportDir" -ForegroundColor White
    Write-Host "[INFO] Zakonczono cykl dla $vName. Przejscie do nastepnego wariantu." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "[STATUS] Pelna sekwencja eksperymentu SOAK TEST sfinalizowana pomyslnie. Dane sa gotowe do analizy." -ForegroundColor Green