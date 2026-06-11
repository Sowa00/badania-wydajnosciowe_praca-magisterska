# ==============================================================================
# EKSPERYMENT BADAWCZY: Analiza porównawcza wydajności architektur mikroserwisowych
# PROFIL TESTOWY: Mieszany profil obciążeniowy CRUD (70% GET, 20% POST, 10% DELETE)
# METODOLOGIA: Soak Test (Długodystansowa weryfikacja stabilności warstwy danych)
# ==============================================================================

$JMeterPath = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\jmeter.bat"
$JmxPath    = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\View Results Tree CRUD.jmx"
$TargetDir  = "C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska"

# Dynamiczne wykrywanie nazwy usługi bazy danych z docker-compose
$DbService = (docker compose config --services | Select-String -Pattern "db|postgres" | Select-Object -First 1).ToString()
if (-not $DbService) { $DbService = "postgres" }

# Matryca konfiguracji wariantów technologicznych ( Soak Test ) - podane bezpośrednie nazwy usług
$Tests = @(
    @{ Name = "Spring-Boot-JVM";    Port = "8080"; Log = "wyniki-crud-spring-jvm.jtl";    Report = "raport-crud-spring-jvm";    Service = "spring-jvm" },
    @{ Name = "Spring-Boot-Native"; Port = "8081"; Log = "wyniki-crud-spring-native.jtl"; Report = "raport-crud-spring-native"; Service = "spring-native" },
    @{ Name = "Quarkus-JVM";        Port = "8082"; Log = "wyniki-crud-quarkus-jvm.jtl";   Report = "raport-crud-quarkus-jvm";   Service = "quarkus-jvm" },
    @{ Name = "Quarkus-Native";     Port = "8083"; Log = "wyniki-crud-quarkus-native.jtl"; Report = "raport-crud-quarkus-native";  Service = "quarkus-native" }
)

Write-Host "[INIT] INICJALIZACJA PROJEKTU BADAWCZEGO: REPLICATED CRUD SOAK TEST (4x 2h)" -ForegroundColor Cyan

# Globalne czyszczenie starych katalogów raportów przed rozpoczęciem całego maratonu
Remove-Item -Recurse -Force "$TargetDir\raport-crud-*" -ErrorAction SilentlyContinue

foreach ($Test in $Tests) {
    $vName = $Test.Name
    $vPort = $Test.Port
    $vLog  = $Test.Log
    $vRep  = $Test.Report
    $vServ = $Test.Service

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Gray
    Write-Host "[INFO] Przygotowanie srodowiska izolowanego dla obiektu: $vName" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Gray

    # 1. TWARDY RESET ŚRODOWISKA
    Write-Host "[DOCKER] Czyszczenie wszystkich kontenerow i wolumenow..." -ForegroundColor DarkYellow
    docker compose down -v
    docker volume rm badania-wydajnosciowe_praca-magisterska_postgres_data 2>$null
    docker volume prune -f 2>$null

    # 2. PODNOSZENIE TYLKO BAZY DANYCH
    Write-Host "[DOCKER] Uruchamianie izolowanej usługi bazy danych: $DbService..." -ForegroundColor DarkGreen
    docker compose up -d $DbService

    Write-Host "[INFO] Oczekiwanie 15 sekund na inicjalizacje plikow systemowych PostgreSQL..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 15

    # 3. WSTRZYKNIĘCIE SEKWENCJI DO CZYSZCZONEJ BAZY DANYCH
    Write-Host "[POSTGRES] Inicjalizacja struktur sekwencji SQL..." -ForegroundColor Cyan
    $DbContainer = (docker ps --filter "name=db|postgres" --format "{{.Names}}" | Select-Object -First 1)

    # Tworzymy sekwencje, żeby aplikacje wstały bez błędów
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "CREATE SEQUENCE IF NOT EXISTS products_SEQUENCE START WITH 1 INCREMENT BY 1;" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "CREATE SEQUENCE IF NOT EXISTS hibernate_sequence START WITH 1 INCREMENT BY 1;" 2>$null

    # WYŁĄCZONE: Sztuczne przesuwanie licznika na 5000.
    # Baza startuje czysto i przypisuje nowym produktom ID od 1 w górę.
    # docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "SELECT setval('products_SEQUENCE', 5000, false);" 2>$null
    # docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "SELECT setval('hibernate_sequence', 5000, false);" 2>$null

    # 4. PODNOSZENIE DEDYKOWANEJ APLIKACJI
    Write-Host "[DOCKER] Uruchamianie usługi aplikacji badanej: $vServ..." -ForegroundColor DarkGreen
    docker compose up -d $vServ

    $LogFile = "$TargetDir\$vLog"
    $ReportDir = "$TargetDir\$vRep"

    # Czyszczenie starych potoków danych (.jtl)
    if (Test-Path $LogFile) {
        Write-Host "[DEBUG] Wykryto stare logi JMetera. Czyszczenie pliku logu: $vLog" -ForegroundColor DarkYellow
        Remove-Item $LogFile -Force
    }

    # ZABEZPIECZENIE METODOLOGICZNE: Rozgrzanie kontekstu frameworka
    Write-Host "[INFO] Oczekiwanie 25 sekund na pelna gotowosc sieciowa dla $vName..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 25

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
    Write-Host "[INFO] Inicjalizacja 5s przerwy technicznej." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "[STATUS] Pelna sekwencja eksperymentu SOAK TEST sfinalizowana pomyslnie. Dane sa gotowe do analizy." -ForegroundColor Green