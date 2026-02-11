# Architecture

## Overview

This document describes the architecture of the Crypto Data Platform.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CRYPTO DATA PLATFORM                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         DATA SOURCES                                │    │
│  │                                                                     │    │
│  │    ┌──────────────┐              ┌──────────────┐                   │    │
│  │    │  CoinGecko   │              │    Fake      │                   │    │
│  │    │    API       │              │   Events     │                   │    │
│  │    │   (Batch)    │              │  (Stream)    │                   │    │
│  │    └──────┬───────┘              └──────┬───────┘                   │    │
│  └───────────┼─────────────────────────────┼───────────────────────────┘    │
│              │                             │                                │
│              ▼                                           ▼                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       INGESTION LAYER                               │    │
│  │                                                                     │    │
│  │    ┌──────────────┐              ┌──────────────┐                   │    │
│  │    │   Python     │              │    Kafka     │                   │    │
│  │    │  Ingestion   │              │   Topics     │                   │    │
│  │    │   Script     │              │              │                   │    │
│  │    └──────┬───────┘              └──────┬───────┘                   │    │
│  └───────────┼─────────────────────────────┼───────────────────────────┘    │
│              │                             │                                │
│              ▼                                           ▼                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       STORAGE LAYER                                 │    │
│  │                                                                     │    │
│  │                      ┌──────────────┐                               │    │
│  │                      │  PostgreSQL  │                               │    │
│  │                      │              │                               │    │
│  │    ┌─────────────────┼──────────────┼─────────────────┐             │    │
│  │    │                 │              │                 │             │    │
│  │    │  raw schema     │ staging      │  mart schema    │             │    │
│  │    │  (raw data)     │ schema       │  (analytics)    │             │    │
│  │    │                 │ (cleaned)    │                 │             │    │
│  │    └─────────────────┴──────────────┴─────────────────┘             │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                        │
│                                    ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    TRANSFORMATION LAYER                             │    │
│  │                                                                     │    │
│  │    ┌──────────────┐         ┌──────────────┐                        │    │
│  │    │     dbt      │────────▶│    Great     │                       │    │
│  │    │   Models     │         │ Expectations │                        │    │
│  │    └──────────────┘         └──────────────┘                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                        │
│                                    ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    ORCHESTRATION LAYER                              │    │
│  │                                                                     │    │
│  │                      ┌──────────────┐                               │    │
│  │                      │   Airflow    │                               │    │
│  │                      │    DAGs      │                               │    │
│  │                      └──────────────┘                               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                        │
│                                    ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       SERVING LAYER                                 │    │
│  │                                                                     │    │
│  │    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐         │    │
│  │    │   FastAPI    │    │  Streamlit   │    │   Grafana    │         │    │
│  │    │    (REST)    │    │ (Dashboard)  │    │  (Metrics)   │         │    │
│  │    └──────────────┘    └──────────────┘    └──────────────┘         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      INFRASTRUCTURE                                 │    │
│  │                                                                     │    │
│  │    Docker │ Kubernetes (K3d/GKE) │ ArgoCD │ Terraform │ GitHub CI   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      OBSERVABILITY                                  │    │
│  │                                                                     │    │
│  │              Prometheus (metrics) │ Grafana (dashboards)            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Batch Flow (Daily)
1. Airflow triggers daily at 00:00 UTC
2. Python script fetches data from CoinGecko API
3. Raw data stored in `raw` schema
4. dbt transforms: raw → staging → mart
5. Great Expectations validates data quality
6. Data available via API and dashboard

### Streaming Flow (Real-time)
1. Producer fetches prices every 30 seconds
2. Events published to Kafka topic
3. Consumer writes to PostgreSQL
4. Alerts triggered if thresholds exceeded

## Schemas

### Raw Schema
- `raw_prices`: Raw price data from API
- `raw_market_data`: Market cap, volume, etc.

### Staging Schema
- `stg_prices`: Cleaned, typed price data
- `stg_market_data`: Cleaned market data

### Mart Schema
- `mart_crypto_performance`: Performance metrics
- `mart_market_overview`: Market statistics
- `mart_alerts`: Price alerts

## Technology Choices

See [ADR documents](adr/) for detailed decision records.
