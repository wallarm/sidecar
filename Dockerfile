ARG ALPINE_VERSION
ARG GOLANG_VERSION
FROM golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} as builder

RUN apk add --no-cache                         \
        bash                                   \
        git                                    \
        upx

WORKDIR /build

COPY cmd/ go.mod go.sum ./
RUN go mod download

ARG TARGETARCH
ARG CGO_ENABLED=0
ARG GOOS=linux
ARG GOARCH=${TARGETARCH}
RUN go test -v .                            && \
    go build -a -ldflags="-s -w"               \
        -o sidecar-controller .             && \
    upx -9 sidecar-controller

ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION
ARG GOLANG_VERSION
ARG CONTAINER_VERSION
ARG COMMIT_SHA

LABEL org.opencontainers.image.authors="Wallarm Support Team <support@wallarm.com>"
LABEL org.opencontainers.image.title="Kubernetes Sidecar controller of Wallarm API Security deployment"
LABEL org.opencontainers.image.documentation="https://docs.wallarm.com/installation/kubernetes/sidecar-proxy/deployment/"
LABEL org.opencontainers.image.source="https://github.com/wallarm/sidecar"
LABEL org.opencontainers.image.vendor="Wallarm"
LABEL org.opencontainers.image.version="${CONTAINER_VERSION}"
LABEL org.opencontainers.image.revision="${COMMIT_SHA}"
LABEL com.wallarm.sidecar-controller.versions.alpine="${ALPINE_VERSION}"
LABEL com.wallarm.sidecar-controller.versions.golang="${GOLANG_VERSION}"

ARG UID=65222
ARG GID=65222
RUN apk update                              && \
    apk upgrade                             && \
    apk add --no-cache                         \
        bash                                && \
    addgroup -g ${GID} controller           && \
    adduser -h /home/controller                \
        -s /bin/bash -u ${UID} -D              \
        -G controller                          \
        controller

COPY --from=builder /build/sidecar-controller /usr/local/bin/sidecar-controller
COPY --chown=${UID}:${GID} files/template.yaml.tpl /etc/controller/template.yaml.tpl

USER ${UID}:${GID}

ENTRYPOINT ["sidecar-controller"]
