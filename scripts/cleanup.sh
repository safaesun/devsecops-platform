#!/bin/bash

set -e

echo "======================================="
echo "Cleaning Docker resources"
echo "======================================="

echo "Removing local application image..."
docker image rm ${IMAGE_NAME}:${IMAGE_TAG} || true

echo "Cleaning BuildKit cache..."
docker builder prune -f

echo "Docker disk usage after cleanup:"
docker system df

echo "Cleanup completed."
