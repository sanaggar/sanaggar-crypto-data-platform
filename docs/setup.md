# Setup Guide

## Prerequisites

Before starting, ensure you have the following installed:

- **Docker** (v20.10+)
- **kubectl** (v1.25+)
- **Git**
- **Python 3.10+** (for local development)

## Local Development Setup

### 1. Clone the Repository

```bash
git clone https://github.com/sanaggar/sanaggar-crypto-data-platform.git
cd sanaggar-crypto-data-platform
```

### 2. Run Setup Script

The setup script will:
- Install K3d (if not present)
- Create a Kubernetes cluster
- Deploy ArgoCD
- Deploy all platform components

```bash
chmod +x scripts/setup-local.sh
./scripts/setup-local.sh
```

### 3. Verify Installation

```bash
# Check cluster is running
kubectl get nodes

# Check all pods are running
kubectl get pods -A

# Check ArgoCD applications
kubectl get applications -n argocd
```

### 4. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | http://localhost:8080 | admin / (see below) |
| Airflow | http://localhost:8081 | admin / admin |
| API | http://localhost:8000 | - |
| Dashboard | http://localhost:8501 | - |
| Grafana | http://localhost:3000 | admin / admin |

#### Get ArgoCD Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## Manual Setup (Step by Step)

If you prefer to set up components manually:

### 1. Create K3d Cluster

```bash
k3d cluster create crypto-platform \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer" \
  --agents 2
```

### 2. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Deploy Applications

```bash
kubectl apply -f manifests/base/
```

## Cloud Setup (GCP)

See Phase 3 documentation for GCP deployment instructions.

## Troubleshooting

### Cluster won't start
```bash
# Check Docker is running
docker ps

# Remove existing cluster and recreate
k3d cluster delete crypto-platform
k3d cluster create crypto-platform
```

### Pods stuck in Pending
```bash
# Check events
kubectl get events --sort-by='.lastTimestamp'

# Check node resources
kubectl describe nodes
```

### ArgoCD sync failed
```bash
# Check application status
kubectl get applications -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server
```
