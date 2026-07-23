#!/bin/bash

set -e

LANGUAGE="unknown"
BUILD_TOOL="unknown"

if [ -f "composer.json" ]; then
    LANGUAGE="php"
    BUILD_TOOL="composer"

elif [ -f "pom.xml" ]; then
    LANGUAGE="java"
    BUILD_TOOL="maven"

elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    LANGUAGE="java"
    BUILD_TOOL="gradle"

elif [ -f "package.json" ]; then
    LANGUAGE="node"
    BUILD_TOOL="npm"

elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    LANGUAGE="python"
    BUILD_TOOL="pip"

elif [ -f "go.mod" ]; then
    LANGUAGE="go"
    BUILD_TOOL="go"

elif ls *.csproj >/dev/null 2>&1; then
    LANGUAGE="dotnet"
    BUILD_TOOL="dotnet"

elif [ -f "Cargo.toml" ]; then
    LANGUAGE="rust"
    BUILD_TOOL="cargo"

elif [ -f "Gemfile" ]; then
    LANGUAGE="ruby"
    BUILD_TOOL="bundler"

elif [ -f "Dockerfile" ]; then
    LANGUAGE="generic"
    BUILD_TOOL="docker"

else
    echo "Unsupported project."
    exit 1
fi

echo "LANGUAGE=${LANGUAGE}"
echo "BUILD_TOOL=${BUILD_TOOL}"
