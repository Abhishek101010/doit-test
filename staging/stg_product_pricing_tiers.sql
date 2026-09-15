{#
    STAGING - product pricing tiers (one row per product / tier)

    Explodes `pricing.tiers`, the doubly nested array on the raw product
    record (a struct that contains a list of structs).
#}

{{
    config(
        materialized = 'view',
        schema = 'staging',
        tags = ['staging', 'products']
    )
}}

with source as (

    select
        p.product_id,
        p.pricing.model     as pricing_model,
        p.pricing.currency  as pricing_currency,
        p.pricing.tiers     as tiers
    from {{ ref('raw_products') }} as p

),

exploded as (

    select
        s.product_id,
        s.pricing_model,
        s.pricing_currency,
        t as tier
    from source as s
    cross join unnest(s.tiers) as t

),

renamed as (

    select
        product_id,
        tier.tier_name                                      as tier_name,
        pricing_model,
        pricing_currency,
        cast(tier.min_monthly_spend_usd as float64)         as min_monthly_spend_usd,
        cast(tier.max_monthly_spend_usd as float64)         as max_monthly_spend_usd,
        tier.rate_pct                                       as rate_pct,
        tier.included_support                               as included_support
    from exploded

)

select * from renamed
