# syntax=docker/dockerfile:1.7

FROM node:24-alpine AS frontend-build
WORKDIR /workspace/frontend

COPY frontend/package.json frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY frontend/ ./
RUN npm run build

FROM eclipse-temurin:21-jdk-alpine AS backend-build
WORKDIR /workspace

COPY gradlew build.gradle.kts settings.gradle.kts versions.properties ./
COPY gradle/ ./gradle/
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew dependencies --configuration runtimeClasspath --no-daemon >/dev/null

COPY src/ ./src/
COPY --from=frontend-build /workspace/frontend/dist/ ./src/main/resources/static/
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew spotlessCheck test bootJar --no-daemon && \
    cp build/libs/project-devops-deploy-*.jar /workspace/application.jar

FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S -g 10001 app && \
    adduser -S -D -H -u 10001 -G app app && \
    mkdir -p /tmp/bulletin-images && \
    chown -R app:app /tmp/bulletin-images

WORKDIR /app
COPY --from=backend-build --chown=app:app /workspace/application.jar ./application.jar

USER 10001:10001
EXPOSE 8080 9090

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0"

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:9090/actuator/health/readiness || exit 1

ENTRYPOINT ["java", "-jar", "/app/application.jar"]
