#!/bin/bash

set -e
set -o pipefail

if [[ ! $AIO_VERSION =~ "rc" ]]; then
    IFS=- read -r VERSION SUFFIX <<< "$AIO_VERSION"
    IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"

    helm repo add wallarm https://charts.wallarm.com && helm repo update wallarm || exit 1
    LATEST=$(helm search repo wallarm/wallarm-sidecar --version ${MAJOR}.${MINOR} -o json | jq -r '.[].version')

    if [ -z "$LATEST" ]; then
        LATEST_PATCH=-1
    else
        LATEST_PATCH=$(cut -d'.' -f3 <<< $LATEST)
    fi
    echo "Detected latest release as ${LATEST:-none}"

    if [ $PATCH -gt $LATEST_PATCH ]; then
        echo "Chart with version $AIO_VERSION doesn't exist yet, re-using AIO_VERSION for the new chart version"
        TAG=$AIO_VERSION
    else
        echo "Chart with version $AIO_VERSION (or later) exists already, will increment chart patch version..."
        TAG=$(echo "${MAJOR}.${MINOR}.$((${LATEST_PATCH} + 1))")
        [ ! -z $SUFFIX ] && TAG="${TAG}-${SUFFIX}"
    fi
else
    echo "Chart version is RC, if chart with the same version exists already it will be overwritten"
    TAG=$AIO_VERSION
fi

echo "Chosen CHART_VERSION $TAG"
echo "CHART_VERSION=$TAG" > version.env
