KUBE_CLUSTER_NAME=wallarm-sidecar-chart
KUBE_CONTEXT=kind-$(KUBE_CLUSTER_NAME)

all: lint cluster_up chart_install test cluster_down

lint:
	@helm lint ../

cluster_up:
	@kind create cluster --name $(KUBE_CLUSTER_NAME) --config kind/kind.yaml

chart_install:
	@helm install wallarm-sidecar ../. -f ../values.test.yaml --kube-context $(KUBE_CONTEXT) --namespace wallarm-sidecar --create-namespace

test:
	@pytest --kube_context $(KUBE_CONTEXT)

chart_upgrade:
	@helm upgrade wallarm-sidecar ../. -f ../values.test.yaml --kube-context $(KUBE_CONTEXT) --namespace wallarm-sidecar

chart_uninstall:
	@helm uninstall wallarm-sidecar --kube-context $(KUBE_CONTEXT) --namespace wallarm-sidecar

cluster_down:
	@kind delete cluster --name $(KUBE_CLUSTER_NAME)

.PHONY: lint create_cluster install_chart run_test upgrade_chart delete_cluster