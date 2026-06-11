# ==============================================================================
# EKSPERYMENT BADAWCZY: Analiza porównawcza wydajności architektur mikroserwisowych
# PROFIL TESTOWY: Mieszany profil obciążeniowy CRUD (Steady-State: 70% GET, 15% POST, 15% DELETE)
# ==============================================================================

$JMeterPath = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\jmeter.bat"
$JmxPath    = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\View Results Tree CRUDv2.jmx"
$TargetDir  = "C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska"

$DbService = (docker compose config --services | Select-String -Pattern "db|postgres" | Select-Object -First 1).ToString()
if (-not $DbService) { $DbService = "postgres" }
$DbContainer = "praca_magisterska_db_container"

$Tests = @(
    @{ Name = "Spring-Boot-JVM";    Port = "8080"; Log = "wyniki-perf-spring-jvm.jtl";    Report = "raport-perf-spring-jvm";    Service = "spring-jvm" },
    @{ Name = "Spring-Boot-Native"; Port = "8081"; Log = "wyniki-perf-spring-native.jtl"; Report = "raport-perf-spring-native"; Service = "spring-native" },
    @{ Name = "Quarkus-JVM";        Port = "8082"; Log = "wyniki-perf-quarkus-jvm.jtl";   Report = "raport-perf-quarkus-jvm";   Service = "quarkus-jvm" },
    @{ Name = "Quarkus-Native";     Port = "8083"; Log = "wyniki-perf-quarkus-native.jtl"; Report = "raport-perf-quarkus-native";  Service = "quarkus-native" }
)

Write-Host "[INIT] INICJALIZACJA PROJEKTU: PERFECT CRUD BENCHMARK (4x 2h)" -ForegroundColor Cyan
Remove-Item -Recurse -Force "$TargetDir\raport-perf-*" -ErrorAction SilentlyContinue

foreach ($Test in $Tests) {
    $vName = $Test.Name
    $vPort = $Test.Port
    $vLog  = $Test.Log
    $vRep  = $Test.Report
    $vServ = $Test.Service

    Write-Host "`n========================================================================" -ForegroundColor Gray
    Write-Host "[INFO] Przygotowanie srodowiska izolowanego dla obiektu: $vName" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Gray

    Write-Host "[DOCKER] Czyszczenie wszystkich kontenerow i wolumenow..." -ForegroundColor DarkYellow
    docker compose down -v
    docker volume rm badania-wydajnosciowe_praca-magisterska_postgres_data 2>$null
    docker volume prune -f 2>$null

    Write-Host "[DOCKER] Uruchamianie izolowanej uslugi bazy danych..." -ForegroundColor DarkGreen
    docker compose up -d $DbService

    # 1. CZEKAMY NA BAZĘ
    Write-Host "[HEALTHCHECK] Oczekiwanie na pelna gotowosc bazy PostgreSQL..." -ForegroundColor Yellow
    $dbRetry = 0
    $dbReady = $false

    while ($dbRetry -lt 60) {
        docker exec -i $DbContainer pg_isready -U postgres 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $dbReady = $true
            break
        }
        Start-Sleep -Seconds 1
        $dbRetry++
        Write-Host -NoNewline "."
    }

    if (-not $dbReady) {
        Write-Host "`n[ERROR] Baza danych nie wystartowala w ciagu 60 sekund! Przerywam eksperyment." -ForegroundColor Red
        exit
    }
    Write-Host "`n[HEALTHCHECK] Baza danych zglosila gotowosc." -ForegroundColor Green

    # 2. URUCHAMIAMY APLIKACJĘ (pozwalamy ORM utworzyć tabelę)
    Write-Host "[DOCKER] Uruchamianie uslugi aplikacji badanej: $vServ..." -ForegroundColor DarkGreen
    docker compose up -d $vServ

    # 3. CZEKAMY NA APLIKACJĘ (upewniamy się, że ORM skończył pracę)
    Write-Host "[HEALTHCHECK] Oczekiwanie na gotowosc API (Port $vPort) oraz schematu bazy..." -ForegroundColor Yellow
    $isReady = $false
    $retryCount = 0
    $maxRetries = 60

    while (-not $isReady -and $retryCount -lt $maxRetries) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$vPort/api/products/1" -Method Get -ErrorAction Stop
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 404) {
                $isReady = $true
            }
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
                $isReady = $true
            } else {
                Start-Sleep -Seconds 1
                $retryCount++
                Write-Host -NoNewline "."
            }
        }
    }

    if (-not $isReady) {
        Write-Host "`n[ERROR] Aplikacja $vName nie wystartowala w ciagu 60 sekund! Przerywam eksperyment." -ForegroundColor Red
        exit
    }
    Write-Host "`n[HEALTHCHECK] Aplikacja $vName zglosila gotowosc." -ForegroundColor Green

    # 4. WSTRZYKUJEMY DANE (teraz mamy pewność, że tabela istnieje)
    Write-Host "[POSTGRES] Wstrzykiwanie 5000 prawdziwych rekordow startowych..." -ForegroundColor Cyan

    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "TRUNCATE TABLE products RESTART IDENTITY CASCADE;" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "INSERT INTO products (id, name, price) SELECT i, 'Product_Start_' || i, 150.0 FROM generate_series(1, 5000) AS i;" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "SELECT setval(pg_get_serial_sequence('products', 'id'), coalesce(max(id), 0) + 1, false) FROM products;" 2>$null

    $LogFile = "$TargetDir\$vLog"
    $ReportDir = "$TargetDir\$vRep"
    if (Test-Path $LogFile) { Remove-Item $LogFile -Force }

    # 5. ODPALAMY JMETER
    Write-Host "[EXEC] Uruchomienie procedury obciazeniowej JMeter..." -ForegroundColor Yellow
    $pPort = "-Jport=" + $vPort
    & $JMeterPath -n -t $JmxPath -l $LogFile $pPort

    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[ERROR] Silnik JMeter zakonczyl prace z kodem bledu ($LASTEXITCODE). Przerywam sekwencje." -ForegroundColor Red
        exit
    }

    Write-Host "[EXEC] Agregacja metryk i generowanie raportow HTML..." -ForegroundColor Yellow
    if (Test-Path $ReportDir) { Remove-Item -Recurse -Force $ReportDir -ErrorAction SilentlyContinue }
    & $JMeterPath -g $LogFile -o $ReportDir

    Start-Sleep -Seconds 5
}
Write-Host "`n[STATUS] Zlota sekwencja eksperymentu sfinalizowana pomyslnie!" -ForegroundColor Green