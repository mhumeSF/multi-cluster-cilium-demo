#!/bin/sh

set -e

ROOT="$(git rev-parse --show-toplevel)"

function info() {
    echo "=> ${1}"
}

pushd "${ROOT}" > /dev/null

KUBE_SYSTEM_NAMESPACE="kube-system"
CILIUM_NAMESPACE="${KUBE_SYSTEM_NAMESPACE}"
CILIUM_VERSION="v1.11.0-rc3"

CLUSTER_1_NAME=c1
CLUSTER_1_CONTEXT="kind-${CLUSTER_1_NAME}"
CLUSTER_2_NAME=c2
CLUSTER_2_CONTEXT="kind-${CLUSTER_2_NAME}"

CILIUM_NAMESPACE="${KUBE_SYSTEM_NAMESPACE}"

info "Creating the clusters..."
# - - - - - - - - - - - - - - - - - - - - -
# c1
# - - - - - - - - - - - - - - - - - - - - -

info "Creating cluster c1..."
kind create cluster --name "${CLUSTER_1_NAME}" --config "${CLUSTER_1_NAME}/kind.yaml"

info "Installing Cilium..."
helm upgrade -i --wait cilium cilium/cilium --version 1.14.4 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$CLUSTER_1_NAME-control-plane \
  --set k8sServicePort=6443 \
  --set l2announcements.enabled=true \
  --set devices=eth+ \
  --set l2announcements.leaseDuration=25s \
  --set l2announcements.leaseRenewalDeadline=15s \
  --set l2announcements.leaseRetryPeriod=8s \
  --set k8sClientRateLimit.qps=3000 \
  --set k8sClientRateLimit.burst=20000 \
  --set hostServices.enabled=false \
  --set externalIPs.enabled=true \
  --set nodePort.enabled=true \
  --set hostPort.enabled=true \
  --set operator.replicas=1 \
  --set cluster.name=$CLUSTER_1_NAME \
  --set cluster.id=1 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

info "Sleep for 30..."
sleep 30

info "Verify cilium status..."
cilium status --context $CLUSTER_1_CONTEXT --wait

info "Installing l2 policy..."
kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "default-pool"
spec:
  cidrs:
  - cidr: "172.18.1.0/24"
EOF

kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: main
  namespace: kube-system
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  interfaces:
  - ^eth[0-9]+
  externalIPs: true
  loadBalancerIPs: true
EOF

info "Enabling clustermesh..."
cilium clustermesh enable --context $CLUSTER_1_CONTEXT --service-type LoadBalancer
cilium clustermesh status --context kind-c1 --wait

# - - - - - - - - - - - - - - - - - - - - -
# c2
# - - - - - - - - - - - - - - - - - - - - -

info "Creating cluster c2..."
kind create cluster --name "${CLUSTER_2_NAME}" --config "${CLUSTER_2_NAME}/kind.yaml"

info "Installing Cilium..."
helm upgrade -i --wait cilium cilium/cilium --version 1.14.4 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=c2-control-plane \
  --set k8sServicePort=6443 \
  --set l2announcements.enabled=true \
  --set devices=eth+ \
  --set l2announcements.leaseDuration=25s \
  --set l2announcements.leaseRenewalDeadline=15s \
  --set l2announcements.leaseRetryPeriod=8s \
  --set k8sClientRateLimit.qps=3000 \
  --set k8sClientRateLimit.burst=20000 \
  --set hostServices.enabled=false \
  --set externalIPs.enabled=true \
  --set nodePort.enabled=true \
  --set hostPort.enabled=true \
  --set operator.replicas=1 \
  --set cluster.name=c2 \
  --set cluster.id=2 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

info "Sleep for 30..."
sleep 30

info "Verify cilium status..."
cilium status --context kind-c2 --wait

info "Installing l2 policy..."
kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "default-pool"
spec:
  cidrs:
  - cidr: "172.18.2.0/24"
EOF

kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: main
  namespace: kube-system
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  interfaces:
  - ^eth[0-9]+
  externalIPs: true
  loadBalancerIPs: true
EOF

info "Enabling clustermesh..."
cilium clustermesh enable --context kind-c2 --service-type LoadBalancer
cilium clustermesh status --context kind-c2 --wait

# - - - - - - - - - - - - - - - - - - - - -
# mesh c1 + c2
# - - - - - - - - - - - - - - - - - - - - -
info "Connecting clusters..."
cilium clustermesh connect --context kind-c1 \
   --destination-context kind-c2

CLUSTER=$CLUSTER_1_NAME envsubst < ./nginx-app/app.yaml | kubectl apply -f - --context=$CLUSTER_1_CONTEXT
CLUSTER=$CLUSTER_2_NAME envsubst < ./nginx-app/app.yaml | kubectl apply -f - --context=$CLUSTER_2_CONTEXT

kubectl delete deploy nginx-deployment --context=$CLUSTER_1_CONTEXT
