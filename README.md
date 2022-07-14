# Wallarm Sidecar Deployment

Wallarm is the platform Dev, Sec, and Ops teams choose to build cloud-native applications securely, monitor them for modern threats, and get alerted when threats arise.

Wallarm filtering node can be installed as a sidecar container to the same pod as the main application container. The Wallarm node filters incoming requests and forwards legitimate requests to the application container. For automation this deployment we use Sidecar Controller that can be installed by this chart.

TODO

## Contribution

Any contribution very welcome! So, you need to do it by the dollowing contribution guide.

This repo is based on Makefile that handles all development routines. So this means that you can make this routines just with a short command:

- Bootstrap a new Kubernetes cluster with defined version, as same as remove this one (`make init` and `make clean`)
- Develop your code local and immediately run it the cluster, as same as run tests in the pod or just shell (`make pod-run`, `make pod-test` and `make pod-sh`)
- Run integration testing in this local deployment (`make integration-test`)
- Run install, upgrade, diff, template and remove of the helm chart (`make helm-*`)

## License

This code is released under the [Apache 2.0 License](https://github.com/wallarm/sidecar/tree/main/LICENSE).

Copyright &copy; 2022 Wallarm, Inc.
