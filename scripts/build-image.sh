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

echo "Repository : $APP_REPOSITORY"
echo "Image      : $FULL_IMAGE_NAME"
echo "Tag        : $IMAGE_TAG"

docker build \
    -t ${FULL_IMAGE_NAME}:${IMAGE_TAG} \
    .

docker tag \
    ${FULL_IMAGE_NAME}:${IMAGE_TAG} \
    ${FULL_IMAGE_NAME}:latest

echo ""
echo "Docker image successfully built."

docker images | grep "${FULL_IMAGE_NAME}"

echo "========================================"
