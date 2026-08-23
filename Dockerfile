# Jenkins LTS Dockerfile
# Pinned version for reproducibility and security
# Base image: Jenkins LTS 2.462.1 (Java 17 support)

FROM jenkins/jenkins:2.462.1-jdk17

# Switch to root to install plugins
USER root

# Copy plugins list
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

# Install plugins using Jenkins plugin CLI
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Switch back to jenkins user
USER jenkins

# Labels for metadata
LABEL maintainer="jenkins-infrastructure"
LABEL description="Custom Jenkins LTS image with essential plugins"
