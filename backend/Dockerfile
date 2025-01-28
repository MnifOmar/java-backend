FROM openjdk:17-jdk-slim
WORKDIR /app

# Copy the JAR if it exists
COPY target/demo-0.0.1-SNAPSHOT.jar backend.jar

ENTRYPOINT ["java", "-jar", "backend.jar"]
