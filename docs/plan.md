# Plan: Nginx on AKS via Terraform + Argo CD + Helm

## Goal

Deploy a simple nginx web app on AKS, with:
- Azure resources managed by Terraform
- GitOps delivery via Argo CD
- Nginx packaged as a local Helm chart
- Ingress controller + monitoring stack alongside the app

## Architecture

```
Azure Subscription
└── VNet 10.10.0.0/16  (Azure CNI)
    └── Subnet aks-nodes  10.10.0.0/20
        └── AKS cluster
            ├── ns: argocd          → Argo CD (Helm via Terraform)
            ├── ns: ingress-nginx   → ingress-nginx (Helm via Terraform)
            │                         └── Azure Load Balancer + public IP
            ├── ns: monitoring      → kube-prometheus-stack (Argo CD app)
            └── ns: web             → nginx-demo (Argo CD app, local chart)
```

Routing on the single LB public IP (path-based, no DNS):
- `/`        → nginx-demo
- `/argocd`  → Argo CD UI
- `/grafana` → Grafana

## Repo layout

```
terraform-azure-aks/
├── infra/                       Terraform: Azure resources
│   ├── main.tf                  RG, VNet, subnet, AKS (Azure CNI)
│   ├── variables.tf
│   ├── outputs.tf               kubeconfig, cluster name, RG
│   └── terraform.tfvars.example
│
├── argocd/                      Terraform: cluster bootstrap
│   ├── main.tf                  providers (kubernetes, helm) wired to AKS
│   ├── argocd.tf                helm_release: argo-cd
│   ├── ingress.tf               helm_release: ingress-nginx
│   ├── apps.tf                  Argo CD root Application (App-of-Apps)
│   └── variables.tf
│
├── app/                         Helm charts deployed by Argo CD
│   ├── root/                    App-of-Apps: child Application manifests
│   │   ├── nginx-demo.yaml
│   │   └── monitoring.yaml
│   └── nginx-demo/              Local Helm chart for the demo app
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           └── configmap.yaml   custom index.html
│
└── docs/
    └── plan.md
```

## Tier responsibilities

| Tier      | Tool                              | Owns                                                      | Apply order |
|-----------|-----------------------------------|-----------------------------------------------------------|-------------|
| infra/    | Terraform `azurerm`               | RG, VNet, subnet, AKS, managed identity                   | 1st         |
| argocd/   | Terraform `helm` + `kubernetes`   | Argo CD, ingress-nginx, root Argo CD Application          | 2nd         |
| app/      | Helm (synced by Argo CD)          | nginx-demo, kube-prometheus-stack                         | continuous  |

## Design defaults (decided on the fly)

- **Region / SKU**: `eastus`, node pool `Standard_B2s`, 1–2 nodes
- **Networking**: Azure CNI, subnet `/20`
- **State backend**: local for now; swap to Azure Storage later (note in README)
- **Argo CD repo source**: this repo, branch `master`, path `app/root/`
- **Ingress**: path-based on LB public IP (no DNS)
- **Monitoring**: full kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter)
- **Argo CD UI**: exposed via Ingress at `/argocd`

## Implementation steps

1. **infra/**
   - Provider `azurerm`
   - Resource group, VNet, subnet
   - AKS cluster: Azure CNI, system node pool, managed identity
   - Outputs: `kube_config`, `host`, `cluster_ca_certificate`, `client_certificate`, `client_key`

2. **argocd/**
   - Providers `kubernetes` and `helm`, wired from `infra/` outputs (via `terraform_remote_state` or shared tfvars)
   - `helm_release` argo-cd in `argocd` namespace
   - `helm_release` ingress-nginx in `ingress-nginx` namespace
   - `kubernetes_manifest` for the root Argo CD Application pointing at `app/root/`

3. **app/nginx-demo/** (local Helm chart)
   - Deployment: 2 replicas of `nginx:alpine`, mounts ConfigMap as `/usr/share/nginx/html/index.html`
   - Service: ClusterIP
   - Ingress: path `/`, class `nginx`
   - ConfigMap: custom landing page

4. **app/root/**
   - `nginx-demo.yaml`: Argo CD Application → `app/nginx-demo/`
   - `monitoring.yaml`: Argo CD Application → upstream kube-prometheus-stack chart, with Ingress values for `/grafana`

## Apply workflow

```
cd infra/   && terraform init && terraform apply
cd ../argocd && terraform init && terraform apply
# Argo CD then syncs nginx-demo and monitoring from app/root/ automatically
```

## Verification

- `kubectl get pods -A` → all running
- `curl http://<LB_IP>/` → nginx-demo landing page
- Browse `http://<LB_IP>/argocd` → Argo CD UI (admin password via `kubectl -n argocd get secret argocd-initial-admin-secret`)
- Browse `http://<LB_IP>/grafana` → Grafana

## Out of scope (for this demo)

- TLS / cert-manager
- Custom DNS
- Remote Terraform state
- Multi-environment (dev/stage/prod)
- Horizontal pod autoscaling
