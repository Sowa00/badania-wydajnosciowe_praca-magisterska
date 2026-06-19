$env:JAVA_HOME="$env:USERPROFILE\.jdks\graalvm-jdk-25"
$env:Path="$env:JAVA_HOME\bin;$env:Path"

$TotalStart = Get-Date

# =========================================================
# SPRING BOOT
# =========================================================
Write-Host "`n[START] Budowanie obrazow Spring Boot..." -ForegroundColor Cyan
cd C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska\spring-boot-app

$SpringJvmStart = Get-Date
Write-Host "-> Kompilacja i budowa Spring Boot JVM" -ForegroundColor Yellow
./mvnw clean package "-DskipTests"
docker build -f Dockerfile.jvm -t spring-boot-app:0.0.1-SNAPSHOT .
$SpringJvmTime = New-TimeSpan -Start $SpringJvmStart -End (Get-Date)

$SpringNativeStart = Get-Date
Write-Host "`n-> Kompilacja i budowa Spring Boot NATIVE (Buildpacks)" -ForegroundColor Yellow
./mvnw spring-boot:build-image -Pnative "-DskipTests" "-Dspring-boot.build-image.imageName=spring-boot-app-native:latest"
$SpringNativeTime = New-TimeSpan -Start $SpringNativeStart -End (Get-Date)


# =========================================================
# QUARKUS
# =========================================================
Write-Host "`n[START] Budowanie obrazow Quarkus..." -ForegroundColor Cyan
cd C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska\quarkus-app

$QuarkusJvmStart = Get-Date
Write-Host "-> Kompilacja i budowa Quarkus JVM" -ForegroundColor Yellow
./mvnw clean package "-DskipTests"
docker build -f src/main/docker/Dockerfile.jvm -t quarkus-app-jvm:latest .
$QuarkusJvmTime = New-TimeSpan -Start $QuarkusJvmStart -End (Get-Date)

$QuarkusNativeStart = Get-Date
Write-Host "`n-> Kompilacja i budowa Quarkus NATIVE (Container Build)" -ForegroundColor Yellow
./mvnw package -Pnative "-DskipTests" "-Dquarkus.native.container-build=true"
docker build -f src/main/docker/Dockerfile.native -t quarkus-app-native:latest .
$QuarkusNativeTime = New-TimeSpan -Start $QuarkusNativeStart -End (Get-Date)


# =========================================================
# PODSUMOWANIE
# =========================================================
cd C:\Users\Kuba\Desktop\badania-wydajnosciowe_praca-magisterska
$TotalTime = New-TimeSpan -Start $TotalStart -End (Get-Date)

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "                 PODSUMOWANIE CZASU BUDOWANIA                 " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ("Spring Boot JVM:    {0:00} min {1:00} sek" -f [math]::Floor($SpringJvmTime.TotalMinutes), $SpringJvmTime.Seconds)
Write-Host ("Spring Boot Native: {0:00} min {1:00} sek" -f [math]::Floor($SpringNativeTime.TotalMinutes), $SpringNativeTime.Seconds)
Write-Host ("Quarkus JVM:        {0:00} min {1:00} sek" -f [math]::Floor($QuarkusJvmTime.TotalMinutes), $QuarkusJvmTime.Seconds)
Write-Host ("Quarkus Native:     {0:00} min {1:00} sek" -f [math]::Floor($QuarkusNativeTime.TotalMinutes), $QuarkusNativeTime.Seconds)
Write-Host "------------------------------------------------------------"
Write-Host ("CALKOWITY CZAS:     {0:00} godz {1:00} min {2:00} sek" -f [math]::Floor($TotalTime.TotalHours), $TotalTime.Minutes, $TotalTime.Seconds) -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green