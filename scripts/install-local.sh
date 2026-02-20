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

# Ensure script is run from project root
if [ ! -f "scripts/install-local.sh" ]; then
    echo -e "${RED}Error: Please run this script from the project root directory${NC}"
    echo "  cd /path/to/sanaggar-crypto-data-platform && ./scripts/install-local.sh"
    exit 1
fi

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

# Force delete if cluster or leftover containers exist
if k3d cluster list | grep -q "crypto-platform" || docker ps -a --filter name=k3d-crypto-platform -q 2>/dev/null | grep -q .; then
    echo "  Cluster already exists, deleting..."
    k3d cluster delete crypto-platform 2>/dev/null || true
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

# Git secret for Airflow (if provided and not a placeholder)
if [ -n "$GITHUB_TOKEN" ] && ! echo "$GITHUB_TOKEN" | grep -q "your_.*_here"; then
    kubectl create secret generic airflow-git-secret \
        --namespace airflow \
        --from-literal=GITSYNC_USERNAME=$GITHUB_USERNAME \
        --from-literal=GITSYNC_PASSWORD=$GITHUB_TOKEN \
        --from-literal=GIT_SYNC_USERNAME=$GITHUB_USERNAME \
        --from-literal=GIT_SYNC_PASSWORD=$GITHUB_TOKEN \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# API secret (must include both db_user and db_password as referenced by deployment.yaml)
kubectl create secret generic crypto-api-secret \
    --namespace default \
    --from-literal=db_user=$POSTGRES_USER \
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

# Create Fernet key for encryption (auto-generate if not set or placeholder)
if [ -z "$AIRFLOW_FERNET_KEY" ] || echo "$AIRFLOW_FERNET_KEY" | grep -q "your_.*_here"; then
    FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>/dev/null || openssl rand -base64 32)
else
    FERNET_KEY=$AIRFLOW_FERNET_KEY
fi
kubectl create secret generic airflow-fernet-key \
    --namespace airflow \
    --from-literal=fernet-key="$FERNET_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

# URL-encode password for use in connection string (special chars like !@#$ break URIs)
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${POSTGRES_PASSWORD}', safe=''))")

# Create metadata database connection secret (required by Helm chart)
kubectl create secret generic airflow-metadata-secret \
    --namespace airflow \
    --from-literal=connection="postgresql://${POSTGRES_USER}:${ENCODED_PASSWORD}@postgres.database.svc.cluster.local:5432/airflow_metadata" \
    --dry-run=client -o yaml | kubectl apply -f -

# Run database migrations manually before Helm install
# (The Helm hook for migrations can fail silently on some chart versions)
# Must set FAB auth manager to trigger provider-specific migrations (User/Role tables)
echo "  Running Airflow database migrations..."
AIRFLOW_DB_URI="postgresql://${POSTGRES_USER}:${ENCODED_PASSWORD}@postgres.database.svc.cluster.local:5432/airflow_metadata"

# Pre-pull the Airflow image to avoid kubectl run timeout during first pull
echo "  Pulling Airflow image (this may take a few minutes on first run)..."
kubectl run airflow-image-pull \
    --rm -i --restart=Never \
    --namespace airflow \
    --pod-running-timeout=5m \
    --image=apache/airflow:3.1.7 \
    --command -- echo "Image ready"

kubectl run airflow-db-migrate \
    --rm -i --restart=Never \
    --namespace airflow \
    --pod-running-timeout=5m \
    --image=apache/airflow:3.1.7 \
    --env="AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=${AIRFLOW_DB_URI}" \
    --env="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager" \
    -- airflow db migrate

echo "  ✓ Database migrations complete"

# Build Helm extra args for gitSync (only if GITHUB_TOKEN is provided)
HELM_GITSYNC_ARGS=""
if [ -n "$GITHUB_TOKEN" ] && ! echo "$GITHUB_TOKEN" | grep -q "your_.*_here"; then
    echo "  Git credentials found, enabling DAG sync from GitHub..."
    HELM_GITSYNC_ARGS="\
        --set dags.gitSync.enabled=true \
        --set dags.gitSync.repo=https://github.com/sanaggar/sanaggar-crypto-data-platform.git \
        --set dags.gitSync.branch=main \
        --set dags.gitSync.subPath=dags \
        --set dags.gitSync.wait=60 \
        --set dags.gitSync.credentialsSecret=airflow-git-secret"
else
    echo "  No GITHUB_TOKEN set, DAGs will be loaded manually..."
    HELM_GITSYNC_ARGS="--set dags.gitSync.enabled=false"
fi

helm upgrade --install airflow apache-airflow/airflow \
    --namespace airflow \
    --values manifests/base/airflow/values.yaml \
    --set fernetKeySecretName=airflow-fernet-key \
    --set migrateDatabaseJob.enabled=false \
    --set createUserJob.enabled=false \
    $HELM_GITSYNC_ARGS \
    --timeout 10m \
    --wait

# If no gitSync, copy DAGs directly into the scheduler pod
if { [ -z "$GITHUB_TOKEN" ] || echo "$GITHUB_TOKEN" | grep -q "your_.*_here"; } && [ -d "dags" ]; then
    echo "  Copying local DAGs into Airflow scheduler..."
    SCHEDULER_POD=$(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}')
    kubectl cp dags/ airflow/$SCHEDULER_POD:/opt/airflow/dags/
fi

# Create Airflow admin user
echo "  Creating Airflow admin user..."
kubectl exec -n airflow deployment/airflow-scheduler -- airflow users create \
    --username "${AIRFLOW_ADMIN_USER:-admin}" \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password "$AIRFLOW_ADMIN_PASSWORD" 2>/dev/null || true

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
# Setup dbt and run models
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Post-install] Setting up dbt...${NC}"

mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml <<DBTEOF
crypto_transform:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5432
      user: ${POSTGRES_USER}
      password: ${POSTGRES_PASSWORD}
      dbname: ${POSTGRES_DB}
      schema: public
      threads: 4
DBTEOF
echo "  ✓ dbt profile generated (~/.dbt/profiles.yml)"

if command -v dbt &> /dev/null; then
    echo "  Running dbt models (requires port-forward to postgres)..."
    kubectl port-forward svc/postgres 5432:5432 -n database &>/dev/null &
    PF_PID=$!
    sleep 2
    (cd dbt/crypto_transform && dbt run) || echo -e "${YELLOW}  dbt run failed - you can retry manually after port-forwarding postgres${NC}"
    kill $PF_PID 2>/dev/null || true
else
    echo -e "${YELLOW}  dbt not installed, skipping. Run manually:${NC}"
    echo "    kubectl port-forward svc/postgres 5432:5432 -n database &"
    echo "    cd dbt/crypto_transform && dbt run"
fi

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
echo "  Airflow:  kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow"
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
echo "  1. Trigger the DAG in Airflow to ingest data"
echo "  2. Configure Grafana data source (PostgreSQL)"
echo
