#!/bin/bash

if [[ ! $AIO_VERSION =~ "rc" ]]; then
    IFS=- read -r VERSION SUFFIX <<< "$AIO_VERSION"
    IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"

    helm repo add wallarm https://charts.wallarm.com && helm repo update wallarm
    LATEST=$(helm search repo wallarm/wallarm-sidecar --version ^${MAJOR}.${MINOR} -o json | jq -r '.[].version')
    LATEST_PATCH=$(cut -d'.' -f3 <<< $LATEST)
    echo "Detected latest release as $LATEST"

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

echo "CHART_VERSION=$TAG" > version.env
