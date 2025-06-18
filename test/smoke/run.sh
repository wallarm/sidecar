#!/bin/bash

# import functions
source "${PWD}/test/smoke/functions.sh"

# generate unique group name
export NODE_GROUP_NAME="gitlab-sidecar-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12; echo)"

# check if all mandatory vars was defined
check_mandatory_vars

KIND_LOG_LEVEL="1"

if ! [ -z $DEBUG ]; then
  set -x
  KIND_LOG_LEVEL="6"
fi

export TAG=${TAG:-1.0.0-dev}
export ARCH=${ARCH:-amd64}
export REGISTRY=${REGISTRY:-wallarm}
export HELM_ARGS=${HELM_ARGS:-}

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-sidecar-smoke-test}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

export WALLARM_API_HOST="${WALLARM_API_HOST:-api.wallarm.com}"
export WALLARM_API_CA_VERIFY="${WALLARM_API_CA_VERIFY:-true}"
export SMOKE_IMAGE_NAME="${SMOKE_IMAGE_NAME:-dkr.wallarm.com/tests/smoke-tests}"
export SMOKE_IMAGE_TAG="${SMOKE_IMAGE_TAG:-latest}"
export INJECTION_STRATEGY="${INJECTION_STRATEGY:-single}"

K8S_VERSION=${K8S_VERSION:-v1.29.14} # highest supported version, check actual here https://docs.wallarm.com/installation/kubernetes/sidecar-proxy/deployment/
K8S=${K8S:-v1.29.14}


# This will prevent the secret for index.docker.io from being used if the DOCKERHUB_USER is not set.
DOCKERHUB_REGISTRY_SERVER="https://index.docker.io/v1/"

if [ "${DOCKERHUB_USER:-false}" = "false" ]; then
  DOCKERHUB_REGISTRY_SERVER="fake_docker_registry_server"
fi

DOCKERHUB_SECRET_NAME="dockerhub-secret"
DOCKERHUB_USER="${DOCKERHUB_USER:-fake_user}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-fake_password}"

set -o errexit
set -o nounset
set -o pipefail

trap cleanup EXIT ERR

[[ "${CI:-}" == "true" ]] && unset KUBERNETES_SERVICE_HOST

if ! command -v kind --version &> /dev/null; then
  echo "kind is not installed. Use the package manager or visit the official site https://kind.sigs.k8s.io/"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "${SKIP_CLUSTER_CREATION:-false}" = "false" ]; then
  if kind get clusters | grep -q "${KIND_CLUSTER_NAME}"; then
    echo "[test-env] Kubernetes cluster ${KIND_CLUSTER_NAME} already exists. Using existing cluster ..."
  else
    echo "[test-env] creating Kubernetes cluster with kind"
    kind create cluster \
      --verbosity=${KIND_LOG_LEVEL} \
      --name ${KIND_CLUSTER_NAME} \
      --retain \
      --image "kindest/node:${K8S_VERSION}" \
      --config=<(cat << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30000
        hostPort: 8080
        protocol: TCP
    extraMounts:
      - hostPath: "${CURDIR}/allure_report"
        containerPath: /allure_report
EOF
)

    echo "Kubernetes cluster:"
    kubectl get nodes -o wide
  fi
fi

# create docker-registry secret
echo "[test-env] creating secret docker-registry ..."
if kubectl get secret ${DOCKERHUB_SECRET_NAME} &>/dev/null; then
  echo "[test-env] secret ${DOCKERHUB_SECRET_NAME} already exists, skipping creation."
else
  kubectl create secret docker-registry ${DOCKERHUB_SECRET_NAME} \
    --docker-server=${DOCKERHUB_REGISTRY_SERVER} \
    --docker-username="${DOCKERHUB_USER}" \
    --docker-password="${DOCKERHUB_PASSWORD}" \
    --docker-email=docker-pull@unexists.unexists
fi


if [ "${SKIP_IMAGE_CREATION:-false}" = "false" ]; then
  echo "[test-env] building sidecar image..."
  make -C "${DIR}"/../../ build REGISTRY=${REGISTRY} TAG=${TAG}
fi

# If this variable is set to 'true' we use public images instead local build.
if [ "${SKIP_IMAGE_LOADING:-false}" = "false" ]; then
  echo "[test-env] copying ${REGISTRY}/sidecar-controller:${TAG} image to cluster..."
  kind load docker-image --name="${KIND_CLUSTER_NAME}" "${REGISTRY}/sidecar-controller:${TAG}"
  IMAGE_PULL_POLICY="Never"
else
  TAG=$(cat "${CURDIR}/TAG")
  IMAGE_PULL_POLICY="IfNotPresent"
fi




echo "[test-env] installing cert-manager"
helm repo add jetstack https://charts.jetstack.io/
helm repo update jetstack
if [[ "$K8S" == 1.19* || "$K8S" == v1.19* ]]; then
  CERT_MANAGER_VERSION="v1.9.1"       # for kubernetes 1.19
  docker pull registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.1
  kind load docker-image \
       registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.1 \
       --name "${KIND_CLUSTER_NAME}"

else
  CERT_MANAGER_VERSION="v1.11.1"      # for kubernetes 1.20 and higher
fi
helm upgrade --install cert-manager jetstack/cert-manager --set installCRDs=true -n cert-manager --version "${CERT_MANAGER_VERSION}" --create-namespace --wait

echo "[test-env] installing Helm chart using TAG=${TAG} ..."
cat << EOF | helm upgrade --install sidecar-controller "${DIR}/../../helm" --wait ${HELM_ARGS} --debug --values -
imagePullSecrets:
  - name: ${DOCKERHUB_SECRET_NAME}
config:
  sidecar:
    image:
      pullPolicy: "Always"
    containers:
      proxy:
        readinessProbe:
          initialDelaySeconds: 30
  nginx:
    realIpHeader: "X-Real-IP"
    setRealIpFrom:
      - 0.0.0.0/0
  wallarm:
    fallback: "off"
    api:
      token: ${WALLARM_API_TOKEN}
      host: ${WALLARM_API_HOST}
      nodeGroup: ${NODE_GROUP_NAME}
  injectionStrategy:
    schema: ${INJECTION_STRATEGY}
controller:
  image:
    fullname: ${IMAGE}:${TAG}
    pullPolicy: ${IMAGE_PULL_POLICY}
EOF

echo "[test-env] waiting for postanalytics pod(s) ..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=postanalytics --timeout=120s \
  || get_controller_logs_and_fail

echo "[test-env] waiting for controller pod(s) ..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=controller --timeout=120s \
  || get_controller_logs_and_fail

# Workaround - sometimes sidecar container is not injected right after controller deployment
sleep 10

echo "[test-env] deploying test workload ..."
kubectl apply -f "${DIR}"/workload.yaml --wait
kubectl wait --for=condition=Ready pods --all --timeout=140s || (kubectl describe po -l "app.kubernetes.io/component=workload" && exit 1)

echo "[test-env] running smoke tests suite ..."
make -C "${DIR}"/../../ smoke-test