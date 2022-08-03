# Wallarm sidecar controller
Wallarm sidecar controller Helm chart for Kubernetes

## Introduction
Wallarm sidecar controller provides an ability to automatically inject Wallarm sidecar proxy into a Kubernetes Pod.
Sidecar proxy filters and protects inbound traffic to the Pod it is attached to.

Components of Wallarm sidecar controller:
- Sidecar controller - is the mutating admission webhook which injects Wallarm sidecar resources into Pod and provides configuration based on chart values and annotations.
- Post-analytics module - is the local data analytics backend for Wallarm sidecar proxies. Implemented using Tarantool and set of helper containers.

## Prerequisites
- Kubernetes cluster >= 1.19-1.24
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

| Label            | Enabled value  | Disabled value  |
|------------------|----------------|-----------------|
| wallarm-sidecar  | enabled        | disabled        |

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
          image: kennethreitz/httpbin
          ports:
            - name: http
              containerPort: 80
```

### Using different deployment schemas
Sidecar controller provides two different deployment schemas for sidecar resources: `single` (default) and `split`.
Deployment schema can be configured in the following ways:
- globally by setting Helm chart value `config.injectionStrategy.schema` to `single` (default) or `split`
- on per-pod basis by setting Pod's annotation `sidecar.wallarm.io/sidecar-injection-schema` to `"single"` or `"split"`

#### Single (default)
`single` - is default deployment schema where only one additional container will be injected into a Pod, apart from 
optional init container with iptables. This container contains Nginx proxy with Wallarm module and helper services.
All these processes run and manage by supervisord. Below is the list of sidecar resources for single deployment schema:
- `sidecar-init-iptables` init container with iptables. Enabled by default and can be disabled.
- `sidecar-proxy` container with Nginx and helper services

#### Split
`split` - is an optional deployment schema where two additional containers will be added into a Pod, apart from init containers. 
In this schema all helper services are moved out of `sidecar-proxy` container, which contains only Nginx service now. 
Split deployment schema aims to have more granular control over resources which consumes by Nginx and helper services.
Use split schema for dividing the CPU/Memory/Storage namespaces between wallarm itself and helper containers. 
This can be helpful for highly loaded applications. Below is the list of sidecar resources for split deployment schema:
- `sidecar-init-iptables` init container with iptables. Enabled by default and can be disabled.
- `sidecar-init-helper` init container with helper services which aim to register sidecar proxy in Wallarm cloud
- `sidecar-proxy` container with Nginx only
- `sidecar-helper` container with helper services

### Application container port auto-discovery
In order to handle and forward incoming traffic properly, sidecar proxy must be aware about TCP port
on which application container accepts incoming requests. Application port auto-discovery performs in the following priority:
1. If port number is defined in pod's annotation `sidecar.wallarm.io/application-port` then number of this port will be used
2. If application container has defined port with name `http`, then number of this port will be used
3. If application container doesn't have port with name `http`, then the number of first defined container port will be used
4. If application container has no any defined container ports, then number of port from Helm char value `config.nginx.applicationPort` will be used

*NOTE* If for some reason auto-discovery of application port does not work as expected, just use option 1 or 4 above.

### Inbound traffic interception (port redirection)
By default, Wallarm sidecar intercepts inbound traffic which comes to Pod's IP and application container port, then redirects this
traffic to sidecar proxy container using iptables manipulation. Sidecar proxy does the job and then forwards traffic to application container.
Inbound traffic interception is implemented using init container with `iptables`. This default behaviour can be configured:
- on per-pod basis by setting Pod's annotation `sidecar.wallarm.io/sidecar-injection-iptables-enable` to `"false"`
- globally by setting helm chart value `config.injectionStrategy.iptablesEnable` to `"false"`

If inbound traffic interception is disabled, then sidecar proxy container will publish port with name `proxy`. In this case
inbound traffic from Kubernetes service should be sent to the port named `proxy`, by setting `spec.ports.targetPort: proxy` in your Service manifest.

Example with disabled inbound traffic interception on per-pod basis is shown below:

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
        sidecar.wallarm.io/sidecar-injection-iptables-enable: "false"
    spec:
      containers:
        - name: application
          image: kennethreitz/httpbin
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
Requests and limits for injected sidecar containers can be configured either globally using Helm chart values or 
individually on per-pod basis using annotations. Annotations take precedence over Helm chart values.

#### Configuring resources globally using Helm char values

| Deployment schema | Container name        | Chart value                                      |
|-------------------|-----------------------|--------------------------------------------------|
| Split, Single     | sidecar-proxy         | config.sidecar.containers.proxy.resources        |
| Split             | sidecar-helper        | config.sidecar.containers.helper.resources       |
| Split, Single     | sidecar-init-iptables | config.sidecar.initContainers.iptables.resources |
| Split             | sidecar-init-iptables | config.sidecar.initContainers.helper.resources   |

Example of Helm chart values file for managing resources (requests & limits) globally

```yaml
config:
  sidecar:
    containers:
      proxy:
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
      helper:
        resources:
          requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 300m
              memory: 256Mi
    initContainers:
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

#### Configuring resources on per-pod basis using Pod's annotations

| Deployment schema | Container name        | Annotation                                                             |
|-------------------|-----------------------|------------------------------------------------------------------------|
| Single, Split     | sidecar-proxy         | `sidecar.wallarm.io/proxy-{cpu,memory,cpu-limit,memory-limit}`         |
| Split             | sidecar-helper        | `sidecar.wallarm.io/helper-{cpu,memory,cpu-limit,memory-limit}`        |
| Single, Split     | sidecar-init-iptables | `sidecar.wallarm.io/init-iptables-{cpu,memory,cpu-limit,memory-limit}` |
| Split             | sidecar-init-helper   | `sidecar.wallarm.io/init-helper-{cpu,memory,cpu-limit,memory-limit}`   |

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
          image: kennethreitz/httpbin
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

Additional modules can be enabled only on per-pod basis by setting Pod's annotation `sidecar.wallarm.io/nginx-extra-modules`.
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
          image: kennethreitz/httpbin
          ports:
            - name: http
              containerPort: 80
```

### Using additional user provided Nginx configuration
Here is an option to include user provided configuration into Nginx config of sidecar proxy.
Additional configuration can be included on 3 different levels of Nginx config on per-pod basis using annotations.
The format of annotation's value is JSON list.

| Nginx config section | Annotation                                  | Value type |
|----------------------|---------------------------------------------|------------|
| http                 | `sidecar.wallarm.io/nginx-http-include`     | JSON list  |
| server               | `sidecar.wallarm.io/nginx-server-include`   | JSON list  |
| location             | `sidecar.wallarm.io/nginx-location-include` | JSON list  |

Providing additional configuration files into sidecar proxy container achieves by using extra Volumes and Volumes mounts.

| Item          |  Annotation                                    | Value type  |
|---------------|------------------------------------------------|-------------|
| Volumes       | `sidecar.wallarm.io/proxy-extra-volumes`       | JSON object |
| Volume mounts | `sidecar.wallarm.io/proxy-extra-volume-mounts` | JSON object |

Below is an example with additional user provided configuration file which includes on `http` level of Nginx config.
This example assumes that config map `nginx-http-include-cm` was created in advance and contains valid Nginx configuration directives.

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
        sidecar.wallarm.io/proxy-extra-volumes: "[{'name': 'nginx-http-extra-config', 'configMap': {'name': 'nginx-http-include-cm'}}]"
        sidecar.wallarm.io/proxy-extra-volume-mounts: "[{'name': 'nginx-http-extra-config', 'mountPath': '/nginx_include/http.conf', 'subPath': 'http.conf'}]"
        sidecar.wallarm.io/nginx-http-include: "['/nginx_include/http.conf']"
            spec:
      containers:
        - name: application
          image: kennethreitz/httpbin
          ports:
            - name: http
              containerPort: 80
```

## List of annotations

All annotations below are specified without prefix `sidecar.wallarm.io/`, to use them properly just add this prefix, e.g. `sidecar.wallarm.io/wallarm-mode`
*NOTE*: annotations take precedence over Helm chart values.

### Sidecar deployment settings

| Annotation                          | Chart value                                                      | Description                                                                                                                                                                                                            |
|-------------------------------------|------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| sidecar-injection-schema            | config.injectionStrategy.schema                                  | Sidecar deployment schema: `single` or `split`                                                                                                                                                                         |
| sidecar-injection-iptables-enable   | config.injectionStrategy.iptablesEnable                          | Enable or disable `iptables` init container for port redirection: `true` or `false`                                                                                                                                    |
| wallarm-application                 | NA                                                               | The ID of Wallarm application (optional)                                                                                                                                                                               |
| wallarm-block-page                  | NA                                                               | Lets you set up the response to the blocked request, e.g. ``                                                                                                                                                           |
| wallarm-enable-libdetection         | NA                                                               | Enables additional validation of the SQL Injection attacks via the libdetection library: `on` or `off`                                                                                                                 |
| wallarm-mode                        | config.wallarm.mode                                              | Wallarm mode: `monitoring`, `block` or `off`                                                                                                                                                                           |
| wallarm-mode-allow-override         | config.wallarm.modeAllowOverride                                 | Manages the ability to override the wallarm_mode values via filtering in the Cloud (custom ruleset): `on`, `off` or `strict`                                                                                           |
| wallarm-parser-disable              | NA                                                               | Allows to disable parsers. The directive values corresponds to the name of the parser to be disabled. Multiple parser can be specified, dividing by semicolon. E.g. `json`, `json; base64`                             |
| wallarm-parse-response              | config.wallarm.parseResponse                                     | Whether to analyze the application responses for attacks: `on` or `off`                                                                                                                                                |
| wallarm-parse-websocket             | config.wallarm.parseWebsocket                                    | Whether to analyze WebSocket's messages for attacks: `on` or `off`                                                                                                                                                     |
| wallarm-unpack-response             | config.wallarm.unpackResponse                                    | Whether to decompress compressed data returned in the application response: `on` or `off`                                                                                                                              |
| wallarm-upstream-connect-attempts   | config.wallarm.upstream.connectAttempts                          | Defines the number of immediate reconnects to the Tarantool or Wallarm API                                                                                                                                             |
| wallarm-upstream-reconnect-interval | config.wallarm.upstream.reconnectInterval                        | Defines the interval between attempts to reconnect to the Tarantool or Wallarm API                                                                                                                                     |
| application-port                    | config.nginx.applicationPort                                     | Port listening by application container. This port is used as application container port, if pod has no exposed ports for application container. Refer `Application container port auto-discovery` section for details |
| nginx-listen-port                   | config.nginx.listenPort                                          | Port listening by sidecar proxy container. This port is reserved for using by Wallarm sidecar, can't be the same as `config.nginx.applicationPort`                                                                     |
| nginx-http-include                  | NA                                                               | JSON list of full paths to additional config files which should be included on `http` level of NGINX configuration. Refer "Using additional user provided Nginx configuration" section for more details                |
| nginx-http-snippet                  | NA                                                               | Additional inline config which should be included on `http` level of NGINX configuration. Refer "Using additional user provided Nginx configuration" section for more details                                          |
| nginx-server-include                | NA                                                               | JSON list of full paths to additional config files which should be included on `server` level of NGINX configuration. Refer "Using additional user provided Nginx configuration" section for more details              |                                                                                                                                                                                                        |
| nginx-server-snippet                | NA                                                               | Additional inline config which should be included on `server` level of NGINX configuration. Refer "Using additional user provided Nginx configuration" section for more details                                        |
| nginx-location-include              | NA                                                               | JSON list of full paths to additional config files which should be included on `location` level of NGINX configuration. Refer "Using additional user provided Nginx configuration" section for more details            |                                                                                                                                                                                                         |
| nginx-location-snippet              | NA                                                               | Additional inline config which should be included on `location` level of NGINX configuration. Refer "Using additional user provided Nginx configuration" section for more details                                      |
| nginx-extra-modules                 | NA                                                               | JSON list of NGINX modules to enable. Refer "Enable additional Nginx modules" section for details                                                                                                                      |
| proxy-extra-volumes                 | NA                                                               | User volumes to be added to the Pod (JSON object). Example: `"[{'name':'volumeName','configMap':{'name':'someConfigMapName'}}]"`                                                                                       |
| proxy-extra-volume-mounts           | NA                                                               | User volume mounts to be added to the `proxy` container (JSON object). Example:`"[{'name':'volumeName','mountPath':'/some/thing'}]"`                                                                                   |
| proxy-cpu                           | config.sidecar.containers.proxy.resources.requests.cpu           | Requested CPU for `proxy` container                                                                                                                                                                                    |
| proxy-memory                        | config.sidecar.containers.proxy.resources.requests.memory        | Requested memory for `proxy` container                                                                                                                                                                                 |
| proxy-cpu-limit                     | config.sidecar.containers.proxy.resources.limits.cpu             | CPU limit for `proxy` container                                                                                                                                                                                        |
| proxy-memory-limit                  | config.sidecar.containers.proxy.resources.limits.memory          | Memory limit for `proxy` container                                                                                                                                                                                     |
| helper-cpu                          | config.sidecar.containers.helper.resources.requests.cpu          | Requested CPU for `helper` container                                                                                                                                                                                   |
| helper-memory                       | config.sidecar.containers.helper.resources.requests.memory       | Requested memory for `helper` container                                                                                                                                                                                |
| helper-cpu-limit                    | config.sidecar.containers.helper.resources.limits.cpu            | CPU limit for `helper` container                                                                                                                                                                                       |
| helper-memory-limit                 | config.sidecar.containers.helper.resources.limits.memory         | Memory limit for `helper` container                                                                                                                                                                                    |
| init-iptables-cpu                   | config.sidecar.initContainers.iptables.resources.requests.cpu    | Requested CPU for `init-iptables` container                                                                                                                                                                            |
| init-iptables-memory                | config.sidecar.initContainers.iptables.resources.requests.memory | Requested memory for `init-iptables` container                                                                                                                                                                         |
| init-iptables-cpu-limit             | config.sidecar.initContainers.iptables.resources.limits.cpu      | CPU limit for `init-iptables` container                                                                                                                                                                                |
| init-iptables-memory-limit          | config.sidecar.initContainers.iptables.resources.limits.memory   | Memory limit for `init-iptables` container                                                                                                                                                                             |
| init-helper-cpu                     | config.sidecar.initContainers.helper.resources.requests.cpu      | Requested CPU for `init-helper` container                                                                                                                                                                              |
| init-helper-memory                  | config.sidecar.initContainers.helper.resources.requests.memory   | Requested memory for `init-helper` container                                                                                                                                                                           |
| init-helper-cpu-limit               | config.sidecar.initContainers.helper.resources.limits.cpu        | CPU limit for `init-helper` container                                                                                                                                                                                  |
| init-helper-memory-limit            | config.sidecar.initContainers.helper.resources.limits.memory     | Memory limit for `init-helper` container                                                                                                                                                                               |
