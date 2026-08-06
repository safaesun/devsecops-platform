#!/bin/bash

set -e

echo "========================================"
echo "Generating SBOM with Syft"
echo "========================================"

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

mkdir -p reports/sbom

echo "Image : ${FULL_IMAGE_NAME}:${IMAGE_TAG}"

syft ${FULL_IMAGE_NAME}:${IMAGE_TAG} \
    -o spdx-json=reports/sbom/sbom-spdx.json

syft ${FULL_IMAGE_NAME}:${IMAGE_TAG} \
    -o cyclonedx-json=reports/sbom/sbom-cyclonedx.json

echo ""
echo "SBOM successfully generated."

ls -lh reports/sbom

echo "========================================"
