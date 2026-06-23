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
├── 01_variables.tf      input variables (Phase 1)
├── 02_locals.tf         derived names, common tags (Phase 1)
├── 03_providers.tf      terraform + azurerm version + provider config (Phase 1)
├── 04_outputs.tf        outputs for argocd/ tier (Phase 5)
├── 05_az_rg.tf          resource group (Phase 2)
├── 06_az_vnet.tf        VNet + subnet (Phase 3)
├── 07_az_node_groups.tf user node pool(s) (Phase 4)
├── 08_az_aks.tf         AKS cluster (Phase 4)
├── 09_argocd.tf         placeholder / handoff marker (Phase 7)
├── terraform.tfvars.example
└── .gitignore           *.tfstate, *.tfvars (except .example), .terraform/
```

Phase-to-file map:

| Phase | Files added                                                                        |
| ----- | ---------------------------------------------------------------------------------- |
| 1     | `01_variables.tf`, `02_locals.tf`, `03_providers.tf`, `terraform.tfvars.example`, `.gitignore` |
| 2     | `05_az_rg.tf`                                                                      |
| 3     | `06_az_vnet.tf`                                                                    |
| 4     | `07_az_node_groups.tf`, `08_az_aks.tf`                                              |
| 5     | `04_outputs.tf`                                                                    |
| 7     | `09_argocd.tf`                                                                     |

---

## Phase 0 — Prerequisites

Verify before touching code.

- [x] Azure CLI installed: `az version` → **2.87.0**
- [x] Logged in: `az login` → `simonangelfong@gmail.com`
- [x] Subscription selected: `az account show` → `Azure subscription 1` (`adb97c42-2927-4b7d-881d-59fc6c69b886`)
- [x] Terraform ≥ 1.6 installed: `terraform version` → **1.15.2** (1.15.6 available, optional upgrade)
- [x] `kubectl` installed: `kubectl version --client` → **v1.34.1**
- [x] Quota check: B-series vCPUs available in target region (`az vm list-usage -l eastus -o table`) → **4 vCPUs** (Standard BS, Bsv2)

### Quota constraint (must respect in Phase 4)

Total Regional vCPUs and Standard BS Family are both capped at **4** in `eastus`. One `Standard_B2s` = 2 vCPUs.

| Node count | vCPUs used | Headroom     | Verdict                                                                 |
| ---------- | ---------- | ------------ | ----------------------------------------------------------------------- |
| 1          | 2 / 4      | 2 vCPUs free | ✅ safe, allows upgrade surge                                           |
| 2          | 4 / 4      | 0 vCPUs free | ⚠️ exact fit; AKS upgrades (default `max_surge=10%` → +1 node) may fail |

**Decision**: keep `node_count = 1` as the default in `variables.tf`. Request quota increase before scaling.

Decisions captured (from system design):

- Region: `eastus`
- Node SKU: `Standard_B2s`, count **1** (revised from 1–2 due to quota)
- Network: Azure CNI, VNet `10.10.0.0/16`, subnet `10.10.0.0/20`
- State: local backend (note for later migration)
- Subscription ID for `terraform.tfvars`: `adb97c42-2927-4b7d-881d-59fc6c69b886`

---

## Phase 1 — Bootstrap

Goal: get a working Terraform workspace that can talk to Azure. **No Azure resources created yet** — this phase is purely scaffolding so later phases have somewhere to land.

Files to create:

- `01_variables.tf` — input variable declarations only (no resources)
- `02_locals.tf` — derived names and a `common_tags` local merged into every resource later
- `03_providers.tf` — `terraform { required_version, required_providers }` block + `provider "azurerm" { features {} subscription_id = var.subscription_id }`
- `terraform.tfvars.example` — documented sample showing `subscription_id` and any overrides
- `.gitignore` — `*.tfstate*`, `*.tfvars` (but not `*.tfvars.example`), `.terraform/`, `.terraform.lock.hcl` left committed

Variables to declare in `01_variables.tf` (declarations only — resources consume them in later phases):

| Variable                | Type   | Default              | Notes                                    |
| ----------------------- | ------ | -------------------- | ---------------------------------------- |
| `subscription_id`       | string | —                    | Required; from Phase 0                   |
| `location`              | string | `eastus`             |                                          |
| `resource_group_name`   | string | `rg-aks-demo`        |                                          |
| `cluster_name`          | string | `aks-demo`           |                                          |
| `node_count`            | number | `1`                  | Capped by 4 vCPU quota; see Phase 0      |
| `node_vm_size`          | string | `Standard_B2s`       |                                          |
| `vnet_address_space`    | string | `10.10.0.0/16`       |                                          |
| `subnet_address_prefix` | string | `10.10.0.0/20`       |                                          |
| `tags`                  | map    | `{ project = "aks-demo", managed_by = "terraform" }` | Merged into `common_tags` |

Locals in `02_locals.tf`:

- `common_tags` — `merge(var.tags, { environment = "demo" })`
- (extend later as naming conventions need it)

Provider versions in `03_providers.tf`:

- `terraform { required_version = ">= 1.6" }`
- `azurerm ~> 4.0` (latest major)

Checkpoint:

```
cd infra/
terraform init        # downloads azurerm provider
terraform validate    # config is syntactically and semantically valid
terraform plan        # expect: "No changes" — zero resources defined
```

All three must succeed. `terraform plan` showing zero resources confirms the bootstrap is clean and ready for Phase 2.

---

## Phase 2 — Resource Group

Goal: smallest possible resource lands in Azure to prove the provider chain works.

Add `05_az_rg.tf`:

- `azurerm_resource_group.this` — `name = var.resource_group_name`, `location = var.location`, `tags = local.common_tags`

Checkpoint:

```
terraform plan      # expect: 1 to add
terraform apply
az group show -n rg-aks-demo -o table
```

---

## Phase 3 — Networking (VNet + subnet)

Goal: VNet sized for Azure CNI pod IPs.

Add `06_az_vnet.tf`:

- `azurerm_virtual_network.this` — address space `var.vnet_address_space` (`10.10.0.0/16`)
- `azurerm_subnet.aks_nodes` — prefix `var.subnet_address_prefix` (`10.10.0.0/20`, ~4096 IPs for nodes + pods)

Sizing rationale: with Azure CNI, every pod gets an IP from this subnet. `/20` gives headroom for the demo without overcommitting.

Checkpoint:

```
terraform plan      # expect: 2 to add
terraform apply
az network vnet subnet show -g rg-aks-demo --vnet-name <vnet> -n aks-nodes -o table
```

---

## Phase 4 — AKS cluster + node pool

Goal: a minimum-viable AKS cluster on the subnet above. Split across two files so the node pool config is editable without scrolling past the cluster block.

Add `08_az_aks.tf`:

- `azurerm_kubernetes_cluster.this`
  - `default_node_pool` — inline reference to the values declared in `07_az_node_groups.tf` (via locals)
  - `identity { type = "SystemAssigned" }`
  - `network_profile`:
    - `network_plugin = "azure"` (Azure CNI)
    - `service_cidr = "10.20.0.0/16"` (non-overlapping with VNet)
    - `dns_service_ip = "10.20.0.10"`
  - `role_based_access_control_enabled = true`
  - `dns_prefix = var.cluster_name`
  - `tags = local.common_tags`

Add `07_az_node_groups.tf`:

- A `locals` block describing the system node pool: `name = "system"`, `vm_size = var.node_vm_size`, `node_count = var.node_count`, `vnet_subnet_id = azurerm_subnet.aks_nodes.id`
- (Room to add `azurerm_kubernetes_cluster_node_pool` user pools later without touching `08_az_aks.tf`)

Notes:

- Service CIDR must NOT overlap the VNet address space.
- Leave `kubernetes_version` unset → Azure picks current default.

Checkpoint:

```
terraform plan      # expect: 1 to add (cluster)
terraform apply     # ~5–10 min
az aks show -g rg-aks-demo -n aks-demo --query provisioningState
```

---

## Phase 5 — Outputs for the `argocd/` tier

Goal: expose the data `argocd/` needs to authenticate its `kubernetes` and `helm` providers.

Add `04_outputs.tf`:

- `resource_group_name`
- `cluster_name`
- `kube_config_raw` (sensitive) — `azurerm_kubernetes_cluster.this.kube_config_raw`
- `host` (sensitive) — `azurerm_kubernetes_cluster.this.kube_config.0.host`
- `cluster_ca_certificate` (sensitive)
- `client_certificate` (sensitive)
- `client_key` (sensitive)

Why these specific fields: the `argocd/` Terraform will read them via `terraform_remote_state` (or shared tfvars) and pass them directly into provider blocks — no kubeconfig file juggling.

Checkpoint:

```
terraform output
terraform output -raw kube_config_raw > ../kubeconfig
KUBECONFIG=../kubeconfig kubectl get nodes      # node should be Ready
```

---

## Phase 6 — Smoke test

Goal: confirm the cluster is healthy enough to host Argo CD.

Checks:

- [ ] `kubectl get nodes` → 1 node `Ready`
- [ ] `kubectl get pods -A` → kube-system pods all `Running`
- [ ] `kubectl get sc` → default StorageClass present
- [ ] `kubectl auth can-i create namespace` → `yes`

If any fail, stop and diagnose before moving on.

---

## Phase 7 — Handoff to `argocd/`

Add `09_argocd.tf` — a marker file containing only a `data "terraform_remote_state"` reference or a comment block documenting which outputs the `argocd/` tier reads. No resources here; the file exists so the handoff contract is visible in the tree.

The `argocd/` tier consumes `infra/` outputs. Two options, pick during implementation:

**Option A — `terraform_remote_state`**

```hcl
data "terraform_remote_state" "infra" {
  backend = "local"
  config  = { path = "../infra/terraform.tfstate" }
}
```

Pro: no manual copy. Con: couples the two tiers to the state file path.

**Option B — shared tfvars**
Export `infra/` outputs into `argocd/terraform.tfvars` once after apply.
Pro: tiers are loosely coupled. Con: a manual step.

Recommendation: **Option A** for the demo (one less step), Option B noted in README as the production-shaped alternative.

---

## Definition of done

- `terraform apply` in `infra/` is idempotent (second run shows "no changes")
- `kubectl --kubeconfig=./kubeconfig get nodes` returns a Ready node
- All outputs in Phase 5 resolve (non-empty)
- `infra/README.md` documents the apply/destroy commands and the handoff option chosen

---

## Out of scope for `infra/`

- Argo CD, ingress-nginx, monitoring, nginx-demo — all live in `argocd/` and `app/`
- Remote state backend (Azure Storage) — noted for later
- Multiple node pools, autoscaling, spot nodes
- Private cluster, API server authorized IP ranges
- Azure AD integration for cluster RBAC
- Log Analytics / Container Insights
