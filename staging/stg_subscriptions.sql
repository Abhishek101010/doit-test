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
        s.customer_id,
        sub as subscription
    from source as s
    cross join unnest(s.subscriptions) as sub

),

renamed as (

    select
        subscription.subscription_id            as subscription_id,
        customer_id,
        subscription.product_id                 as product_id,
        subscription.tier                       as subscription_tier,
        lower(subscription.status)              as subscription_status,
        subscription.billing_frequency          as billing_frequency,
        subscription.seats                      as seats,

        subscription.mrr_usd                    as mrr_usd,
        subscription.mrr_usd * 12               as arr_usd,

        subscription.start_date                 as start_date,
        subscription.end_date                   as end_date

    from exploded

),

final as (

    select
        *,
        (subscription_status = 'active' and end_date is null)   as is_active,
        (end_date is not null)                                  as is_churned,
        date_diff(
            coalesce(end_date, current_date()),
            start_date,
            month
        )                                                       as tenure_months
    from renamed

)

select * from final
