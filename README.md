This repo is an example of two clusters meshed together using cilium. An nginx
deployment of identical names are deployed to each cluster, with the caveat that
each have a message saying hello from either c1 or c2 cluster.

TODO: clean and reduce everything. Alot of noise created while cobbling
together. I wanted to lean on cilium for l2 announcments, rather than using
metallb. 

```
helm upgrade -i  cilium cilium/cilium --version 1.14.4 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=c1-control-plane \
  --set k8sServicePort=6443 \
  --set hostServices.enabled=false \
  --set externalIPs.enabled=true \
  --set nodePort.enabled=true \
  --set hostPort.enabled=true \
  --set operator.replicas=1 \
  --set cluster.name=c1 \
  --set cluster.id=1 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true 

cilium clustermesh enable --context kind-c1 --service-type LoadBalancer

kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "default-pool"
spec:
  cidrs:
  - cidr: "172.18.1.0/24"
EOF
```

```
helm upgrade -i  cilium cilium/cilium --version 1.14.4 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=c2-control-plane \
  --set k8sServicePort=6443 \
  --set hostServices.enabled=false \
  --set externalIPs.enabled=true \
  --set nodePort.enabled=true \
  --set hostPort.enabled=true \
  --set operator.replicas=1 \
  --set cluster.name=c2 \
  --set cluster.id=2 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true 

cilium clustermesh enable --context kind-c2 --service-type LoadBalancer

kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "default-pool"
spec:
  cidrs:
  - cidr: "172.18.2.0/24"
EOF
```

See kube-proxy replacement stuff:
https://medium.com/@charled.breteche/kind-cluster-with-cilium-and-no-kube-proxy-c6f4d84b5a9d
Needs these settings for things to workout.
```
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<name-of-cluster-like-"c1">-control-plane \
  --set k8sServicePort=6443 \
```

Also, this for kind cluster config:

```
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  kubeProxyMode: "none"
```
