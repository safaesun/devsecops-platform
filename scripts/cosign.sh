#!/bin/bash

set -e

echo "========================================"
echo "Signing Docker Image"
echo "========================================"

if [ -z "$APP_REPOSITORY" ]; then
    APP_REPOSITORY=$(git config --get remote.origin.url)
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "DOCKERHUB_USERNAME not found."
    exit 1
fi

if [ -z "$COSIGN_PASSWORD" ]; then
    echo "COSIGN_PASSWORD not found."
    exit 1
fi

if [ -z "$COSIGN_PRIVATE_KEY" ]; then
    echo "COSIGN_PRIVATE_KEY not found."
    exit 1
fi

IMAGE_NAME=$(basename -s .git "$APP_REPOSITORY")

if [ -z "$BUILD_NUMBER" ]; then
    IMAGE_TAG="local"
else
    IMAGE_TAG="$BUILD_NUMBER"
fi

FULL_IMAGE_NAME="${DOCKERHUB_USERNAME}/${IMAGE_NAME}"

echo "Retrieving image digest..."

IMAGE_DIGEST=$(docker image inspect \
    "${FULL_IMAGE_NAME}:${IMAGE_TAG}" \
    --format='{{index .RepoDigests 0}}')

echo "Image : ${IMAGE_DIGEST}"

KEY_FILE=$(mktemp)

cleanup() {
    rm -f "$KEY_FILE"
}

trap cleanup EXIT

echo "$COSIGN_PRIVATE_KEY" > "$KEY_FILE"

echo "===== BEGIN KEY ====="
cat "$KEY_FILE"
echo "===== END KEY ====="

chmod 600 "$KEY_FILE"

export COSIGN_PASSWORD

cosign sign \
    --key "$KEY_FILE" \
    --yes \
    "${IMAGE_DIGEST}"

echo ""
echo "Docker image successfully signed."

echo "========================================"
