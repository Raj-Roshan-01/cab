FROM node:20-alpine AS web
WORKDIR /web
COPY frontend/package.json .
RUN npm install
COPY frontend/ .
RUN npm run build

FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q dependency:go-offline
COPY src src
COPY --from=web /src/main/resources/static src/main/resources/static
RUN mvn -q -DskipTests package

FROM eclipse-temurin:17-jre
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* && useradd -r app
COPY --from=build /app/target/cab-booking-1.0.0.jar app.jar
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD curl -fs http://localhost:8080/actuator/health || exit 1
# MaxRAMPercentage keeps the JVM inside small (1 GB) free-tier instances
ENTRYPOINT ["java","-XX:MaxRAMPercentage=60","-XX:+UseSerialGC","-jar","app.jar"]
