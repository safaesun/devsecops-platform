#!/bin/bash

set -e

echo "======================================="
echo "Retrieving secrets from Vault..."
echo "======================================="

export VAULT_ADDR="http://127.0.0.1:8200"

if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: VAULT_TOKEN is not defined."
    exit 1
fi

GITHUB_TOKEN=$(vault kv get -field=token secret/devsecops/github)

SONAR_TOKEN=$(vault kv get -field=token secret/devsecops/sonar)

NEXUS_USERNAME=$(vault kv get -field=username secret/devsecops/nexus)

NEXUS_PASSWORD=$(vault kv get -field=password secret/devsecops/nexus)

COSIGN_PASSWORD=$(vault kv get -field=password secret/devsecops/cosign)

echo "✓ GitHub token loaded"
echo "✓ Sonar token loaded"
echo "✓ Nexus credentials loaded"
echo "✓ Cosign password loaded"

echo "GITHUB_TOKEN=${GITHUB_TOKEN}"
echo "SONAR_TOKEN=${SONAR_TOKEN}"
echo "NEXUS_USERNAME=${NEXUS_USERNAME}"
echo "NEXUS_PASSWORD=${NEXUS_PASSWORD}"
echo "COSIGN_PASSWORD=${COSIGN_PASSWORD}"
