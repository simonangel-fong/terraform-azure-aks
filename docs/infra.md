```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt
terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve

terraform -chdir=infra destroy -auto-approve
```

```sh
az login

SUB_ID=$(az account show --query id --output tsv) && echo $SUB_ID
az account set --subscription $SUB_ID

RG_NAME="rg-aks-demo-dev"
AKS_NAME="aks-demo-dev"

az aks get-credentials --name $AKS_NAME --resource-group $RG_NAME

az aks get-credentials --resource-group "rg-aks-demo-dev" --name "aks-demo-dev"

kubectl get node
# NAME                              STATUS   ROLES    AGE   VERSION
# aks-general-87655435-vmss000000   Ready    <none>   11m   v1.35.5
```
