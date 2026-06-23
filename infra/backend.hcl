# Usage: terraform -chdir=infra init -backend-config=backend.hcl
bucket       = "simonangelfong-terraform-backend"
key          = "tf-aks-demo/de/terraform.tfstate"
region       = "ca-central-1"
encrypt      = true
use_lockfile = true
