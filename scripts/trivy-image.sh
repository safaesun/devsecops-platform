#!/bin/bash

set -e

echo "========================================"
echo "Running Trivy Docker Image Scan"
echo "========================================"

REPORT_DIR="reports/trivy-image"

mkdir -p "${REPORT_DIR}"

if [ -z "$APP_REPOSITORY" ]; then
    APP_REPOSITORY=$(git config --get remote.origin.url)
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "DOCKERHUB_USERNAME not found."
    exit 1
fi

IMAGE_NAME=$(basename -s .git "$APP_REPOSITORY")

if [ -z "$BUILD_NUMBER" ]; then
    IMAGE_TAG="local"
else
    IMAGE_TAG="$BUILD_NUMBER"
fi

FULL_IMAGE_NAME="${DOCKERHUB_USERNAME}/${IMAGE_NAME}"

IMAGE="${FULL_IMAGE_NAME}:${IMAGE_TAG}"

echo "Scanning image : ${IMAGE}"

trivy image \
    --scanners vuln \
    --format json \
    --output "${REPORT_DIR}/trivy-image-report.json" \
    "${IMAGE}"

trivy image \
    --scanners vuln \
    --format table \
    --output "${REPORT_DIR}/trivy-image-report.txt" \
    "${IMAGE}"

trivy image \
    --scanners vuln \
    --format template \
    --template "@/usr/local/share/trivy/templates/html.tpl" \
    --output "${REPORT_DIR}/trivy-image-report.html" \
    "${IMAGE}"

echo ""
echo "Trivy Image Scan completed."

ls -lh "${REPORT_DIR}"

echo "========================================"
