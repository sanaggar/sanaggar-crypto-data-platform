# Crypto Data Platform

A production-grade data platform for cryptocurrency market data, demonstrating modern data engineering practices.

## 🎯 Project Overview

This project builds a complete data platform that ingests, transforms, and serves cryptocurrency market data. It showcases skills in data engineering, platform engineering, and cloud infrastructure.
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│    SOURCES              INGESTION            TRANSFORMATION                 │
│   ┌─────────┐          ┌─────────┐          ┌─────────┐                     │
│   │CoinGecko│──Batch──▶│ Airflow │─────────▶│   dbt   │                     │
│   │  (API)  │          │  (DAGs) │          │ (models)│                     │
│   └─────────┘          └─────────┘          └─────────┘                     │
│                              │                    │                         │
│   ┌─────────┐          ┌─────────┐                │                         │
│   │  Price  │─Stream──▶│  Kafka  │────────────────┤                         │
│   │ Events  │          │(events) │                │                         │
│   └─────────┘          └─────────┘                ▼                         │
│                                            ┌─────────────┐                  │
│                                            │ PostgreSQL  │                  │
│                                            │ (warehouse) │                  │
│                                            └─────────────┘                  │
│                                                   │                         │
│                              ┌────────────────────┼────────────────────┐    │
│                              │                    │                    │    │
│                              ▼                    ▼                    ▼    │
│                        ┌─────────┐          ┌─────────┐          ┌───────┐  │
│                        │ FastAPI │          │Streamlit│          │Grafana│  │
│                        │  (REST) │          │(dashboard)         │(metrics) │
│                        └─────────┘          └─────────┘          └───────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 📊 Data Sources

- **CoinGecko API** (Free tier)
  - Historical prices (BTC, ETH, SOL, and top cryptocurrencies)
  - Market cap and 24h volume
  - Top 100 cryptocurrencies ranking

## 🛠️ Tech Stack

### Data Engineering
| Tool                   | Purpose                |
|------------------------|------------------------|
| **Apache Airflow**     | Workflow orchestration |
| **dbt**                | Data transformation    |
| **Apache Kafka**       | Real-time streaming    |
| **Great Expectations** | Data quality           |
| **PostgreSQL**         | Data warehouse         |

### Infrastructure
| Tool                     | Purpose                 |
|--------------------------|-------------------------|
| **Docker**               | Containerization        |
| **Kubernetes (K3d/GKE)** | Container orchestration |
| **ArgoCD**               | GitOps deployment       |
| **Terraform**            | Infrastructure as Code  |
| **GitHub Actions**       | CI/CD pipelines         |

### Observability
| Tool           | Purpose               |
|----------------|-----------------------|
| **Prometheus** | Metrics collection    |
| **Grafana**    | Dashboards & alerting |

### Serving Layer
| Tool          | Purpose               |
|---------------|-----------------------|
| **FastAPI**   | REST API              |
| **Streamlit** | Interactive dashboard |

### Languages
- Python
- SQL
- YAML
- Bash
- HCL (Terraform)

## 🚀 Project Phases

### Phase 1: Batch Pipeline (Local) ⏳ In Progress
- [x] Project setup and documentation
- [x] K3d cluster + ArgoCD
- [x] PostgreSQL deployment
- [ ] Data ingestion from CoinGecko
- [ ] dbt transformations
- [ ] Airflow orchestration
- [ ] FastAPI serving layer

### Phase 2: Streaming + Quality 📋 Planned
- [ ] Apache Kafka deployment
- [ ] Real-time price streaming
- [ ] Great Expectations integration
- [ ] Prometheus + Grafana monitoring
- [ ] Streamlit dashboard

### Phase 3: Cloud Migration 📋 Planned
- [ ] Terraform GCP infrastructure
- [ ] GKE deployment
- [ ] GitHub Actions CI/CD
- [ ] Production documentation

## 📁 Project Structure
```
sanaggar-crypto-data-platform/
│
├── README.md
├── docs/
│   ├── architecture.md
│   └── setup.md
│
├── manifests/
│   ├── base/
│   │   ├── argocd/
│   │   │   └── ingress.yaml
│   │   ├── postgres/
│   │   │   ├── namespace.yaml
│   │   │   ├── pvc.yaml
│   │   │   ├── statefulset.yaml
│   │   │   ├── service.yaml
│   │   │   ├── secret.yaml.example
│   │   │   └── secret.yaml          # NOT IN GIT - create from example
│   │   ├── airflow/
│   │   │   ├── values.yaml
│   │   │   ├── secret.yaml.example
│   │   │   ├── secret.yaml          # NOT IN GIT - create from example
│   │   │   ├── webserver-secret.yaml.example
│   │   │   └── webserver-secret.yaml # NOT IN GIT - create from example
│   │   └── test-app/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   └── overlays/
│
├── pipelines/
│   ├── ingestion/
│   ├── dbt/
│   └── quality/
│
├── apps/
│   ├── api/
│   └── dashboard/
│
├── airflow/
│   └── dags/
│
├── .github/
│   └── workflows/
│
├── scripts/
│
└── tests/
```

## 🏃 Quick Start

### Prerequisites
- Docker
- kubectl
- K3d
- Helm

### 1. Clone and Setup Cluster
```bash
# Clone the repository
git clone https://github.com/sanaggar/sanaggar-crypto-data-platform.git
cd sanaggar-crypto-data-platform

# Create K3d cluster
k3d cluster create crypto-platform \
  --servers 1 \
  --agents 2 \
  --port "8081:80@loadbalancer" \
  --port "8443:443@loadbalancer" \
  --port "5432:5432@loadbalancer"
```

### 2. Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Configure ArgoCD for HTTP (dev only)
kubectl edit configmap argocd-cmd-params-cm -n argocd
# Add under data:
#   server.insecure: "true"

kubectl rollout restart deployment argocd-server -n argocd

# Apply ingress
kubectl apply -f manifests/base/argocd/ingress.yaml

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access ArgoCD at: http://localhost:8081

### 3. Configure Secrets (⚠️ IMPORTANT)

**Secrets are NOT stored in Git for security. You must create them manually.**

#### PostgreSQL Secret
```bash
# Copy the example file
cp manifests/base/postgres/secret.yaml.example manifests/base/postgres/secret.yaml

# Edit with your credentials
nano manifests/base/postgres/secret.yaml
```

Example content:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: database
type: Opaque
stringData:
  POSTGRES_USER: your_username
  POSTGRES_PASSWORD: your_secure_password
  POSTGRES_DB: crypto_data
```

#### Airflow Secrets
```bash
# Copy the example files
cp manifests/base/airflow/secret.yaml.example manifests/base/airflow/secret.yaml
cp manifests/base/airflow/webserver-secret.yaml.example manifests/base/airflow/webserver-secret.yaml

# Edit with your credentials
nano manifests/base/airflow/secret.yaml
nano manifests/base/airflow/webserver-secret.yaml
```

Airflow metadata secret (`secret.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: airflow-metadata-secret
  namespace: airflow
type: Opaque
stringData:
  connection: "postgresql://YOUR_USER:YOUR_PASSWORD@postgres.database.svc.cluster.local:5432/airflow_metadata"
```

Webserver secret (`webserver-secret.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: airflow-webserver-secret
  namespace: airflow
type: Opaque
stringData:
  AIRFLOW__WEBSERVER__SECRET_KEY: "your-random-secret-key-here"
```

### 4. Deploy PostgreSQL
```bash
# Create namespace and apply secret
kubectl create namespace database
kubectl apply -f manifests/base/postgres/secret.yaml

# Connect repo to ArgoCD (replace with your GitHub token)
argocd repo add https://github.com/sanaggar/sanaggar-crypto-data-platform.git \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_GITHUB_TOKEN

# Create ArgoCD application
argocd app create postgres \
  --repo https://github.com/sanaggar/sanaggar-crypto-data-platform.git \
  --path manifests/base/postgres \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace database \
  --sync-policy automated

# Verify
kubectl get pods -n database
```

### 5. Setup PostgreSQL Schemas
```bash
# Connect to PostgreSQL
kubectl exec -it postgres-0 -n database -- psql -U YOUR_USER -d crypto_data

# Create schemas
CREATE SCHEMA raw;
CREATE SCHEMA staging;
CREATE SCHEMA mart;

# Create Airflow metadata database
CREATE DATABASE airflow_metadata;

# Verify
\dn
\q
```

### 6. Deploy Airflow
```bash
# Create namespace and apply secrets
kubectl create namespace airflow
kubectl apply -f manifests/base/airflow/secret.yaml
kubectl apply -f manifests/base/airflow/webserver-secret.yaml

# Install with Helm
helm repo add apache-airflow https://airflow.apache.org
helm repo update

helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --values manifests/base/airflow/values.yaml \
  --timeout 15m

# Create admin user (choose your own credentials)
kubectl exec -it deployment/airflow-api-server -n airflow -- \
  airflow users create \
  --username YOUR_USERNAME \
  --firstname YOUR_FIRSTNAME \
  --lastname YOUR_LASTNAME \
  --role Admin \
  --email YOUR_EMAIL \
  --password YOUR_PASSWORD
```

Access Airflow at: http://localhost:8080 (requires port-forward)
```bash
kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow
```

## 🔐 Security Notes

- **Never commit secrets to Git** - All sensitive files are in `.gitignore`
- **Use `.example` files as templates** - Copy and fill with your own values
- **Rotate credentials regularly** - Especially before making repo public
- **Use strong passwords** - Mix of uppercase, lowercase, numbers, and symbols

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [Setup Guide](docs/setup.md)
- [Architecture Decision Records](docs/adr/)

## 🎓 Skills Demonstrated

This project demonstrates proficiency in:

- **Data Engineering**: ETL/ELT pipelines, batch and stream processing
- **Platform Engineering**: Kubernetes, GitOps, containerization
- **Cloud Engineering**: IaC with Terraform, GCP services
- **DevOps**: CI/CD, monitoring, observability
- **Software Engineering**: API design, testing, documentation
- **Security**: Secret management, credential handling

## 👤 Author

**sanaggar**
