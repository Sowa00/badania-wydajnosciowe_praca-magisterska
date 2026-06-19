# ==============================================================================
# EKSPERYMENT: Cold Start & RAM Footprint (Zimny start i zuzycie zasobow)
# ==============================================================================

$DbService = (docker compose config --services | Select-String -Pattern "db|postgres" | Select-Object -First 1).ToString()
if (-not $DbService) { $DbService = "postgres" }
$DbContainer = "praca_magisterska_db_container"

$Tests = @(
    @{ Name = "Spring-Boot-JVM";    Port = "8080"; Service = "spring-jvm";    Container = "spring-jvm-container" },
    @{ Name = "Spring-Boot-Native"; Port = "8081"; Service = "spring-native"; Container = "spring-native-container" },
    @{ Name = "Quarkus-JVM";        Port = "8082"; Service = "quarkus-jvm";   Container = "quarkus-jvm-container" },
    @{ Name = "Quarkus-Native";     Port = "8083"; Service = "quarkus-native";Container = "quarkus-native-container" }
)

Write-Host "`n[INIT] Rozpoczynam Test Zasobow i Zimnego Startu..." -ForegroundColor Cyan

Write-Host "[DOCKER] Czyszczenie srodowiska..." -ForegroundColor DarkYellow
docker compose down -v 2>$null | Out-Null
docker volume prune -f 2>$null | Out-Null

Write-Host "[DOCKER] Uruchamianie bazy PostgreSQL..." -ForegroundColor DarkGreen
docker compose up -d $DbService 2>$null | Out-Null

# Oczekiwanie na baze
$dbRetry = 0
$dbReady = $false
while ($dbRetry -lt 30) {
    docker exec -i $DbContainer pg_isready -U postgres 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $dbReady = $true; break }
    Start-Sleep -Seconds 1
    $dbRetry++
}
if (-not $dbReady) { Write-Host "[ERROR] Baza nie wstala." -ForegroundColor Red; exit }

Write-Host "`n========================================================================" -ForegroundColor Gray
Write-Host " WYNIKI EKSPERYMENTU ZASOBOWEGO"
Write-Host "========================================================================" -ForegroundColor Gray

foreach ($Test in $Tests) {
    $vName = $Test.Name
    $vPort = $Test.Port
    $vServ = $Test.Service
    $vCont = $Test.Container

    Write-Host "`n[ANALIZA] Badanie obiektu: $vName" -ForegroundColor Cyan
    docker compose up -d $vServ 2>$null | Out-Null

    # Czekamy aż port odpowie
    $isReady = $false
    $retryCount = 0
    while (-not $isReady -and $retryCount -lt 60) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$vPort/api/products/1" -Method Get -ErrorAction Stop
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 404) { $isReady = $true }
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) { $isReady = $true }
            else { Start-Sleep -Milliseconds 500; $retryCount++ }
        }
    }

    # Dajemy aplikacji 5 sekund na ustabilizowanie GC (Garbage Collector)
    Start-Sleep -Seconds 5

    # Pobieranie zużycia pamięci RAM
    $ramStats = docker stats $vCont --no-stream --format "{{.MemUsage}}"
    Write-Host " -> ZUZYCIE RAM (Idle): " -NoNewline; Write-Host "$ramStats" -ForegroundColor Green

    # Pobieranie czasu startu z logów
    Write-Host " -> CZAS STARTU (Log):  " -NoNewline
    $startupLog = docker logs $vCont 2>&1 | Select-String -Pattern "(?i)(started|started in|started application in).*s\b" | Select-Object -Last 1

    if ($startupLog) {
        Write-Host "$startupLog" -ForegroundColor Yellow
    } else {
        Write-Host "[Nie wykryto standardowej linii logu startowego - sprawdz manualnie]" -ForegroundColor Red
    }

    # Ubijanie kontenera
    docker compose stop $vServ 2>$null | Out-Null
    docker compose rm -f $vServ 2>$null | Out-Null
}

Write-Host "`n[DOCKER] Sprzatanie po zakonczonym tescie..." -ForegroundColor DarkYellow
docker compose down -v 2>$null | Out-Null
Write-Host "[STATUS] Eksperyment zakonczony." -ForegroundColor Green