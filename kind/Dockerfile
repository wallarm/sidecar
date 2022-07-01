FROM docker:20.10.17-dind-alpine3.16 as builder

ARG KUBERNETES_VERSION="1.22.9"

WORKDIR /output
COPY ./docker/manifests ./manifests
COPY ./docker/scripts ./usr/local/bin

RUN apk add --no-cache sed                          && \
    chmod +x ./usr/local/bin/*                      && \
    sed 's/@@@KUBERNETES_VERSION@@@/'${KUBERNETES_VERSION}'/g' -i ./manifests/cluster.yml

FROM docker:20.10.17-dind-alpine3.16

USER root

ARG KIND_VERSION=0.14.0
ARG KUBERNETES_VERSION=1.22.9
ARG HELM_VERSION=3.8.1

RUN apk add --no-cache                                 \
        bash                                           \
        bash-completion                                \
        bind-tools                                     \
        curl                                           \
        git                                            \
        jq                                             \
        nano                                           \
        py3-pip                                        \
        python3                                        \
        sed                                            \
        supervisor                                  && \
    pip install yq --no-cache --no-cache-dir

# Kind
RUN curl https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-linux-amd64 \
        -Lo /usr/local/bin/kind                     && \
    chmod +x /usr/local/bin/kind

# Kubectl
RUN curl https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubectl \
        -Lo /usr/local/bin/kubectl                  && \
    chmod +x /usr/local/bin/kubectl

# Helm
RUN curl -L https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
        | tar -xz linux-amd64/helm                  && \
    chmod +x linux-amd64/helm                       && \
    mv linux-amd64/helm /usr/local/bin/helm         && \
    rm -r linux-amd64                               && \
    helm plugin install                                \
        https://github.com/databus23/helm-diff

COPY --from=builder /output /
