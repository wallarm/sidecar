# https://makefiletutorial.com/

-include env.ini
.EXPORT_ALL_VARIABLES:

DOCKERFILE       := ./Dockerfile
TAG   	 		 ?= $(shell cat TAG)
IMAGE 	  		 ?= wallarm/sidecar-controller
CONTROLLER_IMAGE = $(IMAGE):$(TAG)

### For embedding into the chart
###
SIDECAR_IMAGE    := wallarm/sidecar:4.6.0-1
TARANTOOL_IMAGE  := wallarm/ingress-tarantool:4.6.2-1
RUBY_IMAGE       := wallarm/ingress-ruby:4.6.2-1
PYTHON_IMAGE     := wallarm/ingress-python:4.6.2-1

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
			--set "config.wallarm.api.host=$(WALLARM_API_HOST)" \
			--set "config.sidecar.image.fullname=$(SIDECAR_IMAGE)" \
			--set "postanalytics.init.image.fullname=$(RUBY_IMAGE)" \
			--set "postanalytics.cron.image.fullname=$(RUBY_IMAGE)" \
			--set "postanalytics.tarantool.image.fullname=$(TARANTOOL_IMAGE)" \
			--set "postanalytics.appstructure.image.fullname=$(PYTHON_IMAGE)" \
			--set "postanalytics.antibot.image.fullname=$(PYTHON_IMAGE)"

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
build:
	@docker build -t $(CONTROLLER_IMAGE) . --force-rm --no-cache --progress=plain

push rmi:
	@docker $@ $(CONTROLLER_IMAGE)

dive:
	@dive $(CONTROLLER_IMAGE)

.PHONY: build push rmi dive

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
	@$(BASH) 'exec kubectl exec -n pytest -it $$(kubectl get pods -n pytest -o name | cut -d '/' -f 2) -- pytest -n 4 helm/test'

.PHONY: integration-*

### Chart testing routines
###

ct-install:
	@$(CURDIR)/helm/test/run_chart_tests.sh

ct-upgrade:
	@CT_MODE="upgrade" $(CURDIR)/helm/test/run_chart_tests.sh

.PHONY: ct-*