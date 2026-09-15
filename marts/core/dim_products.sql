{#
    MART · core - product dimension

    Product catalogue enriched with feature availability and the pricing
    envelope taken from the nested tier list.
#}

{{
    config(
        materialized = 'table',
        schema = 'marts',
        tags = ['marts', 'core']
    )
}}

with products as (

    select * from {{ ref('stg_products') }}

),

features as (

    select
        product_id,
        count(*)                                        as feature_count,
        countif(availability_status = 'GA')             as ga_feature_count,
        countif(availability_status = 'PREVIEW')        as preview_feature_count,
        countif(availability_status = 'RETIRED')        as retired_feature_count
    from {{ ref('stg_product_features') }}
    group by 1

),

pricing as (

    select
        product_id,
        count(*)            as pricing_tier_count,
        min(rate_pct)       as min_rate_pct,
        max(rate_pct)       as max_rate_pct,
        max(max_monthly_spend_usd) as max_addressable_monthly_spend_usd
    from {{ ref('stg_product_pricing_tiers') }}
    group by 1

),

adoption as (

    select
        product_id,
        count(distinct customer_id)                 as customer_count,
        count(*)                                    as subscription_count,
        countif(is_active)                          as active_subscription_count,
        sum(if(is_active, mrr_usd, null))           as active_mrr_usd
    from {{ ref('stg_subscriptions') }}
    group by 1

),

final as (

    select
        p.product_id,
        p.product_name,
        p.product_family,
        p.product_description,
        p.is_active_product,
        p.launch_date,

        p.supported_providers,
        p.supported_providers_list,
        p.supported_provider_count,

        p.pricing_model,
        p.pricing_currency,
        p.base_fee_usd,
        coalesce(pr.pricing_tier_count, 0)      as pricing_tier_count,
        pr.min_rate_pct,
        pr.max_rate_pct,
        pr.max_addressable_monthly_spend_usd,

        coalesce(f.feature_count, 0)            as feature_count,
        coalesce(f.ga_feature_count, 0)         as ga_feature_count,
        coalesce(f.preview_feature_count, 0)    as preview_feature_count,
        coalesce(f.retired_feature_count, 0)    as retired_feature_count,

        coalesce(a.customer_count, 0)               as customer_count,
        coalesce(a.subscription_count, 0)           as subscription_count,
        coalesce(a.active_subscription_count, 0)    as active_subscription_count,
        coalesce(a.active_mrr_usd, 0)               as active_mrr_usd

    from products p
    left join features f  on f.product_id = p.product_id
    left join pricing pr  on pr.product_id = p.product_id
    left join adoption a  on a.product_id = p.product_id

)

select * from final
