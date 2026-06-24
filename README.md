# Terraform Azure AKS + Argo CD (GitOps Demo)

> Provision an AKS cluster with Terraform, bootstrap Argo CD, and let an app-of-apps pattern deploy ingress-nginx and a sample web app from this repo.

![Microsoft Azure](https://custom-icon-badges.demolab.com/badge/Microsoft%20Azure-0089D6?logo=msazure&logoColor=white&style=plastic) ![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white&style=plastic)

---

## Diagram

![diagram](./docs/img/diagram.gif)

---

## How it works

1. `Terraform` creates the `AKS cluster` and installs `Argo CD`.
2. Deploy the **app-of-apps** in `Argo CD`.
3. `Argo CD` reconciles every manifest against the cluster.
4. Pushing changes to trigger `Argo CD` to roll the workloads forward.

---

## Outcome

- **AKS cluster**

![aks](./docs/img/aks.png)

- **Argo CD UI**

![argocd](./docs/img/argocd.png)

- **nginx-demo**

![web](./docs/img/web.png)

---
