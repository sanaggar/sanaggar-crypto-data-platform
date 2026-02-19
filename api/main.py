"""
Crypto Data Platform API
Exposes cryptocurrency data from PostgreSQL via REST endpoints.
"""

from fastapi import FastAPI, HTTPException
from contextlib import asynccontextmanager
import psycopg2
from psycopg2.extras import RealDictCursor
import os

# Database connection settings
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "dbname": os.getenv("DB_NAME", "crypto_data"),
    "user": os.getenv("DB_USER", "crypto_admin"),
    "password": os.getenv("DB_PASSWORD", "crypto_secret_2026"),
}


def get_db_connection():
    """Create a database connection."""
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Test database connection on startup."""
    try:
        conn = get_db_connection()
        conn.close()
        print("✅ Database connection successful")
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
    yield


app = FastAPI(
    title="Crypto Data Platform API",
    description="API for accessing cryptocurrency price data",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/")
def root():
    """Health check endpoint."""
    return {"status": "ok", "message": "Crypto Data Platform API"}


@app.get("/prices")
def get_prices():
    """Get latest prices for all cryptocurrencies."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT DISTINCT ON (coin_id)
                coin_id,
                price_usd,
                price_eur,
                market_cap_usd,
                volume_24h_usd,
                change_24h_pct,
                ingested_at
            FROM dbt_staging.stg_prices
            ORDER BY coin_id, ingested_at DESC
        """)
        prices = cursor.fetchall()
        cursor.close()
        conn.close()
        return {"data": prices, "count": len(prices)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/prices/{coin_id}")
def get_price_by_coin(coin_id: str):
    """Get latest price for a specific cryptocurrency."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT
                coin_id,
                price_usd,
                price_eur,
                market_cap_usd,
                volume_24h_usd,
                change_24h_pct,
                ingested_at
            FROM dbt_staging.stg_prices
            WHERE coin_id = %s
            ORDER BY ingested_at DESC
            LIMIT 1
        """, (coin_id,))
        price = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if not price:
            raise HTTPException(status_code=404, detail=f"Coin '{coin_id}' not found")
        
        return {"data": price}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/metrics/daily")
def get_daily_metrics():
    """Get daily aggregated metrics."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT
                coin_id,
                price_date,
                num_records,
                avg_price_usd,
                min_price_usd,
                max_price_usd,
                latest_market_cap_usd,
                latest_volume_24h_usd
            FROM dbt_mart.daily_metrics
            ORDER BY price_date DESC, coin_id
        """)
        metrics = cursor.fetchall()
        cursor.close()
        conn.close()
        return {"data": metrics, "count": len(metrics)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/metrics/daily/{coin_id}")
def get_daily_metrics_by_coin(coin_id: str):
    """Get daily metrics for a specific cryptocurrency."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT
                coin_id,
                price_date,
                num_records,
                avg_price_usd,
                min_price_usd,
                max_price_usd,
                latest_market_cap_usd,
                latest_volume_24h_usd
            FROM dbt_mart.daily_metrics
            WHERE coin_id = %s
            ORDER BY price_date DESC
        """, (coin_id,))
        metrics = cursor.fetchall()
        cursor.close()
        conn.close()
        
        if not metrics:
            raise HTTPException(status_code=404, detail=f"No metrics found for '{coin_id}'")
        
        return {"data": metrics, "count": len(metrics)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
