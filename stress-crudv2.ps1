$JMeterPath = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\jmeter.bat"
$JmxPath    = "C:\Users\Kuba\Desktop\Magisterka\apache-jmeter-5.6.3\bin\View Results Tree CRUD - stress testv2.jmx"
$TargetDir  = "C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska"

$DbService = (docker compose config --services | Select-String -Pattern "db|postgres" | Select-Object -First 1).ToString()
if (-not $DbService) { $DbService = "postgres" }
$DbContainer = "praca_magisterska_db_container"

$Tests = @(
    @{ Name = "Spring-Boot-JVM";    Port = "8080"; Log = "wyniki-stress-spring-jvm.jtl";    Report = "raport-stress-spring-jvm";    Service = "spring-jvm" },
    @{ Name = "Spring-Boot-Native"; Port = "8081"; Log = "wyniki-stress-spring-native.jtl"; Report = "raport-stress-spring-native"; Service = "spring-native" },
    @{ Name = "Quarkus-JVM";        Port = "8082"; Log = "wyniki-stress-quarkus-jvm.jtl";   Report = "raport-stress-quarkus-jvm";   Service = "quarkus-jvm" },
    @{ Name = "Quarkus-Native";     Port = "8083"; Log = "wyniki-stress-quarkus-native.jtl"; Report = "raport-stress-quarkus-native";  Service = "quarkus-native" }
)

Write-Host "[INIT] Starting CRUD STRESS TEST (1000 Threads, 5 min Ramp-Up)" -ForegroundColor Cyan
Remove-Item -Recurse -Force "$TargetDir\raport-stress-*" -ErrorAction SilentlyContinue

foreach ($Test in $Tests) {
    $vName = $Test.Name
    $vPort = $Test.Port
    $vLog  = $Test.Log
    $vRep  = $Test.Report
    $vServ = $Test.Service

    Write-Host "`n========================================================================" -ForegroundColor Gray
    Write-Host "[INFO] Provisioning isolated environment for STRESS target: $vName" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Gray

    Write-Host "[DOCKER] Purging existing containers and volumes..." -ForegroundColor DarkYellow
    docker compose down -v
    docker volume rm badania-wydajnosciowe_praca-magisterska_postgres_data 2>$null
    docker volume prune -f 2>$null

    Write-Host "[DOCKER] Starting database service..." -ForegroundColor DarkGreen
    docker compose up -d $DbService

    # 1. CZEKANIE NA START DB
    Write-Host "[HEALTHCHECK] Awaiting PostgreSQL readiness..." -ForegroundColor Yellow
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
        Write-Host "`n[FATAL] PostgreSQL failed to initialize within 60s timeout. Aborting." -ForegroundColor Red
        exit
    }
    Write-Host "`n[HEALTHCHECK] PostgreSQL ready." -ForegroundColor Green

    # 2. URUCHOMIENIE APLIKACJI
    Write-Host "[DOCKER] Starting target application service: $vServ..." -ForegroundColor DarkGreen
    docker compose up -d $vServ

    # 3. CZEKANIE NA START APLIKACJI
    Write-Host "[HEALTHCHECK] Awaiting API (Port $vPort) and schema readiness..." -ForegroundColor Yellow
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
        Write-Host "`n[FATAL] Application $vName failed to initialize within 60s timeout. Aborting." -ForegroundColor Red
        exit
    }
    Write-Host "`n[HEALTHCHECK] Application $vName ready." -ForegroundColor Green

    # 4. WSTRZYKUJEMY DANE
    Write-Host "[POSTGRES] Seeding initial dataset (5000 records) with category defaults..." -ForegroundColor Cyan

    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "CREATE SEQUENCE IF NOT EXISTS products_SEQUENCE START WITH 1 INCREMENT BY 1;" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "CREATE SEQUENCE IF NOT EXISTS hibernate_sequence START WITH 1 INCREMENT BY 1;" 2>$null

    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "TRUNCATE TABLE products RESTART IDENTITY CASCADE;" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "INSERT INTO products (id, name, category, price) SELECT i, 'Product_Start_' || i, 'General', 150.0 FROM generate_series(1, 5000) AS i;" 2>$null

    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "SELECT setval('products_SEQUENCE', 5000, true);" 2>$null
    docker exec -i $DbContainer psql -U postgres -d praca_magisterska_db -c "SELECT setval('hibernate_sequence', 5000, true);" 2>$null

    $LogFile = "$TargetDir\$vLog"
    $ReportDir = "$TargetDir\$vRep"
    if (Test-Path $LogFile) { Remove-Item $LogFile -Force }

    # 5. JMETER
    Write-Host "[EXEC] Initiating JMeter STRESS test sequence (5 min)..." -ForegroundColor Yellow
    $pPort = "-Jport=" + $vPort
    & $JMeterPath -n -t $JmxPath -l $LogFile $pPort

    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[FATAL] JMeter engine terminated with exit code ($LASTEXITCODE). Aborting." -ForegroundColor Red
        exit
    }

    Write-Host "[EXEC] Aggregating stress metrics and generating HTML reports..." -ForegroundColor Yellow
    if (Test-Path $ReportDir) { Remove-Item -Recurse -Force $ReportDir -ErrorAction SilentlyContinue }
    & $JMeterPath -g $LogFile -o $ReportDir

    Start-Sleep -Seconds 5
}
Write-Host "`n[STATUS] Stress Benchmark sequence completed successfully." -ForegroundColor Green