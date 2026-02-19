#!/bin/bash
# =============================================================================
# CRYPTO DATA PLATFORM - Local Installation Script (K3d)
# =============================================================================
# This script deploys the entire platform locally using K3d
# 
# Prerequisites:
#   - Docker
#   - kubectl
#   - k3d
#   - helm
#
# Usage:
#   cp .env.example .env
#   # Edit .env with your values
#   ./scripts/install-local.sh
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Crypto Data Platform - Installation   ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo

# -----------------------------------------------------------------------------
# Check prerequisites
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/8] Checking prerequisites...${NC}"

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        exit 1
    fi
    echo "  ✓ $1 found"
}

check_command docker
check_command kubectl
check_command k3d
check_command helm

echo

# -----------------------------------------------------------------------------
# Load environment variables
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/8] Loading environment variables...${NC}"

if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create it: cp .env.example .env"
    exit 1
fi

source .env

# Validate required variables
required_vars=("POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB" "AIRFLOW_ADMIN_PASSWORD" "GRAFANA_ADMIN_PASSWORD")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var is not set in .env${NC}"
        exit 1
    fi
done

echo "  ✓ Environment variables loaded"
echo

# -----------------------------------------------------------------------------
# Create K3d cluster
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/8] Creating K3d cluster...${NC}"

if k3d cluster list | grep -q "crypto-platform"; then
    echo "  Cluster already exists, deleting..."
    k3d cluster delete crypto-platform
fi

k3d cluster create crypto-platform \
    -p "8080:80@loadbalancer" \
    -p "8443:443@loadbalancer" \
    --agents 1

echo "  ✓ K3d cluster created"
echo

# -----------------------------------------------------------------------------
# Create namespaces
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/8] Creating namespaces...${NC}"

kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace airflow --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Namespaces created"
echo

# -----------------------------------------------------------------------------
# Create secrets
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[5/8] Creating secrets...${NC}"

# PostgreSQL secret
kubectl create secret generic postgres-secret \
    --namespace database \
    --from-literal=POSTGRES_USER=$POSTGRES_USER \
    --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    --from-literal=POSTGRES_DB=$POSTGRES_DB \
    --dry-run=client -o yaml | kubectl apply -f -

# Airflow secrets
kubectl create secret generic airflow-secret \
    --namespace airflow \
    --from-literal=AIRFLOW_ADMIN_USER=${AIRFLOW_ADMIN_USER:-admin} \
    --from-literal=AIRFLOW_ADMIN_PASSWORD=$AIRFLOW_ADMIN_PASSWORD \
    --dry-run=client -o yaml | kubectl apply -f -

# Git secret for Airflow (if provided)
if [ -n "$GITHUB_TOKEN" ]; then
    kubectl create secret generic airflow-git-secret \
        --namespace airflow \
        --from-literal=GITSYNC_USERNAME=$GITHUB_USERNAME \
        --from-literal=GITSYNC_PASSWORD=$GITHUB_TOKEN \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# API secret
kubectl create secret generic crypto-api-secret \
    --namespace default \
    --from-literal=db_password=$POSTGRES_PASSWORD \
    --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secrets created"
echo

# -----------------------------------------------------------------------------
# Deploy PostgreSQL
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[6/8] Deploying PostgreSQL...${NC}"

kubectl apply -f manifests/base/postgres/pvc.yaml
kubectl apply -f manifests/base/postgres/statefulset.yaml
kubectl apply -f manifests/base/postgres/service.yaml

echo "  Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod/postgres-0 -n database --timeout=120s

# Initialize database schemas
echo "  Initializing database schemas..."
sleep 5
kubectl exec -n database postgres-0 -- psql -U $POSTGRES_USER -d $POSTGRES_DB -c "
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE TABLE IF NOT EXISTS raw.crypto_prices (
    id SERIAL PRIMARY KEY,
    coin_id VARCHAR(100) NOT NULL,
    data JSONB NOT NULL,
    ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);"

# Create airflow database
kubectl exec -n database postgres-0 -- psql -U $POSTGRES_USER -d postgres -c "CREATE DATABASE airflow_metadata;" 2>/dev/null || true

echo "  ✓ PostgreSQL deployed"
echo

# -----------------------------------------------------------------------------
# Deploy Airflow
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[7/8] Deploying Airflow...${NC}"

helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo update

# Create webserver secret key
kubectl create secret generic airflow-webserver-secret \
    --namespace airflow \
    --from-literal=webserver-secret-key=$(openssl rand -hex 32) \
    --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install airflow apache-airflow/airflow \
    --namespace airflow \
    --values manifests/base/airflow/values.yaml \
    --timeout 10m \
    --wait

# Create Airflow PostgreSQL connection
kubectl exec -n airflow deployment/airflow-scheduler -- airflow connections add postgres_crypto \
    --conn-type postgres \
    --conn-host postgres.database.svc.cluster.local \
    --conn-port 5432 \
    --conn-login $POSTGRES_USER \
    --conn-password $POSTGRES_PASSWORD \
    --conn-schema $POSTGRES_DB 2>/dev/null || true

echo "  ✓ Airflow deployed"
echo

# -----------------------------------------------------------------------------
# Deploy API and Grafana
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[8/8] Deploying API and Grafana...${NC}"

# Build and load API image
docker build -t crypto-api:latest ./api/
k3d image import crypto-api:latest -c crypto-platform

# Deploy API
kubectl apply -f manifests/base/api/deployment.yaml
kubectl apply -f manifests/base/api/service.yaml

# Deploy Grafana
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm upgrade --install grafana grafana/grafana \
    --namespace monitoring \
    --set adminPassword=$GRAFANA_ADMIN_PASSWORD \
    --set persistence.enabled=false

echo "  ✓ API and Grafana deployed"
echo

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Installation Complete!                ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo "Access your services:"
echo
echo "  Airflow:  kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow"
echo "            http://localhost:8080"
echo "            User: admin / Password: (from .env)"
echo
echo "  Grafana:  kubectl port-forward svc/grafana 3000:80 -n monitoring"
echo "            http://localhost:3000"
echo "            User: admin / Password: (from .env)"
echo
echo "  API:      kubectl port-forward svc/crypto-api 8001:8000"
echo "            http://localhost:8001/docs"
echo
echo "Next steps:"
echo "  1. Run dbt to create views: cd dbt/crypto_transform && dbt run"
echo "  2. Trigger the DAG in Airflow to ingest data"
echo "  3. Configure Grafana data source (PostgreSQL)"
echo
