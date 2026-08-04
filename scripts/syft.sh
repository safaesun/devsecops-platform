#!/bin/bash

set -e

echo "========================================"
echo "Generating SBOM with Syft"
echo "========================================"

if [ -z "$APP_REPOSITORY" ]; then
    APP_REPOSITORY=$(git config --get remote.origin.url)
fi

IMAGE_NAME=$(basename -s .git "$APP_REPOSITORY")

if [ -z "$BUILD_NUMBER" ]; then
    IMAGE_TAG="local"
else
    IMAGE_TAG="$BUILD_NUMBER"
fi

mkdir -p reports/sbom

echo "Image : ${IMAGE_NAME}:${IMAGE_TAG}"

syft ${IMAGE_NAME}:${IMAGE_TAG} \
    -o spdx-json=reports/sbom/sbom-spdx.json

syft ${IMAGE_NAME}:${IMAGE_TAG} \
    -o cyclonedx-json=reports/sbom/sbom-cyclonedx.json

echo ""
echo "SBOM successfully generated."

ls -lh reports/sbom

echo "========================================"
