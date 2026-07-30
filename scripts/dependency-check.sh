#!/bin/bash

set -e

echo "======================================="
echo "OWASP Dependency-Check Analysis"
echo "======================================="

if [ -z "$NVD_API_KEY" ]; then
    echo "ERROR: NVD_API_KEY is not defined."
    exit 1
fi

PROJECT_NAME=$(basename "$PWD")
REPORT_DIR="$PWD/reports/dependency-check"

mkdir -p "$REPORT_DIR"

dependency-check \
    --project "$PROJECT_NAME" \
    --scan . \
    --data /var/jenkins_home/odc-data \
    --format HTML \
    --format JSON \
    --format XML \
    --out "$REPORT_DIR" \
    --nvdApiKey "$NVD_API_KEY" \
    --disableOssIndex \

echo "======================================="
echo "Dependency-Check analysis completed."
echo "Reports generated in:"
echo "$REPORT_DIR"
echo "======================================="
