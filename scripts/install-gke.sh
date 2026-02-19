#!/bin/bash
# =============================================================================
# CRYPTO DATA PLATFORM - GKE Installation Script (Personal Use)
# =============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Crypto Data Platform - GKE Install    ${NC}"
echo -e "${GREEN}=========================================${NC}"

# Load environment
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi
source .env

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
    --from-literal=db_password=$POSTGRES_PASSWORD \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic airflow-git-secret -n airflow \
    --from-literal=GITSYNC_USERNAME=$GITHUB_USERNAME \
    --from-literal=GITSYNC_PASSWORD=$GITHUB_TOKEN \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic airflow-webserver-secret -n airflow \
    --from-literal=webserver-secret-key=$(openssl rand -hex 32) \
    --dry-run=client -o yaml | kubectl apply -f -

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

# 6. Airflow
echo -e "${YELLOW}[6/7] Deploying Airflow...${NC}"
helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo update
helm upgrade --install airflow apache-airflow/airflow \
    -n airflow --values manifests/base/airflow/values.yaml --timeout 15m --wait

kubectl exec -n airflow deployment/airflow-api-server -- airflow connections add postgres_crypto \
    --conn-type postgres \
    --conn-host postgres.database.svc.cluster.local \
    --conn-port 5432 \
    --conn-login $POSTGRES_USER \
    --conn-password $POSTGRES_PASSWORD \
    --conn-schema $POSTGRES_DB 2>/dev/null || true

kubectl exec -n airflow deployment/airflow-api-server -- airflow users create \
    --username admin --firstname Admin --lastname User --role Admin \
    --email admin@example.com --password $AIRFLOW_ADMIN_PASSWORD 2>/dev/null || true

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

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  GKE Installation Complete!            ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo "Access:"
echo "  Airflow: kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow"
echo "  Grafana: kubectl port-forward svc/grafana 3000:80 -n monitoring"
echo "  API:     kubectl port-forward svc/crypto-api 8001:8000"
echo
echo "Don't forget to run dbt:"
echo "  kubectl port-forward svc/postgres 5433:5432 -n database"
echo "  cd dbt/crypto_transform && dbt run --profiles-dir ./profiles"
