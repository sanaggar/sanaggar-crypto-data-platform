-- Mart model: Daily aggregated metrics per cryptocurrency

with staged_prices as (
    select * from {{ ref('stg_prices') }}
),

daily_aggregates as (
    select
        coin_id,
        date(ingested_at) as price_date,
        
        -- Aggregations
        count(*) as num_records,
        avg(price_usd) as avg_price_usd,
        min(price_usd) as min_price_usd,
        max(price_usd) as max_price_usd,
        avg(price_eur) as avg_price_eur,
        
        -- Latest values (from most recent record of the day)
        (array_agg(market_cap_usd order by ingested_at desc))[1] as latest_market_cap_usd,
        (array_agg(volume_24h_usd order by ingested_at desc))[1] as latest_volume_24h_usd,
        (array_agg(change_24h_pct order by ingested_at desc))[1] as latest_change_24h_pct,
        
        -- Metadata
        min(ingested_at) as first_ingestion,
        max(ingested_at) as last_ingestion
        
    from staged_prices
    group by coin_id, date(ingested_at)
)

select * from daily_aggregates
