FROM openjdk:17-jdk-slim
WORKDIR /app
COPY demo-0.0.1-SNAPSHOT.jar backend.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "backend.jar"]
