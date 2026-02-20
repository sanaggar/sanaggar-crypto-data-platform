#!/bin/bash
# =============================================================================
# CRYPTO DATA PLATFORM - GKE Installation Script (Personal Use)
# =============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure script is run from project root
if [ ! -f "scripts/install-gke.sh" ]; then
    echo -e "${RED}Error: Please run this script from the project root directory${NC}"
    exit 1
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Crypto Data Platform - GKE Install    ${NC}"
echo -e "${GREEN}=========================================${NC}"

# Load environment
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi
source .env

# Validate required variables
required_vars=("POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB" "AIRFLOW_ADMIN_PASSWORD" "GRAFANA_ADMIN_PASSWORD" "GITHUB_USERNAME" "GITHUB_TOKEN")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ] || echo "${!var}" | grep -q "your_.*_here"; then
        echo -e "${RED}Error: $var is not set in .env${NC}"
        exit 1
    fi
done

# 1. Terraform
echo -e "${YELLOW}[1/7] Creating GKE cluster...${NC}"
cd terraform
terraform init
terraform apply -auto-approve
cd ..

# 2. Configure kubectl
echo -e "${YELLOW}[2/7] Configuring kubectl...${NC}"
gcloud container clusters get-credentials crypto-platform-cluster \
    --zone europe-west1-b

# 3. Namespaces
echo -e "${YELLOW}[3/7] Creating namespaces...${NC}"
kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace airflow --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 4. Secrets
echo -e "${YELLOW}[4/7] Creating secrets...${NC}"

kubectl create secret generic postgres-secret -n database \
    --from-literal=POSTGRES_USER=$POSTGRES_USER \
    --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    --from-literal=POSTGRES_DB=$POSTGRES_DB \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic crypto-api-secret -n default \
    --from-literal=db_user=$POSTGRES_USER \
    --from-literal=db_password=$POSTGRES_PASSWORD \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic airflow-git-secret -n airflow \
    --from-literal=GITSYNC_USERNAME=$GITHUB_USERNAME \
    --from-literal=GITSYNC_PASSWORD=$GITHUB_TOKEN \
    --from-literal=GIT_SYNC_USERNAME=$GITHUB_USERNAME \
    --from-literal=GIT_SYNC_PASSWORD=$GITHUB_TOKEN \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic airflow-webserver-secret -n airflow \
    --from-literal=webserver-secret-key=$(openssl rand -hex 32) \
    --dry-run=client -o yaml | kubectl apply -f -

# Fernet key
if [ -z "$AIRFLOW_FERNET_KEY" ] || echo "$AIRFLOW_FERNET_KEY" | grep -q "your_.*_here"; then
    FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>/dev/null || openssl rand -base64 32)
else
    FERNET_KEY=$AIRFLOW_FERNET_KEY
fi
kubectl create secret generic airflow-fernet-key -n airflow \
    --from-literal=fernet-key="$FERNET_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

# URL-encode password for connection string
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${POSTGRES_PASSWORD}', safe=''))")

kubectl create secret generic airflow-metadata-secret -n airflow \
    --from-literal=connection="postgresql://${POSTGRES_USER}:${ENCODED_PASSWORD}@postgres.database.svc.cluster.local:5432/airflow_metadata" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secrets created"

# 5. PostgreSQL
echo -e "${YELLOW}[5/7] Deploying PostgreSQL...${NC}"
kubectl apply -f manifests/gke/postgres/pvc.yaml
kubectl apply -f manifests/gke/postgres/statefulset.yaml
kubectl apply -f manifests/base/postgres/service.yaml
kubectl wait --for=condition=ready pod/postgres-0 -n database --timeout=300s
sleep 10

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
kubectl exec -n database postgres-0 -- psql -U $POSTGRES_USER -d postgres -c "CREATE DATABASE airflow_metadata;" 2>/dev/null || true

echo "  ✓ PostgreSQL deployed"

# 6. Airflow
echo -e "${YELLOW}[6/7] Deploying Airflow...${NC}"
helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo update

# Run database migrations (core + FAB auth) before Helm install
echo "  Running Airflow database migrations..."
AIRFLOW_DB_URI="postgresql://${POSTGRES_USER}:${ENCODED_PASSWORD}@postgres.database.svc.cluster.local:5432/airflow_metadata"
kubectl run airflow-db-migrate \
    --rm -i --restart=Never \
    --namespace airflow \
    --pod-running-timeout=5m \
    --image=apache/airflow:3.1.7 \
    --env="AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=${AIRFLOW_DB_URI}" \
    --env="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager" \
    -- airflow db migrate

echo "  ✓ Database migrations complete"

helm upgrade --install airflow apache-airflow/airflow \
    -n airflow \
    --values manifests/base/airflow/values.yaml \
    --set fernetKeySecretName=airflow-fernet-key \
    --set migrateDatabaseJob.enabled=false \
    --set createUserJob.enabled=false \
    --set dags.gitSync.enabled=true \
    --set dags.gitSync.repo=https://github.com/sanaggar/sanaggar-crypto-data-platform.git \
    --set dags.gitSync.branch=main \
    --set dags.gitSync.subPath=dags \
    --set dags.gitSync.wait=60 \
    --set dags.gitSync.credentialsSecret=airflow-git-secret \
    --timeout 15m \
    --wait

# Create admin user
echo "  Creating Airflow admin user..."
kubectl exec -n airflow deployment/airflow-scheduler -- airflow users create \
    --username "${AIRFLOW_ADMIN_USER:-admin}" \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password "$AIRFLOW_ADMIN_PASSWORD" 2>/dev/null || true

# Create PostgreSQL connection
kubectl exec -n airflow deployment/airflow-scheduler -- airflow connections add postgres_crypto \
    --conn-type postgres \
    --conn-host postgres.database.svc.cluster.local \
    --conn-port 5432 \
    --conn-login $POSTGRES_USER \
    --conn-password $POSTGRES_PASSWORD \
    --conn-schema $POSTGRES_DB 2>/dev/null || true

echo "  ✓ Airflow deployed"

# 7. API + Grafana
echo -e "${YELLOW}[7/7] Deploying API and Grafana...${NC}"
docker build -t crypto-api:latest ./api/
docker tag crypto-api:latest gcr.io/crypto-data-platform-487716/crypto-api:latest
docker push gcr.io/crypto-data-platform-487716/crypto-api:latest

kubectl apply -f manifests/gke/api/deployment.yaml
kubectl apply -f manifests/gke/api/service.yaml

helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm upgrade --install grafana grafana/grafana -n monitoring \
    --set adminPassword=$GRAFANA_ADMIN_PASSWORD --set persistence.enabled=false

echo "  ✓ API and Grafana deployed"

# Post-install: dbt
echo -e "${YELLOW}[Post-install] Setting up dbt...${NC}"
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml <<DBTEOF
crypto_transform:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5433
      user: ${POSTGRES_USER}
      password: ${POSTGRES_PASSWORD}
      dbname: ${POSTGRES_DB}
      schema: public
      threads: 4
DBTEOF
echo "  ✓ dbt profile generated (~/.dbt/profiles.yml)"

if command -v dbt &> /dev/null; then
    echo "  Running dbt models..."
    kubectl port-forward svc/postgres 5433:5432 -n database &>/dev/null &
    PF_PID=$!
    sleep 3
    (cd dbt/crypto_transform && dbt run) || echo -e "${YELLOW}  dbt run failed - retry manually after port-forwarding postgres${NC}"
    kill $PF_PID 2>/dev/null || true
else
    echo -e "${YELLOW}  dbt not installed, skipping. Run manually:${NC}"
    echo "    kubectl port-forward svc/postgres 5433:5432 -n database &"
    echo "    cd dbt/crypto_transform && dbt run"
fi

echo
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  GKE Installation Complete!            ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo "Access:"
echo "  Airflow: kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow"
echo "           http://localhost:8080 (user: admin / password: from .env)"
echo "  Grafana: kubectl port-forward svc/grafana 3000:80 -n monitoring"
echo "           http://localhost:3000 (user: admin / password: from .env)"
echo "  API:     kubectl port-forward svc/crypto-api 8001:8000"
echo "           http://localhost:8001/docs"
echo
echo "Next steps:"
echo "  1. Trigger the DAG in Airflow to ingest data"
echo "  2. Configure Grafana data source (PostgreSQL)"
echo
