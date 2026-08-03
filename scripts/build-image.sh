#!/bin/bash

set -e

echo "========================================"
echo "Building Docker Image"
echo "========================================"

if [ ! -f Dockerfile ]; then
    echo "Dockerfile not found."
    exit 1
fi

if [ -z "$APP_REPOSITORY" ]; then
    APP_REPOSITORY=$(git config --get remote.origin.url)
fi

IMAGE_NAME=$(basename -s .git "$APP_REPOSITORY")

if [ -z "$BUILD_NUMBER" ]; then
    IMAGE_TAG="local"
else
    IMAGE_TAG="$BUILD_NUMBER"
fi

echo "Repository : $APP_REPOSITORY"
echo "Image      : $IMAGE_NAME"
echo "Tag        : $IMAGE_TAG"

docker build \
    -t ${IMAGE_NAME}:${IMAGE_TAG} \
    .

docker tag \
    ${IMAGE_NAME}:${IMAGE_TAG} \
    ${IMAGE_NAME}:latest

echo ""
echo "Docker image successfully built."

docker images | grep "${IMAGE_NAME}"

echo "========================================"
