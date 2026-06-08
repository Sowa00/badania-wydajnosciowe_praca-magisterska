# ==============================================================================
# EKSPERYMENT BADAWCZY: Analiza porównawcza wydajności architektur mikroserwisowych
# PROFIL TESTOWY: Mieszany profil obciążeniowy CRUD (70% GET, 20% POST, 10% DELETE)
# METODOLOGIA: Stress Test (Wyznaczanie punktu krytycznego i granic skalowalnosci)
# ==============================================================================

$JMeterPath = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\jmeter.bat"
$JmxPath    = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\View Results Tree CRUD - stress test.jmx"
$TargetDir  = "C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska"

# Wykrywanie nazwy uslugi bazy danych z docker-compose
$DbService = (docker compose config --services | Select-String -Pattern "db|postgres" | Select-Object -First 1).ToString()
if (-not $DbService) { $DbService = "postgres" } # Fallback

# MATRYCA KONFIGURACJI - Parametr 'Service' musi odpowiadac nazwom z docker-compose.yml!
$Tests = @(
    @{ Name = "Spring-Boot-JVM";    Port = "8080"; Log = "stress-spring-jvm.jtl";    Report = "stress-raport-spring-jvm";    Service = "spring-jvm" },
    @{ Name = "Spring-Boot-Native"; Port = "8081"; Log = "stress-spring-native.jtl"; Report = "stress-raport-spring-native"; Service = "spring-native" },
    @{ Name = "Quarkus-JVM";        Port = "8082"; Log = "stress-quarkus-jvm.jtl";   Report = "stress-raport-quarkus-jvm";   Service = "quarkus-jvm" },
    @{ Name = "Quarkus-Native";     Port = "8083"; Log = "stress-quarkus-native.jtl"; Report = "stress-raport-quarkus-native";  Service = "quarkus-native" }
)

Write-Host "[INIT] INICJALIZACJA PROJEKTU BADAWCZEGO: REPLICATED CRUD STRESS TEST" -ForegroundColor Red

# Globalne czyszczenie starych raportow stress testu
Remove-Item -Recurse -Force "$TargetDir\stress-raport-*" -ErrorAction SilentlyContinue

foreach ($Test in $Tests) {
    $vName = $Test.Name
    $vPort = $Test.Port
    $vLog  = $Test.Log
    $vRep  = $Test.Report
    $vServ = $Test.Service

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Gray
    Write-Host "[STRESS] Przygotowanie czystego srodowiska dla obiektu: $vName" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Gray

    # 1. TWARDY RESET ŚRODOWISKA
    Write-Host "[DOCKER] Czyszczenie wszystkich kontenerow i wolumenow..." -ForegroundColor DarkYellow
    docker compose down -v
    docker volume rm badania-wydajnosciowe_praca-magisterska_postgres_data 2>$null
    docker volume prune -f 2>$null

    # 2. PODNOSZENIE SAMES BAZY DANYCH
    Write-Host "[DOCKER] Uruchamianie izolowanej usługi bazy danych: $DbService..." -ForegroundColor DarkGreen
    docker compose up -d $DbService

    Write-Host "[INFO] Oczekiwanie 15 sekund na inicjalizacje plikow systemowych PostgreSQL..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 15

    # 3. WSTRZYKNIĘCIE SEKWENCJI DO CZYSZCZONEJ BAZY
    Write-Host "[POSTGRES] Inicjalizacja struktur sekwencji SQL..." -ForegroundColor Cyan
    # Sprawdzamy stan kontenera bazy i wstrzykujemy SQL
    $DbContainer = (docker ps --filter "name=db|postgres" --format "{{.Names}}" | Select-Object -First 1)
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "CREATE SEQUENCE IF NOT EXISTS products_SEQUENCE START WITH 1 INCREMENT BY 1;" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "CREATE SEQUENCE IF NOT EXISTS hibernate_sequence START WITH 1 INCREMENT BY 1;" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "SELECT setval('products_SEQUENCE', 5000, false);" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "SELECT setval('hibernate_sequence', 5000, false);" 2>$null

    # 4. PODNOSZENIE USŁUGI APLIKACJI
    Write-Host "[DOCKER] Uruchamianie uslugi aplikacji badanej: $vServ..." -ForegroundColor DarkGreen
    docker compose up -d $vServ

    $LogFile = "$TargetDir\$vLog"
    $ReportDir = "$TargetDir\$vRep"

    if (Test-Path $LogFile) {
        Remove-Item $LogFile -Force
    }

    # Czas na wstanie kontekstu aplikacji na bezpiecznej bazie
    Write-Host "[INFO] Oczekiwanie 25 sekund na pelne rozgrzanie kontekstu i gniazda TCP dla $vName..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 25

    Write-Host "[EXEC] URUCHOMIENIE PROCEDURY przeciazeniowej w silniku JMeter CLI..." -ForegroundColor Red

    $pPort = "-Jport=" + $vPort
    & $JMeterPath -n -t $JmxPath -l $LogFile $pPort

    Write-Host "[SUCCESS] Eksperyment przeciazeniowy zakonczony dla: $vName" -ForegroundColor Green
    Write-Host "[EXEC] Generowanie dedykowanego raportu statystycznego HTML..." -ForegroundColor Yellow

    if (Test-Path $ReportDir) {
        Remove-Item -Recurse -Force $ReportDir -ErrorAction SilentlyContinue
    }
    & $JMeterPath -g $LogFile -o $ReportDir

    Write-Host "[INFO] Raport stress testu dostepny pod: $ReportDir" -ForegroundColor White
    Write-Host "[INFO] Zwalnianie zasobow przed kolejnym wariantem..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "[STATUS] PROCEDURA STRESS TESTOW ZAKONCZONA POMYŚLNIE." -ForegroundColor Green