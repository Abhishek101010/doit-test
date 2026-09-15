{#
    STAGING - subscriptions (one row per subscription)

    Explodes the nested `subscriptions` array and derives the recurring
    revenue measures used by the marts layer.
#}

{{
    config(
        materialized = 'view',
        schema = 'staging',
        tags = ['staging', 'subscriptions']
    )
}}

with source as (

    select
        customer_id,
        subscriptions
    from {{ ref('raw_customers') }}

),

exploded as (

    select
        customer_id,
        unnest(subscriptions) as subscription
    from source

),

renamed as (

    select
        struct_extract(subscription, 'subscription_id')      as subscription_id,
        customer_id,
        struct_extract(subscription, 'product_id')           as product_id,
        struct_extract(subscription, 'tier')                 as subscription_tier,
        lower(struct_extract(subscription, 'status'))        as subscription_status,
        struct_extract(subscription, 'billing_frequency')    as billing_frequency,
        struct_extract(subscription, 'seats')                as seats,

        cast(struct_extract(subscription, 'mrr_usd') as double)        as mrr_usd,
        cast(struct_extract(subscription, 'mrr_usd') as double) * 12   as arr_usd,

        cast(struct_extract(subscription, 'start_date') as date)       as start_date,
        cast(struct_extract(subscription, 'end_date') as date)         as end_date

    from exploded

),

final as (

    select
        *,
        (subscription_status = 'active' and end_date is null)   as is_active,
        (end_date is not null)                                  as is_churned,
        datediff(
            'month',
            start_date,
            coalesce(end_date, current_date)
        )                                                       as tenure_months
    from renamed

)

select * from final
