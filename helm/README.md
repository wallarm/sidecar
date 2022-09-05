# Wallarm Sidecar Helm chart

To secure an application deployed as a Pod in a Kubernetes cluster, you can run the NGINX-based Wallarm node in front of the application as a sidecar controller. Wallarm sidecar controller will filter incoming traffic to the application Pod by allowing only legitimate requests and mitigating malicious ones.

This repository contains the Helm chart automating the Sidecar solution deployment.

To run and use the solution, please refer to the [Wallarm Documentation](https://docs.wallarm.com/waf-installation/kubernetes/sidecar-proxy/deployment/).
