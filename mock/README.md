## Test cases
By using the following cases we test template functionality of sidecar controller

### 1. Main functionality
Check that functionality of the following settings are working properly:
- `config.injectionStrategy.schema`
- `config.injectionStrategy.iptablesEnable`

#### 1.1. Single mode with iptables enabled
#### 1.2. Single mode with iptables disabled
#### 1.3. Split mode with iptables enabled
#### 1.4. Split mode with iptables disabled

### 2. Application port detection
Check that logic of application port detection is working as expected

#### 2.1. Application port defined in pod annotation `sidecar.wallarm.io/application-port`
#### 2.2. Application container has named port "http"
The number of `http` port is different from `config.nginx.applicationPort` 
#### 2.3. Application container has several unnamed ports
First port should be taken
#### 2.4. Application container has no ports specified
The port from Helm chart setting `config.nginx.applicationPort` should be taken

### 3. Managing sidecar resources
Check that sidecar container resources, which specified either by chart values or by annotations, are applied properly

#### 3.1. Resources are specified in chart values
#### 3.2. Resources are specified in pod's annotations
#### 3.1. Resources are specified in chart values but overwritten by pod's annotations

### 4. Managing sidecar security context
Check that security context provided by user in chart values is applied properly

### 5. Wallarm node specific settings
Check that wallarm specific settings configured by pod's annotations are applied properly

### 6. Nginx extra modules
Test that built in extra modules specified in pod's annotations are applied properly

### 7. User specified extra volumes
Test that extra volumes which specified in pod's annotations applied properly and can be used as additional Nginx configs
