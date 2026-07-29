#!/bin/bash

set -e

echo "======================================="
echo "SonarQube Analysis"
echo "======================================="

if [ -z "$SONAR_TOKEN" ]; then
    echo "ERROR: SONAR_TOKEN is not defined."
    exit 1
fi

if [ -z "$SONAR_HOST_URL" ]; then
    echo "ERROR: SONAR_HOST_URL is not defined."
    exit 1
fi

if [ -z "$APP_REPOSITORY" ]; then
    echo "ERROR: APP_REPOSITORY is not defined."
    exit 1
fi

PROJECT_NAME=$(basename -s .git "$APP_REPOSITORY")

echo "Project Name : ${PROJECT_NAME}"
echo "SonarQube URL : ${SONAR_HOST_URL}"

sonar-scanner \
  -Dsonar.projectKey="${PROJECT_NAME}" \
  -Dsonar.projectName="${PROJECT_NAME}" \
  -Dsonar.projectVersion=1.0 \
  -Dsonar.sources=. \
  -Dsonar.host.url="${SONAR_HOST_URL}" \
  -Dsonar.token="${SONAR_TOKEN}"

echo "======================================="
echo "SonarQube analysis completed."
echo "======================================="
