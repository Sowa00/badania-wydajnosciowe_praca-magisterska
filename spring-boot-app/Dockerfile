FROM ghcr.io/graalvm/native-image-community:25 AS builder
WORKDIR /build

COPY .mvn .mvn
COPY mvnw mvnw.cmd pom.xml ./
COPY src src

RUN ./mvnw clean native:compile -Pnative -DskipTests

FROM ubuntu:noble
WORKDIR /app
COPY --from=builder /build/target/spring-boot-app /app/application

RUN chmod +x /app/application
EXPOSE 8080
ENTRYPOINT ["/app/application"]