FROM openjdk:17-jdk-slim
WORKDIR /app

# Debugging step: check if the JAR exists
RUN echo "Checking if the JAR exists..." && ls -l backend/target/demo-0.0.1-SNAPSHOT.jar

# Copy the JAR if it exists
COPY backend/target/demo-0.0.1-SNAPSHOT.jar backend.jar

ENTRYPOINT ["java", "-jar", "backend.jar"]
