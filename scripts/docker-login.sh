#!/bin/bash

set -e

echo "========================================"
echo "Docker Hub Authentication"
echo "========================================"

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "DOCKERHUB_USERNAME not found."
    exit 1
fi

if [ -z "$DOCKERHUB_TOKEN" ]; then
    echo "DOCKERHUB_TOKEN not found."
    exit 1
fi

echo "$DOCKERHUB_TOKEN" | docker login \
    --username "$DOCKERHUB_USERNAME" \
    --password-stdin

echo ""
echo "Docker Hub authentication successful."

echo "========================================"
