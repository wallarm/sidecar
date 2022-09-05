# Wallarm Sidecar Deployment

Wallarm is the platform Dev, Sec, and Ops teams choose to build cloud-native applications securely, monitor them for modern threats, and get alerted when threats arise.

To secure an application deployed as a Pod in a Kubernetes cluster, you can run the NGINX-based Wallarm node in front of the application as a sidecar proxy container. Wallarm sidecar proxy will filter incoming traffic to the application Pod by allowing only legitimate requests and mitigating malicious ones.

This repository contains the Helm chart automating the Sidecar solution deployment.

## Usage

To run and use the solution, please refer to the [Wallarm Documentation](https://docs.wallarm.com/waf-installation/kubernetes/sidecar-proxy/deployment/).

## Contribution

Any contribution very welcome! To contribute, follow the guidelines below.

The repository contains the Makefile that handles all development routines. To run routines, use the following commands:

- Bootstrap a new Kubernetes cluster with defined version, as same as remove this one (`make init` and `make clean`)
- Develop your code local and immediately run it the cluster, as same as run tests in the pod or just shell (`make pod-run`, `make pod-test` and `make pod-sh`)
- Run integration testing in this local deployment (`make integration-test`)
- Run install, upgrade, diff, template and remove the helm chart (`make helm-*`)

## License

This code is released under the [Apache 2.0 License](https://github.com/wallarm/sidecar/tree/main/LICENSE).

Copyright &copy; 2022 Wallarm, Inc.
