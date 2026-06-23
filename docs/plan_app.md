# Plan: `app/` — Nginx Web App via Argo CD + Local Helm Chart

Scope: a local Helm chart for an nginx demo app, delivered to AKS by Argo CD.
Boundary: this plan assumes the `infra/` tier is applied (AKS running, Argo CD installed in namespace `argocd`). It stops when the app is reachable via an Azure Load Balancer public IP.

## Deliverable

- A local Helm chart at `app/nginx-demo/` that renders Deployment + Service + Ingress + ConfigMap
- An Argo CD `Application` resource pointing at that chart path in this repo
- An ingress-nginx controller exposing the app on an Azure LB public IP
- Verifiable from the browser: `http://<LB_IP>/` returns the custom landing page

---

## Target file structure

Final layout. Files are added **progressively**, one phase at a time — not all at once.

```
app/
└── nginx-demo/                 Local Helm chart (this is what Argo CD syncs)
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── configmap.yaml      custom index.html
        ├── deployment.yaml
        ├── service.yaml
        └── ingress.yaml
argocd/
└── nginx-demo-app.yaml         Argo CD Application manifest (applied manually with kubectl, not synced by Argo CD)
```

Repo source for Argo CD: `https://github.com/simonangel-fong/terraform-azure-aks`, branch `master`, path `app/nginx-demo`.

---

## Phase 0 — Prerequisites

Verify before touching the app tier.

- [x] `infra/` applied, AKS reachable: `kubectl get nodes` → Ready
- [x] Argo CD running: `kubectl -n argocd get pods` → all Running
- [x] Argo CD UI reachable via port-forward (sanity check):
  ```sh
  kubectl -n argocd port-forward svc/argocd-server 8080:443
  # browse https://localhost:8080
  ```
- [x] Helm CLI installed (for local chart linting): `helm version`

---

## Phase 1 — Minimal nginx web app (single pod, no Argo CD yet) ✅

- Goal:
  - smallest possible local Helm chart that renders a running nginx pod with a custom landing page
  - install manually with `helm install` first to prove the chart is sound, then hand off to Argo CD in Phase 4

- Files to create:
  - `app/nginx-demo/Chart.yaml`: `apiVersion: v2`, `name: nginx-demo`, `version: 0.1.0`, `appVersion: "1.27"`
  - `app/nginx-demo/values.yaml`:
    ```yaml
    image:
      repository: nginx
      tag: alpine
    replicaCount: 1
    service:
      type: ClusterIP
      port: 80
    indexHtml: |
      <h1>nginx-demo on AKS</h1>
      <p>Served by Argo CD + local Helm chart.</p>
    ```
  - `app/nginx-demo/templates/configmap.yaml`: ConfigMap `nginx-demo-index` with key `index.html` from `.Values.indexHtml`
  - `app/nginx-demo/templates/deployment.yaml`: single Deployment, mounts the ConfigMap at `/usr/share/nginx/html/index.html` (subPath)
  - `app/nginx-demo/templates/service.yaml`: ClusterIP Service, port 80 → containerPort 80

- Checkpoint:

```sh
helm lint app/nginx-demo
helm template app/nginx-demo                    # eyeball the rendered yaml

# install manually into a throwaway namespace
kubectl create ns web
helm install nginx-demo app/nginx-demo -n web
kubectl -n web get pods,svc                     # 1 pod Running, 1 ClusterIP svc

# verify the landing page
kubectl -n web port-forward svc/nginx-demo 8081:80
# browse http://localhost:8081  → custom landing page

# tear down before Phase 2
helm uninstall nginx-demo -n web
kubectl delete ns web
```

---

## Phase 2 — Replicas ✅

- Goal:
  - scale the Deployment to multiple replicas, confirm Service load-balances across pods

- Files to update:
  - `app/nginx-demo/values.yaml`: `replicaCount: 3`
  - (no template changes — `deployment.yaml` already reads `.Values.replicaCount`)

- Checkpoint:

```sh
helm install nginx-demo app/nginx-demo -n web --create-namespace
kubectl -n web get pods -o wide                 # 3 pods, ideally on >1 node
kubectl -n web get endpoints nginx-demo         # 3 endpoint IPs

# hit the service repeatedly, confirm it answers from different pods
kubectl -n web port-forward svc/nginx-demo 8081:80
for i in 1 2 3 4 5; do curl -s http://localhost:8081 > /dev/null && echo ok; done

# tear down before Phase 3
helm uninstall nginx-demo -n web
kubectl delete ns web
```

---

## Phase 3 — Ingress (ingress-nginx + Ingress resource) ✅

- Goal:
  - install the ingress-nginx controller (creates an Azure LB + public IP)
  - add an `Ingress` resource to the chart, route `/` to the nginx-demo Service
  - reach the app from the browser via the LB public IP — no port-forward

- Sub-step 3a — install ingress-nginx controller (one-time, cluster-wide, run manually — not committed to this repo and not managed by Argo CD):
  ```sh
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  helm install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace \
    --set controller.service.type=LoadBalancer
  ```

- Sub-step 3b — add Ingress to the chart:
  - `app/nginx-demo/values.yaml` (append):
    ```yaml
    ingress:
      enabled: true
      className: nginx
      path: /
      pathType: Prefix
    ```
  - `app/nginx-demo/templates/ingress.yaml`: `networking.k8s.io/v1` Ingress, gated by `if .Values.ingress.enabled`, routes `path` → Service `nginx-demo:80`

- Checkpoint:

```sh
# controller should have a public IP
kubectl -n ingress-nginx get svc ingress-nginx-controller
# NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)
# ingress-nginx-controller   LoadBalancer   10.0.x.x      <PUBLIC_IP>    80:..., 443:...

# install the app with ingress enabled
helm install nginx-demo app/nginx-demo -n web --create-namespace
kubectl -n web get ingress                      # ADDRESS should populate within ~30s

LB_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s http://$LB_IP/                          # custom landing page
# also browse http://$LB_IP/ in a browser

# tear down before Phase 5 (keep ingress-nginx controller installed)
helm uninstall nginx-demo -n web
kubectl delete ns web
```

---

## Phase 4 — Verify the Azure Load Balancer ✅

- Goal:
  - confirm AKS provisioned an Azure LB + public IP in the **node resource group** (not the main RG)
  - record the public IP for documentation

- Checkpoint:

```sh
# node resource group name = local.common_name in Terraform
NODE_RG="aks-demo-dev"

# the public IP resource (auto-created by AKS for the LoadBalancer Service)
az network public-ip list -g $NODE_RG -o table
# Name                                                          ResourceGroup    Location    Zones    Address          AddressVersion    AllocationMethod    IdleTimeoutInMinutes    ProvisioningState
# ------------------------------------------------------------  ---------------  ----------  -------  ---------------  ----------------  ------------------  ----------------------  -----------------
# kubernetes-<hash>                                             aks-demo-dev     eastus               <PUBLIC_IP>      IPv4              Static              4                       Succeeded

# the load balancer itself
az network lb list -g $NODE_RG -o table
# Name       ResourceGroup    Location    ProvisioningState
# ---------  ---------------  ----------  -----------------
# kubernetes aks-demo-dev     eastus      Succeeded

# the frontend IP config + backend pool
az network lb show -g $NODE_RG -n kubernetes \
  --query "{frontends:frontendIpConfigurations[].publicIpAddress.id, rules:loadBalancingRules[].name}" -o yaml

# sanity: the EXTERNAL-IP reported by kubectl should match the public IP above
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

If the IP matches and `curl http://$LB_IP/` still returns the landing page, the LB chain is correct end-to-end.

---

## Phase 5 — Hand off to Argo CD

- Goal:
  - delete the manually-installed Helm release and let Argo CD own the app
  - app reconciles automatically from this repo

- Files to create:
  - `argocd/nginx-demo-app.yaml`: Argo CD `Application` (apiVersion `argoproj.io/v1alpha1`)
    - `metadata.name: nginx-demo`, `metadata.namespace: argocd`
    - `spec.project: default`
    - `spec.source`:
      - `repoURL: https://github.com/simonangel-fong/terraform-azure-aks`
      - `targetRevision: master`
      - `path: app/nginx-demo`
      - `helm: { releaseName: nginx-demo }`
    - `spec.destination: { server: https://kubernetes.default.svc, namespace: web }`
    - `spec.syncPolicy.automated: { prune: true, selfHeal: true }`
    - `spec.syncPolicy.syncOptions: [ CreateNamespace=true ]`

- Checkpoint:

```sh
# make sure no manual release lingers
helm uninstall nginx-demo -n web --ignore-not-found
kubectl delete ns web --ignore-not-found

# hand off
kubectl apply -f argocd/nginx-demo-app.yaml

# Argo CD picks it up
kubectl -n argocd get applications
# NAME         SYNC STATUS   HEALTH STATUS
# nginx-demo   Synced        Healthy

# resources show up in the target namespace, created by Argo CD
kubectl -n web get all,ingress

# same LB IP, same landing page — but now GitOps-managed
curl -s http://$LB_IP/
```

- Verify drift correction:
  ```sh
  kubectl -n web scale deploy nginx-demo --replicas=1
  # within ~3 min Argo CD reverts it back to replicaCount from values.yaml
  kubectl -n web get deploy nginx-demo
  ```

---

## Out of scope (for this demo)

- TLS / cert-manager
- Custom DNS (A record pointing at the LB IP)
- App-of-Apps pattern (single Application is enough here)
- Monitoring stack (kube-prometheus-stack)
- HPA / PDB / NetworkPolicy
- Multi-environment values (dev/stage/prod overlays)
