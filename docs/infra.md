# Infrastructure

[Back](../README.md)

- [Infrastructure](#infrastructure)
  - [Provision Infrastructures with Terraform](#provision-infrastructures-with-terraform)
  - [Access AKS via kubectl](#access-aks-via-kubectl)

---

## Provision Infrastructures with Terraform

```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve

terraform -chdir=infra destroy -auto-approve
```

---

## Access AKS via kubectl

```sh
az login

SUB_ID=$(az account show --query id --output tsv) && echo $SUB_ID
az account set --subscription $SUB_ID

RG_NAME="rg-aks-demo-dev"
AKS_NAME="aks-demo-dev"

az aks get-credentials -g $RG_NAME -n $AKS_NAME --file ./kubeconfig --overwrite-existing
KUBECONFIG=./kubeconfig kubectl get nodes      # node should be Ready

kubectl get node
# NAME                              STATUS   ROLES    AGE     VERSION
# aks-general-21123181-vmss000000   Ready    <none>   3m50s   v1.35.5
```
