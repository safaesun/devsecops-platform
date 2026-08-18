#!/bin/bash

set -e

echo "========================================"
echo "Kyverno Policy Validation (Dry-Run)"
echo "========================================"

# ========================================
# Vérification des variables nécessaires
# ========================================

if [ -z "$APP_REPOSITORY" ]; then
    echo "APP_REPOSITORY not found."
    exit 1
fi

if [ -z "$BUILD_NUMBER" ]; then
    echo "BUILD_NUMBER not found."
    exit 1
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "DOCKERHUB_USERNAME not found."
    exit 1
fi

if [ -z "$K3S_SSH_KEY" ]; then
    echo "K3S_SSH_KEY not found."
    exit 1
fi


# ========================================
# Détermination de l'image Docker
# ========================================

IMAGE_NAME=$(basename -s .git "$APP_REPOSITORY")

IMAGE_TAG="$BUILD_NUMBER"

FULL_IMAGE_NAME="${DOCKERHUB_USERNAME}/${IMAGE_NAME}"


# ========================================
# Configuration K3s (identique à deploy.sh)
# ========================================

K3S_HOST="${K3S_HOST:-192.168.56.112}"

K3S_USER="${K3S_USER:-saphae}"

K3S_KUBECONFIG="${K3S_KUBECONFIG:-/home/saphae/.kube/config}"

RELEASE_NAME="${RELEASE_NAME:-application}"

NAMESPACE="${K8S_NAMESPACE:-applications}"

CHART_PATH="${K8S_CHART_PATH:-/home/saphae/devsecops-platform/kubernetes/charts/application}"

INGRESS_ENABLED="${INGRESS_ENABLED:-true}"

INGRESS_HOST="${INGRESS_HOST:-app.192.168.56.112.nip.io}"


# ========================================
# Préparation du dossier de rapport
# ========================================

REPORT_DIR="reports/kyverno"

mkdir -p "$REPORT_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')


# ========================================
# Affichage de la configuration
# ========================================

echo "K3s host       : ${K3S_HOST}"
echo "Namespace      : ${NAMESPACE}"
echo "Release        : ${RELEASE_NAME}"
echo "Image          : ${FULL_IMAGE_NAME}:${IMAGE_TAG}"
echo "Chart          : ${CHART_PATH}"


# ========================================
# Test SSH
# ========================================

echo ""
echo "Checking SSH connection to K3s..."

ssh \
    -i "$K3S_SSH_KEY" \
    -o StrictHostKeyChecking=no \
    "${K3S_USER}@${K3S_HOST}" \
    "hostname"

echo "SSH connection OK."


# ========================================
# Simulation du déploiement (dry-run server)
# ========================================

echo ""
echo "Simulating Helm deployment against Kyverno policies..."
echo ""

set +e

DRYRUN_OUTPUT=$(ssh \
    -i "$K3S_SSH_KEY" \
    -o StrictHostKeyChecking=no \
    "${K3S_USER}@${K3S_HOST}" \
    "export KUBECONFIG='${K3S_KUBECONFIG}' && \
     helm upgrade --install '${RELEASE_NAME}' '${CHART_PATH}' \
       --namespace '${NAMESPACE}' \
       --create-namespace \
       --set image.repository='${FULL_IMAGE_NAME}' \
       --set image.tag='${IMAGE_TAG}' \
       --set imagePullSecrets[0].name=dockerhub-registry \
       --set ingress.enabled='${INGRESS_ENABLED}' \
       --set ingress.host='${INGRESS_HOST}' \
       --set envFrom[0].secretRef.name=unicomnova-env \
       --dry-run=server" 2>&1)

DRYRUN_STATUS=$?

set -e

echo "$DRYRUN_OUTPUT"


# ========================================
# Récupération du PolicyReport en direct
# ========================================

echo ""
echo "Fetching live PolicyReport for the release..."

LIVE_REPORT=$(ssh \
    -i "$K3S_SSH_KEY" \
    -o StrictHostKeyChecking=no \
    "${K3S_USER}@${K3S_HOST}" \
    "export KUBECONFIG='${K3S_KUBECONFIG}' && \
     kubectl get policyreport -n '${NAMESPACE}' -o json" 2>/dev/null)


# ========================================
# Analyse des résultats
# ========================================

WARNING_COUNT=$(echo "$DRYRUN_OUTPUT" | grep -ci "^Warning:" || true)

if [ $DRYRUN_STATUS -ne 0 ]; then
    OVERALL_STATUS="BLOCKED"
elif [ "$WARNING_COUNT" -gt 0 ]; then
    OVERALL_STATUS="WARNING"
else
    OVERALL_STATUS="PASSED"
fi


# ========================================
# Génération du rapport HTML
# ========================================

STATUS_COLOR="#2ecc71"
if [ "$OVERALL_STATUS" = "WARNING" ]; then
    STATUS_COLOR="#f39c12"
fi
if [ "$OVERALL_STATUS" = "BLOCKED" ]; then
    STATUS_COLOR="#e74c3c"
fi

cat > "${REPORT_DIR}/kyverno-report.html" << HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Kyverno Policy Validation Report</title>
<style>
    body { font-family: Arial, sans-serif; margin: 30px; background: #f5f5f5; }
    h1 { color: #333; }
    .status { display: inline-block; padding: 6px 16px; border-radius: 4px; color: white; font-weight: bold; background: ${STATUS_COLOR}; }
    table { border-collapse: collapse; width: 100%; margin-top: 20px; background: white; }
    th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
    th { background: #2c3e50; color: white; }
    pre { background: #1e1e1e; color: #dcdcdc; padding: 15px; border-radius: 4px; overflow-x: auto; white-space: pre-wrap; }
</style>
</head>
<body>
    <h1>Kyverno Policy Validation Report</h1>
    <p>Statut global : <span class="status">${OVERALL_STATUS}</span></p>

    <table>
        <tr><th>Date</th><td>${TIMESTAMP}</td></tr>
        <tr><th>Build</th><td>${BUILD_NUMBER}</td></tr>
        <tr><th>Application</th><td>${IMAGE_NAME}</td></tr>
        <tr><th>Image</th><td>${FULL_IMAGE_NAME}:${IMAGE_TAG}</td></tr>
        <tr><th>Namespace</th><td>${NAMESPACE}</td></tr>
        <tr><th>Release</th><td>${RELEASE_NAME}</td></tr>
        <tr><th>Code retour dry-run</th><td>${DRYRUN_STATUS}</td></tr>
        <tr><th>Avertissements Kyverno</th><td>${WARNING_COUNT}</td></tr>
    </table>

    <h2>Sortie du dry-run Helm</h2>
    <pre>$(echo "$DRYRUN_OUTPUT" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre>

    <h2>PolicyReport en direct (namespace ${NAMESPACE})</h2>
    <pre>$(echo "$LIVE_REPORT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d, indent=2))" 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' || echo "Non disponible")</pre>
</body>
</html>
HTMLEOF


# ========================================
# Résumé final
# ========================================

echo ""
echo "========================================"
echo "Kyverno analysis completed."
echo "Overall status: ${OVERALL_STATUS}"
echo "Report generated in:"
echo "${REPORT_DIR}"
echo "========================================"


# ========================================
# Décision finale (Audit = non bloquant)
# ========================================

if [ "$OVERALL_STATUS" = "BLOCKED" ]; then
    echo "Kyverno blocked the deployment."
    exit 1
fi

exit 0
