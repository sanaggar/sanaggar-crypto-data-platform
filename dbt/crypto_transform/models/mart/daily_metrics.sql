-- Mart model: Daily aggregated metrics per cryptocurrency

with prices as (
    select * from {{ ref('stg_prices') }}
),

daily_stats as (
    select
        coin_id,
        symbol,
        name,
        market_cap_rank,
        date_trunc('day', ingested_at) as date,
        avg(price_usd) as avg_price_usd,
        min(price_usd) as min_price_usd,
        max(price_usd) as max_price_usd,
        avg(market_cap_usd) as avg_market_cap_usd,
        avg(volume_24h_usd) as avg_volume_24h_usd,
        avg(change_24h_pct) as avg_change_24h_pct,
        count(*) as data_points
    from prices
    group by coin_id, symbol, name, market_cap_rank, date_trunc('day', ingested_at)
)

select * from daily_stats
order by date desc, market_cap_rank asc
