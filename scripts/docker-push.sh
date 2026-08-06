#!/bin/bash

set -e

echo "========================================"
echo "Pushing Docker Image to Docker Hub"
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

echo "Image : ${FULL_IMAGE_NAME}:${IMAGE_TAG}"

docker push "${FULL_IMAGE_NAME}:${IMAGE_TAG}"

docker push "${FULL_IMAGE_NAME}:latest"

echo ""
echo "Docker image successfully pushed."

echo ""
echo "Image digest:"

docker image inspect "${FULL_IMAGE_NAME}:${IMAGE_TAG}" \
    --format='{{index .RepoDigests 0}}'

echo "========================================"
