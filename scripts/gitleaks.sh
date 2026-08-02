#!/bin/bash

set -e

echo "======================================="
echo "Running Gitleaks Secret Scan"
echo "======================================="

REPORT_DIR="reports/gitleaks"

mkdir -p "${REPORT_DIR}"

gitleaks detect \
    --source . \
    --report-format json \
    --report-path "${REPORT_DIR}/gitleaks-report.json" \
    --verbose || true

echo ""
echo "Gitleaks scan completed."

if [ -f "${REPORT_DIR}/gitleaks-report.json" ]; then
    echo "Report generated:"
    ls -lh "${REPORT_DIR}/gitleaks-report.json"
else
    echo "Report not generated."
fi
