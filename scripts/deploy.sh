#!/bin/bash

set -e

echo "========================================"
echo "Deploying Application to Kubernetes"
echo "========================================"

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

IMAGE_NAME=$(basename -s .git "$APP_REPOSITORY")

IMAGE_TAG="$BUILD_NUMBER"

FULL_IMAGE_NAME="${DOCKERHUB_USERNAME}/${IMAGE_NAME}"

K3S_HOST="${K3S_HOST:-192.168.56.112}"
K3S_USER="${K3S_USER:-saphae}"
K3S_KUBECONFIG="${K3S_KUBECONFIG:-/home/saphae/.kube/config}"

RELEASE_NAME="${RELEASE_NAME:-application}"
NAMESPACE="${K8S_NAMESPACE:-applications}"

CHART_PATH="${K8S_CHART_PATH:-kubernetes/charts/application}"

INGRESS_ENABLED="${INGRESS_ENABLED:-true}"
INGRESS_HOST="${INGRESS_HOST:-app.192.168.56.112.nip.io}"

echo "K3s host       : ${K3S_HOST}"
echo "K3s user       : ${K3S_USER}"
echo "Namespace      : ${NAMESPACE}"
echo "Release        : ${RELEASE_NAME}"
echo "Image          : ${FULL_IMAGE_NAME}:${IMAGE_TAG}"
echo "Chart          : ${CHART_PATH}"

echo ""
echo "Checking SSH connection to K3s..."

ssh \
    -i "$K3S_SSH_KEY" \
    -o StrictHostKeyChecking=no \
    "${K3S_USER}@${K3S_HOST}" \
    "hostname"

echo ""
echo "Deploying Helm release..."

ssh \
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
       --set envFrom[0].secretRef.name=unicomnova-env"

echo ""
echo "Waiting for deployment..."

ssh \
    -i "$K3S_SSH_KEY" \
    -o StrictHostKeyChecking=no \
    "${K3S_USER}@${K3S_HOST}" \
    "export KUBECONFIG='${K3S_KUBECONFIG}' && \
     kubectl rollout status deployment/${RELEASE_NAME} \
       --namespace '${NAMESPACE}' \
       --timeout=300s"

echo ""
echo "Checking deployed resources..."

ssh \
    -i "$K3S_SSH_KEY" \
    -o StrictHostKeyChecking=no \
    "${K3S_USER}@${K3S_HOST}" \
    "export KUBECONFIG='${K3S_KUBECONFIG}' && \
     kubectl get pods,svc,ingressroute \
       --namespace '${NAMESPACE}'"

echo ""
echo "========================================"
echo "Application successfully deployed."
echo "========================================"
