# Wallarm sidecar controller
Walalrm sidecar controller Helm chart for Kubernetes

## Introduction
Wallarm sidecar controller provides an ability to automatically inject Wallarm sidecar proxy into a Kubernetes Pod.
Sidecar proxy filters and protects inbound traffic to the Pod it is attached to.

Components of Wallarm sidecar controller:
- Sidecar injector - is the mutating admission webhook which injects Wallarm sidecar proxy into Pods and provides configuration based on labels and annotations.
- Post-analytics module - is the local data analytics backend for Wallarm sidecar proxies. Implemented using Tarantool and set of helper containers.

## Prerequisites
- Kubernetes cluster >= 1.19-1.23
- Helm 3 package manager
- Access to Wallarm API endpoint:
    - `https://api.wallarm.com:443` for EU cloud
    - `https://us1.api.wallarm.com:443` for US cloud
- Access to Wallarm helm charts `https://charts.wallarm.com`
- Access to Wallarm repositories on Docker hub `https://hub.docker.com/r/wallarm`
- Wallarm node token created in Wallarm console. Refer [this manual](https://docs.wallarm.com/admin-en/installation-kubernetes-en/#step-1-installing-the-wallarm-ingress-controller)

## Installation
### Add repository
```
helm repo add wallarm https://charts.wallarm.com
helm repo update
```
### Install the chart
EU cloud
```
helm install wallarm-sidecar wallarm/wallarm-sidecar -n wallarm-sidecar --create-namespace --wait --set wallarmApi.token ${API_TOKEN}
```
US cloud
```
helm install wallarm-sidecar wallarm/wallarm-sidecar -n wallarm-sidecar --create-namespace --wait --set wallarmApi.token ${API_TOKEN} --set wallarmApi.host us1.api.wallarm.com
```
Where `${API_TOKEN}` is the Wallarm node API token

## Usage
### Sidecar injection logic
Sidecar injection is controlled on a per-pod basis, by configuring the `wallarm-sidecar` label on a pod.

| Label           | Enabled value | Disabled value |
| --------------- | ------------- | -------------- |
| wallarm-sidecar | enabled       | disabled       |

Sidecar injection has the following logic:
1. If label is set to `enabled`, sidecar is injected
2. If label is set to `disabled`, sidecar is not injected
3. If label is not present in Pod spec, sidecar is not injected

Below is simple example of Kubernetes Deployment which has Wallarm sidecar enabled:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        wallarm-sidecar: enabled
    spec:
      containers:
        - name: application
          image: mockserver/mockserver
          env:
            - name: MOCKSERVER_SERVER_PORT
              value: 80
          ports:
            - name: http
              containerPort: 80
```

### Using deployment schemas
Sidecar controller provides two different deployment schemas for sidecar resources:

  - Single (default)
    - `sidecar-init-iptables` init container with iptables (if interception is enabled)
    - `sidecar-proxy` container with Nginx and helper services
  - Split (optional)
    - `sidecar-init-iptables` init container with iptables (if interception is enabled)
    - `sidecar-init-helper` init container with helper services which aim to register sidecar proxy in Wallarm cloud
    - `sidecar-proxy` container with Nginx only
    - `sidecar-helper` container with helper services

In `single` deployment schema - only one additional container will be added into a Pod, apart of optional init container with iptables.
This container contains Nginx proxy with Wallarm module and helper services. All these processes are run and managed by
supervisord.

In `split` deployment schema - two additional containers will added into a Pod, apart of init containers. In this schema all helper services
are moved out of `sidecar-proxy` container, which contains only Nginx service now. Split deployment schema aims to have more granular control
over resources which consumes by Nginx and helper services.

Deployment schema can be configured in the following ways:
- on per-pod basis by setting Pod's annotation `sidecar.wallarm.io/sidecar-deployment-scheme` to `"single"` or `"split"`
- globally by changing default value in Helm chart `.Values.sidecarDefaults.deployment.scheme` to `"single"` (default) or `"split"`

### Application container port auto-discovery
In order to redirect and proxying incoming traffic properly, sidecar proxy must be aware about TCP port
on which application container accepts incoming requests. Application port auto-discovery has the following logic:
1. If pod has only one container port, this port will be used
2. If pod has multiple container ports:
   - If port with `name: http` found, number of his port will be used
   - If no any port has `name: http`, number of first port will be used
3. If pod has no container ports described, then default setting from `.Values.SidecarDefaults.nginx.proxyPassPort` will be used
4. If annotation `sidecar.wallarm.io/nginx-proxy-pass-port` is set, then it will take precedence over all options above

*NOTE* If for some reason auto-discovery of application port does not work as expected, just use option 3 or 4 above

### Inbound traffic interception
By default Wallarm sidecar intercepts inbound traffic which comes to Pod's IP and application container port, then redirects this
traffic to sidecar proxy container. Sidecar proxy does the job and then proxies traffic to application container.
Inbound traffic interception is implemented using init container with `iptables`. This default behaviour can be configured:
- on per-pod basis by setting Pod's annotation `sidecar.wallarm.io/sidecar-iptables-enable` to `"false"`
- globally by setting helm chart value `.Values.sidecarDefaults.deployment.iptablesEnable` to `"false"`

If inbound traffic interception is disabled, then sidecar proxy container will publish port with name `proxy`. In this case
inbound traffic from Kubernetes service should be sent to `proxy` port, by setting `spec.ports.targetPort: proxy`.
Below is an example with disabled inbound traffic interception on per-pod basis:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        wallarm-sidecar: enabled
      annotations:
        sidecar.wallarm.io/sidecar-iptables-enable: "false"
    spec:
      containers:
        - name: application
          image: mockserver/mockserver
          env:
            - name: MOCKSERVER_SERVER_PORT
              value: 80
          ports:
            - name: http
              containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: myapp-svc
  namespace: default
spec:
  ports:
    - port: 80
      targetPort: proxy
      protocol: TCP
      name: http
  selector:
    app: myapp
```

### Resource management for sidecar containers
Requests and limits for injected containers can be configured either globally using Helm chart values or individually on per-pod basis annotations.
Annotations take precedence over Helm chart values.

| Deployment schema | Container             | Chart value                                       |
|-------------------|-----------------------|---------------------------------------------------|
| Single            | sidecar-proxy         | sidecarDefaults.container.proxy.single.resources  |
| Split, Single     | sidecar-init-iptables | sidecarDefaults.container.init.iptables.resources |
| Split             | sidecar-init-helpers  | sidecarDefaults.container.init.helpers.resources  |
| Split             | sidecar-proxy         | sidecarDefaults.container.proxy.split.resources   |
| Split             | sidecar-helper        | sidecarDefaults.container.helper.resources        |

Example of Helm chart values file for managing resources (requests & limits) globally for both deployment schemes

```yaml
wallarmApi:
  token: ${API_TOKEN}

sidecarDefaults:
  container:
    proxy:
      single:
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
      split:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 300m
            memory: 256Mi
    helper:
      resources:
        requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 300m
            memory: 256Mi
    init:
      helper:
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 300m
            memory: 128Mi
      iptables:
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
          limits:
            cpu: 100m
            memory: 64Mi
```

| Deployment schema | Container             | Annotation                                        |
|-------------------|-----------------------|---------------------------------------------------|
| Single, Split     | sidecar-init-iptables | `sidecar.wallarm.io/init-iptables-{cpu,memory,cpu-limit,memory-limit}` |
| Split             | sidecar-init-helpers  | `sidecar.wallarm.io/init-helpers-{cpu,memory,cpu-limit,memory-limit}` |
| Single, Split     | sidecar-proxy         | `sidecar.wallarm.io/proxy-{cpu,memory,cpu-limit,memory-limit}`  |
| Split             | sidecar-helper        | `sidecar.wallarm.io/helper-{cpu,memory,cpu-limit,memory-limit}` |

Example of managing resources (requests & limits) on per-pod basis using default `Single` deployment schema is shown below
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        wallarm-sidecar: enabled
      annotations:
        sidecar.wallarm.io/proxy-cpu: 200m
        sidecar.wallarm.io/proxy-cpu-limit: 500m
        sidecar.wallarm.io/proxy-memory: 256Mi
        sidecar.wallarm.io/proxy-memory-limit: 512Mi
        sidecar.wallarm.io/init-iptables-cpu: 50m
        sidecar.wallarm.io/init-iptables-cpu-limit: 100m
        sidecar.wallarm.io/init-iptables-memory: 32Mi
        sidecar.wallarm.io/init-iptables-memory-limit: 64Mi
    spec:
      containers:
        - name: application
          image: mockserver/mockserver
          env:
            - name: MOCKSERVER_SERVER_PORT
              value: 80
          ports:
            - name: http
              containerPort: 80
```

### Enable additional Nginx modules
Docker image of sidecar proxy contains the following additional Nginx modules, which are disabled by default:
1. ngx_http_auth_digest_module.so
2. ngx_http_brotli_filter_module.so
3. ngx_http_brotli_static_module.so
4. ngx_http_geoip2_module.so
5. ngx_http_influxdb_module.so
6. ngx_http_modsecurity_module.so
7. ngx_http_opentracing_module.so

Enabling of these additional modules can be done on per-pod basis by setting Pod's annotation `sidecar.wallarm.io/nginx-extra-modules`.
The format of annotation's value is JSON list. Example with additional modules enabled is shown below:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        wallarm-sidecar: enabled
      annotations:
        sidecar.wallarm.io/nginx-extra-modules: "['ngx_http_brotli_filter_module.so','ngx_http_brotli_static_module.so', 'ngx_http_opentracing_module.so']"
    spec:
      containers:
        - name: application
          image: mockserver/mockserver
          env:
            - name: MOCKSERVER_SERVER_PORT
              value: 80
          ports:
            - name: http
              containerPort: 80
```

### Using additional user provided Nginx configuration
Here is an option to include user provided configuration into Nginx config of sidecar proxy.
Additional configuration can be included on 3 different levels of Nginx config on per-pod basis using annotations.
The format of annotation's value is JSON list.

| Nginx config section   | Annotation                                 | Value type |
| ---------------------- | ------------------------------------------ |------------|
| http                   | `sidecar.wallarm.io/nginx-http-include`    | JSON list  |
| server                 | `sidecar.wallarm.io/nginx-server-include`  | JSON list  |
| location               | `sidecar.wallarm.io/nginx-location-include`| JSON list  |

Providing additional configuration files into sidecar proxy container achieves by using extra Volumes and Volumes mounts.

| Item          |  Annotation                                    | Value type  |
|---------------|------------------------------------------------|-------------|
| Volumes       | `sidecar.wallarm.io/proxy-extra-volumes`       | JSON object |
| Volume mounts | `sidecar.wallarm.io/proxy-extra-volume-mounts` | JSON object |

Below is an example with additional user provided configuration file which includes on `server` level into Nginx config.
This example assumes that config map `nginx-http-extra-config` was created in advance and contains valid Nginx configuration directives.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        wallarm-sidecar: enabled
      annotations:
        sidecar.wallarm.io/proxy-extra-volumes: '[{"name": "nginx-http-extra-config", "configMap": {"name": "nginx-include-cm"}}]'
        sidecar.wallarm.io/proxy-extra-volume-mounts: '[{"name": "nginx-http-extra-config", "mountPath": "/nginx_include/http.conf", "subPath": "http.conf"}]'
        sidecar.wallarm.io/nginx-http-include: "['/nginx_include/http.conf']"
            spec:
      containers:
        - name: application
          image: mockserver/mockserver
          env:
            - name: MOCKSERVER_SERVER_PORT
              value: 80
          ports:
            - name: http
              containerPort: 80
```

## List of annotations

All annotations below are specified without prefix `sidecar.wallarm.io/`, to use them properly just add this prefix, e.g. `sidecar.wallarm.io/wallarm-mode`

### Sidecar deployment settings

| Annotation                  | Chart value                                       | Description                                                      |
|-----------------------------|---------------------------------------------------|------------------------------------------------------------------|
| sidecar-deployment-scheme   | .Values.sidecarDefaults.deployment.scheme         | Sidecar deployment scheme: `single` or `split`                   |
| sidecar-iptables-enable     | .Values.sidecarDefaults.deployment.iptablesEnable | Enable or disable `iptables` init container for port redirection: `true` or `false`|

### Wallarm filtering node settings
The list of settings specified below is available at the moment. More settings will be included in the future version.

| Annotation                           | Chart value                                                | Description                                                      |
|--------------------------------------|------------------------------------------------------------|------------------------------------------------------------------|
| wallarm-application                  | NA                                                         | The ID of Wallarm application (optional)                         |
| wallarm-mode                         | .Values.sidecarDefaults.wallarm.mode                       | Wallarm mode: `monitoring, `block` or `off`                      |
| wallarm-mode-allow-override          | .Values.sidecarDefaults.wallarm.modeAllowOverride          | Manages the ability to override the wallarm_mode values via filtering in the Cloud (custom ruleset): `on`, `off` or `strict` |
| wallarm-parse-response               | .Values.sidecarDefaults.wallarm.parseResponse              | Whether to analyze the application responses for attacks: `on` or `off`                   |
| wallarm-parse-websocket              | .Values.sidecarDefaults.wallarm.parseWebsocket             | Whether to analyze WebSocket's messages for attacks: `on` or `off`                        |
| wallarm-unpack-response              | .Values.sidecarDefaults.wallarm.unpackResponse             | Whether to decompress compressed data returned in the application response: `on` or `off` |
| wallarm-upstream-connect-attempts    | .Values.sidecarDefaults.wallarm.upstream.connectAttempts   | Defines the number of immediate reconnects to the Tarantool or Wallarm API                |
| wallarm-upstream-reconnect-interval  | .Values.sidecarDefaults.wallarm.upstream.reconnectInterval | Defines the interval between attempts to reconnect to the Tarantool or Wallarm API        |

### NGINX settings

| Annotation                  | Chart value                                      | Description                                                      |
|-----------------------------|--------------------------------------------------|------------------------------------------------------------------|
| nginx-proxy-pass-port       | .Values.sidecarDefaults.nginx.proxyPassPort      | Port listening by application container. This port is used as application container port, if pod has no exposed ports for application container. Refer `Application container port auto-discovery` section for details |
| nginx-listen-port           | .Values.sidecarDefaults.nginx.listenPort         | Port listening by sidecar proxy container. This port is reserved for using by Wallarm sidecar, can't be the same as nginx.proxyPassPort. |
| nginx-status-port           | .Values.sidecarDefaults.nginx.statusPort         | Port for Wallarm status, Nginx stats and health check endpoints |
| nginx-status-path           | .Values.sidecarDefaults.nginx.statusPath         | Path to Nginx status endpoint |
| nginx-health-path           | .Values.sidecarDefaults.nginx.healthPath         | Path to Nginx health check endpoint |
| nginx-wallarm-status-path   | .Values.sidecarDefaults.nginx.wallarmStatusPath  | Path to Wallarm status endpoint, status provides in JSON format |
| nginx-wallarm-metrics-port  | .Values.sidecarDefaults.nginx.wallarmMetricsPort | Port for Wallarm metrics endpoint |
| nginx-wallarm-metrics-path  | .Values.sidecarDefaults.nginx.wallarmMetricsPath | Port to Wallarm metrics endpoint. Metrics provide in Prometheus format |
| nginx-http-include          | NA                                               | JSON list of full paths to additional config files which should be included into NGINX configuration.Refer "Using additional user provided Nginx configuration" for details |
| nginx-server-include        | NA                                               | Same as above |
| nginx-location-include      | NA                                               | Same as above |
| nginx-extra-modules         | NA                                               | JSON list of NGINX modules to enable. Refer "Enable additional Nginx modules" section for details |

### Sidecar containers settings

| Annotation                  | Chart value                                                               | Description                               |
|-----------------------------|---------------------------------------------------------------------------|-------------------------------------------|
| proxy-extra-volumes         | NA                                                                        | User volumes to be added to the Pod (JSON object). Example: `[{"name":"volumeName","configMap":{“name":"something"}}]`                  |
| proxy-extra-volume-mounts   | NA                                                                        | User volume mounts to be added to the `proxy` container (JSON object). Example:`[{"name":"something","mountPath":"/some/thing"}]` |
| proxy-image                 | .Values.sidecarDefaults.container.proxy.image.image                       | Image for all containers in sidecar scheme     |
| proxy-cpu                   | .Values.sidecarDefaults.container.proxy.*.resources.requests.cpu          | Requested CPU for `proxy` container            |
| proxy-memory                | .Values.sidecarDefaults.container.proxy.*.resources.requests.memory       | Requested memory for `proxy` container         |
| proxy-cpu-limit             | .Values.sidecarDefaults.container.proxy.*.resources.limits.cpu            | CPU limit for `proxy` container                |
| proxy-memory-limit          | .Values.sidecarDefaults.container.proxy.*.resources.limits.memory         | Memory limit for `proxy` container             |
| helper-cpu                  | .Values.sidecarDefaults.container.helper.resources.requests.cpu           | Requested CPU for `helper` container           |
| helper-memory               | .Values.sidecarDefaults.container.helper.resources.requests.memory        | Requested memory for `helper` container        |
| helper-cpu-limit            | .Values.sidecarDefaults.container.helper.resources.limits.cpu             | CPU limit for `helper` container               |
| helper-memory-limit         | .Values.sidecarDefaults.container.helper.resources.limits.memory          | Memory limit for `helper` container            |
| init-iptables-cpu           | .Values.sidecarDefaults.container.init.iptables.resources.requests.cpu    | Requested CPU for `init-iptables` container    |
| init-iptables-memory        | .Values.sidecarDefaults.container.init.iptables.resources.requests.memory | Requested memory for `init-iptables` container |
| init-iptables-cpu-limit     | .Values.sidecarDefaults.container.init.iptables.resources.limits.cpu      | CPU limit for `init-iptables` container        |
| init-iptables-memory-limit  | .Values.sidecarDefaults.container.init.iptables.resources.limits.memory   | Memory limit for `init-iptables` container     |
| init-helper-cpu             | .Values.sidecarDefaults.container.init.helper.resources.requests.cpu      | Requested CPU for `init-helper` container      |
| init-helper-memory          | .Values.sidecarDefaults.container.init.helper.resources.requests.memory   | Requested memory for `init-helper` container   |
| init-helper-cpu-limit       | .Values.sidecarDefaults.container.init.helper.resources.limits.cpu        | CPU limit for `init-helper` container          |
| init-helper-memory-limit    | .Values.sidecarDefaults.container.init.helper.resources.limits.memory     | Memory limit for `init-helper` container       |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| admissionWebhook | object | *See below for details* | Configuration of sidecar injector module |
| admissionWebhook.affinity | object | `{}` | Node affinity for webhook pod and helper Jobs |
| admissionWebhook.annotations | object | `{}` | Annotations to be added to admission webhook resources |
| admissionWebhook.failurePolicy | string | `"Fail"` | Admission webhook failure policy |
| admissionWebhook.healthPath | string | `"/healthz"` | Path of webhook health check endpoint |
| admissionWebhook.image.image | string | `"dmitriev/sidecar-injector"` | Image repository |
| admissionWebhook.image.pullPolicy | string | `"IfNotPresent"` | Image pullPolicy |
| admissionWebhook.image.registry | string | `"quay.io"` | Image registry |
| admissionWebhook.image.tag | string | `"0.1.3"` | Image tag |
| admissionWebhook.injectPath | string | `"/inject"` | Path to webhook injection endpoint |
| admissionWebhook.labels | object | `{}` | Labels to be added to admission webhook resources |
| admissionWebhook.nodeSelector | object | `{}` | Node selector for webhook pod and helper Jobs |
| admissionWebhook.patch | object | *See below for details* | Configuration for certgen and patch helper Jobs |
| admissionWebhook.patch.image.image | string | `"ingress-nginx/kube-webhook-certgen"` | Image repository |
| admissionWebhook.patch.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| admissionWebhook.patch.image.registry | string | `"k8s.gcr.io"` | Image registry |
| admissionWebhook.patch.image.tag | string | `"v1.1.1"` | Image tag |
| admissionWebhook.patch.resources | object | `{}` | Resources for certgen and patch helper Jobs |
| admissionWebhook.port | int | `8443` | Admission webhook listening port |
| admissionWebhook.replicaCount | int | `1` | Replica count of admission webhook deployment |
| admissionWebhook.resources | object | `{}` | Resources for admission webhook Pod |
| admissionWebhook.service.annotations | object | `{}` | Annotations to be added to admission webhook service |
| admissionWebhook.tolerations | list | `[]` | Node tolerations for webhook pod and helper Jobs |
| fullnameOverride | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
| postanalytics | object | *See below for details* | Configuration for post-analytics module |
| postanalytics.affinity | object | `{}` | Node affinity for post-analytics pod |
| postanalytics.annotations | object | `{}` | Annotations to be added to admission webhook resources |
| postanalytics.helpers.addnode.resources | object | `{}` | Resources for `addnode` init container |
| postanalytics.helpers.appstructure.resources | object | `{}` | Resources for `appstructure` helper container |
| postanalytics.helpers.cron.jobs | object | *See below for details* | Cron jobs configuration |
| postanalytics.helpers.cron.jobs.bruteDetect | object | *See below for details* | Parameters for `brute detect` job |
| postanalytics.helpers.cron.jobs.bruteDetect.schedule | string | `"* * * * *"` | Job schedule in cron format |
| postanalytics.helpers.cron.jobs.bruteDetect.timeout | string | `"6m"` | Job timeout |
| postanalytics.helpers.cron.jobs.exportAttacks | object | *See below for details* | Parameters for `export attacks` job |
| postanalytics.helpers.cron.jobs.exportAttacks.schedule | string | `"* * * * *"` | Job schedule in cron format |
| postanalytics.helpers.cron.jobs.exportAttacks.timeout | string | `"3h"` | Job timeout |
| postanalytics.helpers.cron.jobs.exportCounters | object | *See below for details* | Parameters for `export counters` job |
| postanalytics.helpers.cron.jobs.exportCounters.schedule | string | `"* * * * *"` | Job schedule in cron format |
| postanalytics.helpers.cron.jobs.exportCounters.timeout | string | `"11m"` | Job timeout |
| postanalytics.helpers.cron.jobs.exportEnvironment | object | *See below for details* | Parameters for `export environment` job |
| postanalytics.helpers.cron.jobs.exportEnvironment.schedule | string | `"0 */1 * * *"` | Job schedule in cron format |
| postanalytics.helpers.cron.jobs.exportEnvironment.timeout | string | `"10m"` | Job timeout |
| postanalytics.helpers.cron.jobs.syncMarkers | object | *See below for details* | Parameters for `sync markers` job |
| postanalytics.helpers.cron.jobs.syncMarkers.schedule | string | `"* * * * *"` | Job schedule in cron format |
| postanalytics.helpers.cron.jobs.syncMarkers.timeout | string | `"1h"` | Job timeout |
| postanalytics.helpers.cron.resources | object | `{}` | Resources for `cron` helper container |
| postanalytics.helpers.exportenv.resources | object | `{}` | Resources for `exportenv` init container |
| postanalytics.helpers.heartbeat.resources | object | `{}` | Resources for `heartbeat` helper container |
| postanalytics.labels | object | `{}` | Labels to be added to admission webhook resources |
| postanalytics.nodeSelector | object | `{}` | Node selector for post-analytics pod |
| postanalytics.tarantool.arena | string | `"0.5"` | The allocated memory size in GB for Tarantool in-memory storage. Detailed recommendations are provided [here](https://docs.wallarm.com/admin-en/configuration-guides/allocate-resources-for-waf-node/) |
| postanalytics.tarantool.image.image | string | `"wallarm/ingress-tarantool"` | Image repository |
| postanalytics.tarantool.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| postanalytics.tarantool.image.registry | string | `"docker.io"` | Image registry |
| postanalytics.tarantool.image.tag | string | `"4.0.3-1"` | Image tag |
| postanalytics.tarantool.livenessProbe | object | *See below for details* | Configuration of TCP liveness probe for `tarantool` container |
| postanalytics.tarantool.resources | object | `{}` | Resources for `tarantool` container |
| postanalytics.tarantool.service.annotations | object | `{}` | Annotations to be added to Tarantool service |
| postanalytics.tolerations | list | `[]` | Node tolerations for post-analytics pod |
| sidecarDefaults.container.helper | object | *See below for details* | Default configuration for helper container |
| sidecarDefaults.container.helper.resources | object | `{}` | Resources for `helper` container. Applicable if `sidecarDefaults.deployment.scheme` is set to `split` |
| sidecarDefaults.container.init | object | *See below for details* | Default configuration for init-containers |
| sidecarDefaults.container.init.helper.resources | object | `{}` | Resources for `init-helper` container. Applicable if `sidecarDefaults.deployment.scheme` is set to `split` |
| sidecarDefaults.container.init.iptables.resources | object | `{}` | Resources for `init-iptables` container. Applicable if `sidecarDefaults.deployment.iptablesEnable` is set to `true` |
| sidecarDefaults.container.proxy | object | *See below for details* | Default configuration for proxy container |
| sidecarDefaults.container.proxy.image.image | string | `"quay.io/dmitriev/sidecar-proxy:4.0.3-1"` | Image for all containers in sidecar scheme |
| sidecarDefaults.container.proxy.image.pullPolicy | string | `"IfNotPresent"` | Image pullPolicy |
| sidecarDefaults.container.proxy.livenessProbe | object | *See below for details* | Parameters for httpGet liveness probe configuration. Applicable if "sidecarDefaults.container.proxy.livenessProbeEnable: true" |
| sidecarDefaults.container.proxy.livenessProbe.failureThreshold | int | `3` | Probe failure threshold |
| sidecarDefaults.container.proxy.livenessProbe.initialDelaySeconds | int | `60` | Initial delay in seconds. Do not set initial delay below 60. It's time for bootstrapping sidecar and connecting to the cloud |
| sidecarDefaults.container.proxy.livenessProbe.periodSeconds | int | `10` | Probe period in seconds |
| sidecarDefaults.container.proxy.livenessProbe.successThreshold | int | `1` | Probe success threshold |
| sidecarDefaults.container.proxy.livenessProbe.timeoutSeconds | int | `1` | Probe timeout in seconds |
| sidecarDefaults.container.proxy.livenessProbeEnable | bool | `true` | Enable httpGet liveness probe to path "sidecarDefaults.nginx.healthPath" |
| sidecarDefaults.container.proxy.single.resources | object | `{}` | Default resources for `proxy` container in `single` deployment scheme. Applicable only if `sidecarDefaults.deployment.scheme: single` |
| sidecarDefaults.container.proxy.split.resources | object | `{}` | Default resources for `proxy` container in `split` deployment scheme. Applicable if `sidecarDefaults.deployment.scheme` is set to `split` |
| sidecarDefaults.deployment.iptablesEnable | bool | `true` | Enable or disable `iptables` init container for port redirection: `true` or `false` |
| sidecarDefaults.deployment.scheme | string | `"single"` | Sidecar deployment scheme: `single` or `split` |
| sidecarDefaults.nginx | object | *See below for details* | Default parameters for Nginx configuration of sidecar proxy container. Parameters in this section can be overwritten individually for each pod using its `.metadata.annotations` |
| sidecarDefaults.nginx.healthPath | string | `"/health"` | Path to Nginx health check endpoint |
| sidecarDefaults.nginx.listenPort | int | `26001` | Port listening by sidecar proxy container. This port is reserved for using by Wallarm sidecar, can't be the same as nginx.proxyPassPort. |
| sidecarDefaults.nginx.proxyPassPort | int | `80` | Port listening by application container. This port is used as application container port, if pod has no exposed ports for application container. |
| sidecarDefaults.nginx.statusPath | string | `"/status"` | Path to Nginx status endpoint |
| sidecarDefaults.nginx.statusPort | int | `10246` | Port for Wallarm status, Nginx stats and health check endpoints |
| sidecarDefaults.nginx.wallarmMetricsPath | string | `"/wallarm-metrics"` | Port to Wallarm metrics endpoint. Metrics provide in Prometheus format |
| sidecarDefaults.nginx.wallarmMetricsPort | int | `18080` | Port for Wallarm metrics endpoint |
| sidecarDefaults.nginx.wallarmStatusPath | string | `"/wallarm-status"` | Path to Wallarm status endpoint, status provides in JSON format |
| sidecarDefaults.wallarm | object | *See below for details* | Wallarm node configuration. Parameters in this section can be overwritten individually for each pod using its `metadata.annotations` |
| sidecarDefaults.wallarm.mode | string | `"monitoring"` | Wallarm mode: `monitoring, `block` or `off` |
| sidecarDefaults.wallarm.modeAllowOverride | string | `"on"` | Manages the ability to override the wallarm_mode values via filtering in the Cloud (custom ruleset): `on`, `off` or `strict` |
| sidecarDefaults.wallarm.parseResponse | string | `"on"` | Whether to analyze the application responses for attacks: `on` or `off` |
| sidecarDefaults.wallarm.parseWebsocket | string | `"off"` | Whether to analyze WebSocket's messages for attacks: `on` or `off` |
| sidecarDefaults.wallarm.unpackResponse | string | `"on"` | Whether to decompress compressed data returned in the application response: `on` or `off` |
| sidecarDefaults.wallarm.upstream.connectAttempts | int | `10` | Defines the number of immediate reconnects to the Tarantool or Wallarm API |
| sidecarDefaults.wallarm.upstream.reconnectInterval | string | `"15s"` | Defines the interval between attempts to reconnect to the Tarantool or Wallarm API |
| wallarmApi | object | *See below for details* | Wallarm API settings for post-analytics module and sidecar containers |
| wallarmApi.caVerify | bool | `true` | Verify CA during connecting to Wallarm API service: `true` or `false` |
| wallarmApi.host | string | `"api.wallarm.com"` | Address of Wallarm API service |
| wallarmApi.port | int | `443` | Port of Wallarm API service |
| wallarmApi.token | string | `""` | Token to authorize in the Wallarm Cloud |
| wallarmApi.useSSL | bool | `true` | Use SSL to connect to Wallarm API service: `true` or `false` |