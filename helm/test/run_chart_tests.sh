#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

cleanup() {
  rm -f ct.sh
  rm -rf ct_previous_revision*
}

KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-kind}
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/kind-config-kind}

if [[ "${CI:-}" == "true" ]]; then
  unset KUBERNETES_SERVICE_HOST
  kind get kubeconfig --name  "${KIND_CLUSTER_NAME}" > "${KUBECONFIG}"
fi

CT_IMAGE="quay.io/helmpack/chart-testing:v3.7.1-amd64"
CT_NAMESPACE="ct"

SECRET_NAME="wallarm-api-token"
SECRET_KEY="token"


# This will prevent the secret for index.docker.io from being used if the DOCKERHUB_USER is not set.
if [ "${DOCKERHUB_USER:-false}" = "false" ]; then
  DOCKERHUB_REGISTRY_SERVER="fake_docker_registry_server"
fi

DOCKERHUB_SECRET_NAME="dockerhub-secret"
DOCKERHUB_USER="${DOCKERHUB_USER:-fake_user}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-fake_password}"

HELM_EXTRA_ARGS="--timeout 180s"
HELM_EXTRA_SET_ARGS="--set config.wallarm.api.token=${WALLARM_API_TOKEN} \
  --set imagePullSecrets[0].name=${DOCKERHUB_SECRET_NAME} \
  ${HELM_ARGS:-}"

# Handle the case when we run chart testing with '--upgrade' option
if [[ "${CT_MODE:-}" == "upgrade" ]]; then
  CT_ARGS="--target-branch main --remote origin --upgrade --skip-missing-values"
else
  CT_ARGS="--charts helm"
fi

if ! kubectl get namespace ${CT_NAMESPACE} &> /dev/null; then
  echo "Creating namespace for chart testing..."
  kubectl create namespace ${CT_NAMESPACE}
fi

if ! kubectl -n ${CT_NAMESPACE} get secret "${SECRET_NAME}" &> /dev/null; then
  echo "Creating secret ${SECRET_NAME}..."
  kubectl -n ${CT_NAMESPACE} create secret generic "${SECRET_NAME}" --from-literal="${SECRET_KEY}"="${WALLARM_API_TOKEN}"
fi

if ! kubectl -n ${CT_NAMESPACE} get secret "${DOCKERHUB_SECRET_NAME}" &> /dev/null; then
  echo "Creating secret ${DOCKERHUB_SECRET_NAME}..."
  kubectl -n ${CT_NAMESPACE} create secret docker-registry "${DOCKERHUB_SECRET_NAME}" \
              --docker-username="${DOCKERHUB_USER}" \
              --docker-password="${DOCKERHUB_PASSWORD}" \
              --docker-email=docker-pull@unexists.unexists
fi

cat <<EOF > ct.sh
#!/bin/bash
set -e
git rev-parse --is-inside-work-tree &> /dev/null || git config --global --add safe.directory /workdir
exec ct install \
 --namespace ${CT_NAMESPACE} \
 --helm-extra-set-args "${HELM_EXTRA_SET_ARGS}" \
 --helm-extra-args "${HELM_EXTRA_ARGS}" \
 ${CT_ARGS:-} \
 --debug
EOF
chmod +x ct.sh

echo "Running helm chart tests..."
trap cleanup EXIT

docker run \
    --rm \
    --interactive \
    --network host \
    --name ct \
    --volume "${KUBECONFIG}:/root/.kube/config" \
    --volume "${CURDIR}:/workdir" \
    --workdir /workdir \
    --entrypoint /workdir/ct.sh \
    ${CT_IMAGE}
