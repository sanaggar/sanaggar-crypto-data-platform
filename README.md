# Crypto Data Platform

A production-grade data platform for cryptocurrency market data, demonstrating modern data engineering practices.

## 🎯 Project Overview

This project builds a complete data platform that ingests, transforms, and serves cryptocurrency market data. It showcases skills in data engineering, platform engineering, and cloud infrastructure.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│    SOURCES              INGESTION            TRANSFORMATION                 │
│   ┌─────────┐          ┌─────────┐          ┌─────────┐                     │
│   │CoinGecko│──Batch──▶│ Airflow │─────────▶│   dbt  │                     │
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
│                              ▼                             ▼                             ▼    │
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
- [ ] K3d cluster + ArgoCD
- [ ] PostgreSQL deployment
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
├── infrastructure/
│   ├── docker/
│   ├── k3d/
│   ├── terraform/
│   └── argocd/
│
├── manifests/
│   ├── base/
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

> ⚠️ **Note**: Setup scripts will be available once Phase 1 is complete.

### Prerequisites
- Docker
- kubectl
- Git

### Local Setup (Coming Soon)
```bash
# Clone the repository
git clone https://github.com/sanaggar/sanaggar-crypto-data-platform.git
cd sanaggar-crypto-data-platform

# Run setup script
./scripts/setup-local.sh
```

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

## 👤 Author

**sanaggar**
