#!/bin/bash

set -e

echo "========================================"
echo "Signing Docker Image"
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

COSIGN_KEY="$HOME/devsecops/certs/cosign/cosign.key"

if [ ! -f "$COSIGN_KEY" ]; then
    echo "Cosign private key not found."
    exit 1
fi

if [ -z "$COSIGN_PASSWORD" ]; then
    echo "COSIGN_PASSWORD not found."
    exit 1
fi

echo "Image : ${IMAGE_NAME}:${IMAGE_TAG}"

export COSIGN_PASSWORD

cosign sign \
    --yes \
    --key "$COSIGN_KEY" \
    "${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "Docker image successfully signed."
echo "========================================"
