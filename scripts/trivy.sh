#!/bin/bash

set -e

echo "========================================"
echo "Running Trivy Repository Scan"
echo "========================================"

mkdir -p reports/trivy

trivy repo . \
  --scanners vuln \
  --format json \
  --output reports/trivy/trivy-report.json

trivy repo . \
  --scanners vuln \
  --format table \
  --output reports/trivy/trivy-report.txt

trivy repo . \
  --scanners vuln \
  --format template \
  --template "@/usr/local/share/trivy/templates/html.tpl" \
  --output reports/trivy/trivy-report.html

echo "========================================"
echo "Trivy Scan Completed"
echo "========================================"
