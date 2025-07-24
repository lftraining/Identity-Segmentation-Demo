# identity-segmentation-demo
🐝 Cilium Identity‑Based Segmentation

1. Spin up a single‑node `kind` cluster with Cilium as the CNI.  
2. Deploy three pods (`frontend`, `backend`, `intruder`).  
3. Apply two CiliumNetworkPolicies:  
   * `default‑deny‑all‑ingress` – blocks everything.  
   * `allow‑frontend‑backend`  – re‑opens traffic from `role=frontend` to `role=backend`.  
4. Generate traffic and watch Cilium **allow** or **deny** packets based on the pods’ labels.

### Prerequisites:
- Note: commands were run on Ubuntu 24
- install:
    - Docker: version 27.5.1
      - sudo usermod -aG docker $USER && newgrp docker
    - Kind: version 0.29.0
    - kubectl: v1.30+
    - Cilium: latest 1.17.x

## Setup:
- Make project directory:
mkdir -p ~/identityseg/manifests && cd ~/identityseg

- Create kind-config.yaml (notes if you are not grabbing GitHub files)

- Create a cluster
kind create cluster --name id-seg-demo --config manifest/kind-config.yaml

kubectl get nodes --watch

- Install Cilium
cilium install --version 1.17.6
cilium status --wait

- create frontend.yaml, backend.yaml, and backend-svc.yaml (notes if you are not grabbing GitHub files)

- Apply workloads
kubectl apply -f manifest/frontend.yaml \
             -f manifest/backend.yaml \
             -f manifest/backend-svc.yaml

- sanity check
kubectl get pods
kubectl get svc backend

- create default-deny.yaml and allow-frontend-backend.yaml (notes if you are not grabbing GitHub files)

- Apply workloads
kubectl apply -f manifest/default-deny.yaml

kubectl apply -f manifest/allow-frontend-to-backend.yaml

- sanity check
kubectl get ciliumnetworkpolicies
kubectl get ciliumnetworkpolicy default-deny-all-ingress -o wide

## Steps:

#### In first terminal:

- deploy intruder pod:
kubectl run intruder --image=alpine --labels role=intruder \
  --command -- sleep 3600
kubectl wait --for=condition=ready pod/intruder --timeout=60s

- Create test_seg.sh script and make script executable:

- test_seg.sh:
#!/usr/bin/env bash
set -e
echo "✅ frontend -> backend (should pass)"; echo
kubectl exec frontend -- wget -qO- backend | head -1
echo
echo "✅ intruder -> backend (should fail)"; echo
kubectl exec intruder -- wget -qO- --timeout=3 backend >/dev/null 2>&1 && \
  echo "❌  Unexpectedly succeeded" || echo "Blocked as expected"

- make executable:
chmod +x script/test_seg.sh

- In first terminal, run script:
script/test_seg.sh

Expected test_seg.sh script run output:
~/identityseg$ script/test_seg.sh
✅ frontend -> backend (should pass)

<!DOCTYPE html>

✅ intruder -> backend (should fail)

Blocked


- Optional: Confirm pod identities. The Cilium policies are tied to these identities:
    - Run command:
    kubectl -n kube-system exec "$CILIUM_POD" -- cilium identity list | \
    - see output similar to:
            k8s:role=backend
            k8s:role=frontend
            k8s:role=intruder
    - Run command:
    kubectl -n kube-system exec "$CILIUM_POD" -- cilium identity list
    - see output similar to:
    8608    k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
        k8s:io.cilium.k8s.policy.cluster=kind-id-seg-cluster
        k8s:io.cilium.k8s.policy.serviceaccount=default
        k8s:io.kubernetes.pod.namespace=default
        k8s:role=backend
    9532    k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
        k8s:io.cilium.k8s.policy.cluster=kind-id-seg-cluster
        k8s:io.cilium.k8s.policy.serviceaccount=default
        k8s:io.kubernetes.pod.namespace=default
        k8s:role=frontend
    50744   k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=default
        k8s:io.cilium.k8s.policy.cluster=kind-id-seg-cluster
        k8s:io.cilium.k8s.policy.serviceaccount=default
        k8s:io.kubernetes.pod.namespace=default
        k8s:role=intruder


#### In second terminal, run:

CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
              -o jsonpath='{.items[0].metadata.name}')

- Optional: check to confirm agent grabbed policy
kubectl -n kube-system exec "$CILIUM_POD" -- cilium policy get | less

- get the pod 
kubectl -n kube-system exec -it "$CILIUM_POD" -- \
  cilium endpoint list | grep backend

- monitor for traffic to demonstrate policy in effect
kubectl -n kube-system exec -it "$CILIUM_POD" -- cilium monitor --type drop

- rerun test_seg.sh script in first terminal

- Check output in second terminal which should show expected output similar to below:
xx drop (Policykubectl get ciliumnetworkpolicy default-deny-all-ingress -o wide
 denied) flow 0x7c2352cd to endpoint 354, ifindex 9, file bpf_lxc.c:2118, , identity 50744->8608: 10.xxx.0.xx:52140 -> 10.xxx.0.xxx:80 tcp SYN

#### Monitor All Traffic
 - The previous monitor command only catches traffic that is dropped, but when the following
 commands are run, both approved and denied/dropped traffic is visible.

 - Get the endpoint ID for the pod
 BACKEND_ID=$(kubectl get cep backend -o jsonpath='{.status.id}')
echo "Backend endpoint ID = $BACKEND_ID"

- If needed, set CILIUM_POD again:
CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
              -o jsonpath='{.items[0].metadata.name}')

- Use the altered monitor command to monitor traffic: 
 kubectl -n kube-system exec -it "$CILIUM_POD" -- \
  cilium monitor --type policy-verdict --related-to "$BACKEND_ID"

- Expected output should show both accepted and dropped traffic. While traffic from the frontend to the backend should pass, traffic from the intruder to the backend should fail.
- Run test_seg.sh script again in other terminal. Expected output  of monitor command should be similar to below:
Policy verdict log: flow 0x100a8441 local EP ID 354, remote ID 9532, proto 6, ingress, action allow, auth: disabled, match L3-Only, 10.xxx.0.xxx:38178 -> 10.xxx.0.xxx:80 tcp SYN
Policy verdict log: flow 0x83556614 local EP ID 354, remote ID 50744, proto 6, ingress, action deny, auth: disabled, match none, 10.xxx.0.xx:34098 -> 10.xxx.0.xxx:80 tcp SYN
Policy verdict log: flow 0xb2b031f9 local EP ID 354, remote ID 50744, proto 6, ingress, action deny, auth: disabled, match none, 10.xxx.0.xx:34098 -> 10.xxx.0.xxx:80 tcp SYN
Policy verdict log: flow 0xf50c1462 local EP ID 354, remote ID 50744, proto 6, ingress, action deny, auth: disabled, match none, 10.xxx.0.xx:34098 -> 10.xxx.0.xxx:80 tcp SYN
Policy verdict log: flow 0xae4eea63 local EP ID 354, remote ID 9532, proto 6, ingress, action allow, auth: disabled, match L3-Only, 10.xxx.0.xxx:44950 -> 10.xxx.0.xxx:80 tcp SYN
