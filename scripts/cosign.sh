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

if [ -z "$COSIGN_PASSWORD" ]; then
    echo "COSIGN_PASSWORD not found."
    exit 1
fi

if [ -z "$COSIGN_PRIVATE_KEY" ]; then
    echo "COSIGN_PRIVATE_KEY not found."
    exit 1
fi

KEY_FILE=$(mktemp)

trap 'rm -f "$KEY_FILE"' EXIT

echo "$COSIGN_PRIVATE_KEY" > "$KEY_FILE"

chmod 600 "$KEY_FILE"

export COSIGN_PASSWORD

echo "Image : ${IMAGE_NAME}:${IMAGE_TAG}"

cosign sign \
    --yes \
    --key "$KEY_FILE" \
    "${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "Docker image successfully signed."

echo "========================================"
