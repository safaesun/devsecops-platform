#!/bin/bash

set -e

echo "======================================="
echo "Application Build"
echo "======================================="

case "$BUILD_TOOL" in

    composer)

        echo "Installing PHP dependencies..."

        composer install \
            --no-interaction \
            --no-progress \
            --prefer-dist

        ;;

    npm)

        echo "Installing Node dependencies..."

        npm install

        ;;

    pip)

        echo "Installing Python dependencies..."

        pip3 install -r requirements.txt

        ;;

    maven)

        echo "Building Maven project..."

        mvn clean package -DskipTests

        ;;

    gradle)

        echo "Building Gradle project..."

        ./gradlew build -x test

        ;;

    go)

        echo "Downloading Go modules..."

        go mod download

        ;;

    dotnet)

        echo "Restoring .NET packages..."

        dotnet restore

        ;;

    cargo)

        echo "Fetching Rust dependencies..."

        cargo build

        ;;

    *)

        echo "Unsupported build tool : $BUILD_TOOL"

        exit 1

        ;;

esac

echo "======================================="
echo "Build completed successfully"
echo "======================================="
