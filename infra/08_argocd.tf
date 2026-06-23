# argocd.tf

# ##############################
# ArgoCD Helm release
# ##############################
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.14"

  # Argo CRDs are large; give Helm time to install
  timeout = 600
  wait    = true

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]
}
