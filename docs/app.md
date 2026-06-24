
## Deploy app

```sh
helm lint app/nginx-demo
helm template app/nginx-demo

# install manually into a throwaway namespace
kubectl create ns web
helm install nginx-demo app/nginx-demo -n web
kubectl -n web get pods,svc 
# NAME                              READY   STATUS    RESTARTS   AGE
# pod/nginx-demo-78c4848757-rpgns   1/1     Running   0          6s

# NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
# service/nginx-demo   ClusterIP   10.0.65.98   <none>        80/TCP    7s

# verify the landing page
kubectl -n web port-forward svc/nginx-demo 8081:80
curl http://localhost:8081
# <h1>nginx-demo on AKS</h1>
# <p>Served by Argo CD + local Helm chart.</p>

# tear down before Phase 2
helm uninstall nginx-demo -n web
kubectl delete ns web
```

---

## Confirm LB

```sh
RG_NAME=aks-demo-dev
az network lb list -g $RG_NAME -o table
# Location    Name        ProvisioningState    ResourceGroup    ResourceGuid
# ----------  ----------  -------------------  ---------------  ------------------------------------
# eastus      kubernetes  Succeeded            aks-demo-dev     cb8fbac8-2d2f-44a8-ad00-aa1154d648a6

kubectl get ingress -n web
# NAMESPACE   NAME         CLASS   HOSTS   ADDRESS         PORTS   AGE
# web         nginx-demo   nginx   *       48.194.32.137   80      5m57s

curl http://$(KUBECONFIG=./kubeconfig kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# <h1>nginx-demo on AKS</h1>
# <p>Served by Argo CD + local Helm chart.</p>

kubectl -n argocd get applications
# NAME         SYNC STATUS   HEALTH STATUS
# nginx-demo   Synced        Healthy
```

---

## ArgoCD

```sh
kubectl apply -f argocd/root-app.yaml
```