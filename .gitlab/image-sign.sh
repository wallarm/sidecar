#!/usr/bin/env bash

set -euo pipefail

IMAGE_NAME=${REGISTRY}/${IMAGE}:${TAG}
echo "Will be signing: ${IMAGE_NAME}..."
docker pull -q ${IMAGE_NAME}

IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' $IMAGE_NAME)
IMAGE_URI=$(echo $IMAGE_DIGEST | sed -e 's/\@sha256:/:sha256-/')

# Generate SBOM and provenance files
export SBOM_SPDX="${CI_PROJECT_DIR}/sbom_${TAG}_spdx.json"
export PROVENANCE_PREDICATE="${CI_PROJECT_DIR}/provenance_${TAG}.json"

echo "Generating SBOM..."
syft -o spdx-json ${IMAGE_NAME} > ${SBOM_SPDX}

# Extract SHA256 from digest and set build finished time
export IMAGE_SHA="${IMAGE_DIGEST##*:}"
export BUILD_FINISHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Install Python if not available
apk add --no-cache python3 >/dev/null 2>&1 || apk add --no-cache python3

echo "Generating provenance..."
python3 .gitlab/generate_provenance.py

# Attest SBOM and provenance
echo "Attesting SBOM..."
cosign attest --yes --key env://COSIGN_PRIVATE --type spdxjson --predicate ${SBOM_SPDX} ${IMAGE_DIGEST}

echo "Attesting provenance..."
cosign attest --yes --key env://COSIGN_PRIVATE --type slsaprovenance1 --predicate ${PROVENANCE_PREDICATE} ${IMAGE_DIGEST}

# Sign the image
echo "Signing image..."
cosign sign --recursive --yes --key env://COSIGN_PRIVATE ${IMAGE_DIGEST}
