FROM golang:1.19.0-alpine3.16 as builder

RUN apk add --no-cache                         \
        bash                                   \
        git                                    \
        upx

WORKDIR /build

COPY cmd/ go.mod go.sum ./
RUN go mod download

ARG CGO_ENABLED=0
ARG GOOS=linux
ARG GOARCH=amd64
RUN go test -v .                            && \
    go build -a -ldflags="-s -w"               \
        -o sidecar-controller .             && \
    upx -9 sidecar-controller

FROM alpine:3.16.2

ARG UID=65222
ARG GID=65222
RUN apk update                              && \
    apk upgrade                             && \
    add --no-cache                             \
        bash                                   \
        curl                                && \
    addgroup -g ${GID} controller           && \
    adduser -h /home/controller                \
        -s /bin/bash -u ${UID} -D              \
        -G controller                          \
        controller

COPY --from=builder /build/sidecar-controller /usr/local/bin/sidecar-controller
COPY --chown=${UID}:${GID} files/template.yaml.tpl /etc/controller/template.yaml.tpl

USER ${UID}:${GID}

ENTRYPOINT ["sidecar-controller"]
