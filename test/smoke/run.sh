#!/bin/bash

KIND_LOG_LEVEL="1"

if ! [ -z $DEBUG ]; then
  set -x
  KIND_LOG_LEVEL="6"
fi

export TAG=${TAG:-1.0.0-dev}
export ARCH=${ARCH:-amd64}

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-sidecar-smoke-test}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

export WALLARM_API_HOST="${WALLARM_API_HOST:-api.wallarm.com}"
export WALLARM_API_CA_VERIFY="${WALLARM_API_CA_VERIFY:-true}"
export SMOKE_IMAGE_NAME="${SMOKE_IMAGE_NAME:-dkr.wallarm.com/tests/smoke-tests}"
export SMOKE_IMAGE_TAG="${SMOKE_IMAGE_TAG:-latest}"
export INJECTION_STRATEGY="${INJECTION_STRATEGY:-single}"

K8S_VERSION=${K8S_VERSION:-v1.25.8}

set -o errexit
set -o nounset
set -o pipefail

cleanup() {
  if [[ "${KUBETEST_IN_DOCKER:-}" == "true" ]]; then
    kind "export" logs --name ${KIND_CLUSTER_NAME} "${ARTIFACTS}/logs" || true
  fi
  if [[ "${CI:-}" == "true" ]]; then
    kind delete cluster \
      --verbosity=${KIND_LOG_LEVEL} \
      --name ${KIND_CLUSTER_NAME}
  fi
}

trap cleanup EXIT ERR

[[ "${CI:-}" == "true" ]] && unset KUBERNETES_SERVICE_HOST

declare -a mandatory
mandatory=(
  WALLARM_API_TOKEN
)

missing=false
for var in "${mandatory[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Environment variable $var must be set"
    missing=true
  fi
done

if [ "$missing" = true ]; then
  exit 1
fi

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

if [ "${SKIP_IMAGE_CREATION:-false}" = "false" ]; then
  echo "[test-env] building sidecar image..."
  make -C "${DIR}"/../../ build TAG=${TAG}
fi

# If this variable is set to 'true' we use public images instead local build.
if [ "${SKIP_IMAGE_LOADING:-false}" = "false" ]; then
  echo "[test-env] copying ${REGISTRY}/sidecar-controller:${TAG} image to cluster..."
  kind load docker-image --name="${KIND_CLUSTER_NAME}" "${REGISTRY}/sidecar-controller:${TAG}"
else
  TAG=$(cat "${CURDIR}/TAG")
  export TAG
fi

echo "[test-env] installing Helm chart using TAG=${TAG} ..."

cat << EOF | helm upgrade --install sidecar-controller "${DIR}/../../helm" --wait --values -
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
  injectionStrategy:
    schema: ${INJECTION_STRATEGY}
EOF

kubectl wait --for=condition=Ready pods --all --timeout=120s

echo "[test-env] deploying test workload ..."
kubectl apply -f "${DIR}"/workload.yaml --wait
kubectl wait --for=condition=Ready pods --all --timeout=140s

echo "[test-env] running smoke tests suite ..."
make -C "${DIR}"/../../ smoke-test
