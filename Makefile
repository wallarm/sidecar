# https://makefiletutorial.com/

-include env.ini

ifndef CI
	PLATFORMS?=linux/amd64
	BUILDX_ARGS?=--load
else
	PLATFORMS?=linux/amd64,linux/arm64
	BUILDX_ARGS?=--push
endif

.EXPORT_ALL_VARIABLES:

DOCKERFILE       := ./Dockerfile
TAG   	 		 ?= $(shell cat TAG)
IMAGE 	  		 ?= wallarm/sidecar-controller
CONTROLLER_IMAGE = $(IMAGE):$(TAG)
COMMIT_SHA ?= git-$(shell git rev-parse --short HEAD)

### Versions used to build controller image
###
ALPINE_VERSION = 3.19
GOLANG_VERSION = 1.22.2

### Variables used in tests
###
INJECTION_STRATEGY ?= single
REGISTRY ?= wallarm

### Contribution routines
###
EXEC     := docker-compose exec -w /mnt/kubernetes/sidecar kubernetes
KUBECTL  := $(EXEC) kubectl
HELM     := $(EXEC) helm
BASH     := $(EXEC) bash -c
POD_NAME := $(KUBECTL) get pods -o name -l app.kubernetes.io/component=controller | cut -d '/' -f 2
POD_EXEC  = $(KUBECTL) exec -it $(shell $(POD_NAME)) --

init: cluster-start
	@$(HELM) upgrade --install --wait wallarm-sidecar ./helm -f ./helm/values.dev.yaml $(HELMARGS)
	@$(KUBECTL) wait pods -n default -l app.kubernetes.io/component=controller --for condition=Ready --timeout=90s
	@$(BASH) 'exec kubectl exec -it $$(kubectl get pods -o name -l app.kubernetes.io/component=controller | cut -d '/' -f 2) -- apk add git gcc libc-dev'
	@$(BASH) 'exec kubectl exec -it $$(kubectl get pods -o name -l app.kubernetes.io/component=controller | cut -d '/' -f 2) -- go mod download'

bash:
	@$(EXEC) bash

status:
	@echo ===================== CLUSTERS =====================
	@$(KUBECTL) config get-contexts
	@echo ======================= PODS =======================
	@$(KUBECTL) get pods -A

pod-sh:
	@$(POD_EXEC) sh

pod-run:
	@$(POD_EXEC) go run `ls cmd/*.go | grep -v _test.go` \
		--listen :8443 \
		--config /etc/controller/config.yaml \
		--template /data/files/template.yaml.tpl \
		--tls-cert-file /etc/controller/tls/tls.crt \
		--tls-key-file /etc/controller/tls/tls.key \
		--log-level trace \
		--log-format text-color

pod-test:
	@$(POD_EXEC) go test cmd/*_test.go

clean stop:
	@$(BASH) 'docker ps -q | xargs docker stop || true'
	@$(BASH) 'docker ps -a -q | xargs docker rm || true'
	@$(BASH) 'docker volume ls -q | xargs docker volume rm || true'
	@make $(MAKEFLAGS) cluster-down

clean-all:
	@echo REMOVING VOLUME $(shell docker volume rm dind)
	@echo REMOVING VOLUME $(shell docker volume rm registry)

### Helm routines
###
HELMARGS := --set "config.wallarm.api.token=$(WALLARM_API_TOKEN)" \
			--set "config.wallarm.api.host=$(WALLARM_API_HOST)"

helm-template:
	@$(HELM) template wallarm-sidecar ./helm -f ./helm/values.dev.yaml $(HELMARGS) --debug

helm-install:
	@$(HELM) upgrade --install wallarm-sidecar ./helm -f ./helm/values.dev.yaml $(HELMARGS)

helm-diff:
	@$(HELM) diff upgrade --debug --allow-unreleased wallarm-sidecar ./helm -f ./helm/values.dev.yaml $(HELMARGS)

helm-upgrade:
	@$(HELM) upgrade wallarm-sidecar ./helm -f ./helm/values.dev.yaml $(HELMARGS)

helm-delete:
	@$(HELM) uninstall wallarm-sidecar

.PHONY: helm-*

### Development
###
fmt:
	@go fmt ./...

vet:
	@go vet ./...

test: fmt vet
	@go test -v ./...

.PHONY: fmt vet test

### Build
###

setup_buildx:
	docker buildx rm multi-arch || true
	docker buildx create \
		--name multi-arch \
		--platform linux/amd64,linux/arm64 \
		--driver docker-container \
		--use

build: setup_buildx
	docker buildx build \
		--file Dockerfile \
		--platform=$(PLATFORMS) \
		--build-arg ALPINE_VERSION="$(ALPINE_VERSION)" \
		--build-arg GOLANG_VERSION="$(GOLANG_VERSION)" \
		--build-arg CONTAINER_VERSION="$(TAG)" \
		--build-arg COMMIT_SHA="$(COMMIT_SHA)" \
		--force-rm --no-cache --progress=plain \
		--tag $(CONTROLLER_IMAGE) $(BUILDX_ARGS) .

push rmi:
	@docker $@ $(CONTROLLER_IMAGE)

dive:
	@dive $(CONTROLLER_IMAGE)

.PHONY: build push rmi dive

### Test
###

.PHONY: smoke-test
smoke-test:  ## Run smoke tests (expects access to a working Kubernetes cluster).
	@test/smoke/run-smoke-suite.sh

.PHONY: kind-smoke-test
kind-smoke-test:  ## Run smoke tests using kind.
	@test/smoke/run.sh

### Cluster routines
###
TARBALL := .tmp.image.tar

cluster-export-image:
	@echo 'Putting image into kubernetes-accessible registry (local operation)'
	@docker save $(IMAGE) > $(TARBALL)
	@docker cp $(TARBALL) kubernetes:/$(TARBALL)
	@rm $(TARBALL)
	@docker-compose exec kubernetes docker load --input /$(TARBALL)
	@docker-compose exec kubernetes rm /$(TARBALL)
	@docker-compose exec kubernetes docker tag $(IMAGE) registry/$(IMAGE)
	@docker-compose exec kubernetes docker push registry/$(IMAGE)
	@docker-compose exec kubernetes docker rmi $(IMAGE) registry/$(IMAGE)

cluster-start:
	@docker-compose build --progress plain
	@docker-compose up -d
	@sleep 3
	@docker-compose exec kubernetes bash -c \
		'test "$$(kubectl version -o yaml | grep platform | wc -l)" == 2 && echo CLUSTER EXISTS || routines.py create'

cluster-down:
	@docker-compose down

cluster-stop:
	@docker-compose stop

cluster-pause:
	@docker-compose pause

cluster-unpause:
	@docker-compose unpause

.PHONY: cluster-*

### Integration test routines
###

integration-test:
	@$(KUBECTL) wait pods -n pytest --all --for=condition=Ready
	@$(BASH) 'exec kubectl exec -n pytest -it $$(kubectl get pods -n pytest -o name | cut -d '/' -f 2) -- pytest -n 6 -rs helm/test'

.PHONY: integration-*

### Chart testing routines
###

ct-install:
	@$(CURDIR)/helm/test/run_chart_tests.sh

ct-upgrade:
	@CT_MODE="upgrade" $(CURDIR)/helm/test/run_chart_tests.sh

.PHONY: ct-*