# Plan: `infra/` — Azure Resources via Terraform

Scope: everything needed to hand a working AKS cluster to the `argocd/` tier.
Boundary: this plan stops at `terraform output` producing kubeconfig data. Installing Argo CD is the next tier's job.

## Deliverable

A `terraform apply` in `infra/` that produces:

- A running AKS cluster with Azure CNI
- Outputs consumable by the `argocd/` tier (`host`, `cluster_ca_certificate`, `client_certificate`, `client_key`, or `kube_config_raw`)
- Optional: a local `kubeconfig` file for manual `kubectl` access

---

## Target file structure

Final layout of `infra/`. Files are added **progressively**, one per phase — not all at once. Numeric prefixes order how a reader walks the tier.

```
infra/
├── 01_variables.tf      input variables
├── 02_locals.tf         derived names, common tags
├── 03_providers.tf      terraform + azurerm version + provider config
├── 04_outputs.tf        outputs for argocd/ tier
├── 05_az_rg.tf          resource group
├── 06_az_vnet.tf        VNet + subnet
├── 07_az_aks.tf         AKS cluster
├── 08_argocd.tf         placeholder / handoff marker
├── backend.hcl.example
├── terraform.tfvars.example
└── .gitignore           *.tfstate, *.tfvars (except .example), .terraform/
```

---

## Phase 0 — Prerequisites

Verify before touching code.

- [x] Azure CLI installed: `az version` → **2.87.0**
- [x] Logged in: `az login` → `simonangelfong@gmail.com`
- [x] Subscription selected: `az account show` → `Azure subscription 1` (`adb97c42-2927-4b7d-881d-59fc6c69b886`)
- [x] Terraform ≥ 1.6 installed: `terraform version` → **1.15.2** (1.15.6 available, optional upgrade)
- [x] `kubectl` installed: `kubectl version --client` → **v1.34.1**
- [x] Quota check: B-series vCPUs available in target region (`az vm list-usage -l eastus -o table`) → **4 vCPUs** (Standard BS, Bsv2)

---

## Phase 1 — Bootstrap

- Goal:
  - get a working Terraform workspace that can talk to Azure.
  - **No Azure resources created yet**

- Files to create:
  - `01_variables.tf`: input variable declarations only (no resources)
  - `02_locals.tf`: derived names and a `common_tags` local merged into every resource later
  - `03_providers.tf`:
    - `terraform { required_version, required_providers }` block
    - s3 backend
    - `provider "azurerm" { features {} subscription_id = var.subscription_id }`
  - `04_outputs.tf`: empty stub, populated in later phases
  - `backend.hcl.example`: documented sample showing `bucket`, `key`, `region`, `encrypt`, `use_lockfile`
  - `terraform.tfvars.example`: documented sample showing `subscription_id` and any overrides
  - `.gitignore`: `*.tfstate*`, `*.tfvars` (but not `*.tfvars.example`), `.terraform/`, `.terraform.lock.hcl` left committed

- Verify:

```sh
cd infra/
terraform init -backend-config=backend.hcl   # downloads azurerm provider, configures s3 backend
terraform validate                            # config is syntactically and semantically valid
terraform plan                                # expect: "No changes" — zero resources defined
```

---

## Phase 2 — Resource Group

- Goal:
  - smallest possible resource lands in Azure to prove the provider chain works.

- Files to create:
  - `05_az_rg.tf`: single `azurerm_resource_group.main` using `local.resource_group_name`, `local.location`, `local.default_tags`

- Checkpoint:

```sh
terraform plan      # expect: 1 to add
terraform apply
az group show -n rg-aks-demo-dev -o table
# Location    Name
# ----------  ---------------
# eastus      rg-aks-demo-dev
```

---

## Phase 3 — Networking (VNet + subnet)

- Goal:
  - VNet sized for Azure CNI pod IPs.

- Create vnet: `10.10.0.0/16`
- Create subnets:
  - `subnet1`: `10.10.0.0/20` (~4,091 usable) — AKS node subnet
  - `subnet2`: `10.10.32.0/20` (~4,091 usable) — reserved for future workloads / ingress

- Files to create:
  - `06_az_vnet.tf`: `azurerm_virtual_network.main` + `azurerm_subnet.subnet1` + `azurerm_subnet.subnet2`

- Checkpoint:

```sh
terraform plan      # expect: 3 to add (vnet + 2 subnets)
terraform apply
az network vnet subnet show -g rg-aks-demo-dev --vnet-name aks-demo-dev -n main -o table
# AddressPrefix    DefaultOutboundAccess    Name    PrivateEndpointNetworkPolicies    PrivateLinkServiceNetworkPolicies    ProvisioningState    ResourceGroup
# ---------------  -----------------------  ------  --------------------------------  -----------------------------------  -------------------  ---------------
# 10.10.0.0/20     True                     main    Disabled                          Enabled                              Succeeded            rg-aks-demo-dev
```

---

## Phase 4 — AKS cluster

- Goal:
  - a minimum-viable AKS cluster on the subnet above.

- Create AKS cluster with default node pool
  - `azurerm_user_assigned_identity.base` + `azurerm_role_assignment.base` (Network Contributor on RG)
  - `azurerm_kubernetes_cluster.main`:
    - `kubernetes_version = local.aks_versions`
    - `network_profile { network_plugin = "azure" ... }`
    - `default_node_pool` with `local.node_count` / `local.node_vm_size`
    - `identity { type = "UserAssigned" }`
    - `oidc_issuer_enabled = true`, `workload_identity_enabled = true`
    - `lifecycle { ignore_changes = [default_node_pool[0].node_count] }` so autoscaling later doesn't fight Terraform

- Output the command to connect with cluster via kubectl

- Files to create / update:
  - `07_az_aks.tf`: identity, role assignment, cluster
  - `04_outputs.tf` (populate):
    - `host`, `cluster_ca_certificate`, `client_certificate`, `client_key` (marked `sensitive = true`)
    - `kube_config_raw` (sensitive)
    - `kubeconfig_command`: convenience string, e.g. `az aks get-credentials -g <rg> -n <cluster> --file ./kubeconfig`

- Checkpoint:

```sh
terraform plan      # expect: 3 to add (identity, role assignment, cluster)
terraform apply     # ~5–10 min
az aks show -g rg-aks-demo-dev -n aks-demo-dev --query provisioningState
terraform output

# write a local kubeconfig and verify connectivity
az aks get-credentials -g rg-aks-demo-dev -n aks-demo-dev --file ./kubeconfig --overwrite-existing
KUBECONFIG=./kubeconfig kubectl get nodes      # node should be Ready
```

---

## Phase 5 — Argocd Deployment

- Goal:
  - deploy argocd on aks

- Checkpoint:

```sh
terraform plan    

# Get kubeconfig
az aks get-credentials -g rg-aks-demo-dev -n aks-demo-dev --overwrite-existing

# Retrieve bootstrap admin password
KUBECONFIG=./kubeconfig kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward the UI to localhost:8080
KUBECONFIG=./kubeconfig kubectl -n argocd port-forward svc/argocd-server 8080:443

```

---
