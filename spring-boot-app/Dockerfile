FROM ghcr.io/graalvm/native-image-community:25 AS builder
WORKDIR /build

COPY .mvn .mvn
COPY mvnw mvnw.cmd pom.xml ./
COPY src src

# POPRAWKA 1: Jawne wywołanie kompilacji natywnej GraalVM
RUN ./mvnw clean native:compile -Pnative -DskipTests

FROM ubuntu:noble
WORKDIR /app
# POPRAWKA 2: Kopiujemy czysty plik wykonywalny Linuxa (bez .jar)
COPY --from=builder /build/target/spring-boot-app /app/application

RUN chmod +x /app/application
EXPOSE 8080
ENTRYPOINT ["/app/application"]