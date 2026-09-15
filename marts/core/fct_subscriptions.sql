{#
    MART · core - subscription fact

    One row per subscription with the customer and product attributes
    needed for revenue reporting.
#}

{{
    config(
        materialized = 'table',
        schema = 'marts',
        tags = ['marts', 'core']
    )
}}

with subscriptions as (

    select * from {{ ref('stg_subscriptions') }}

),

customers as (

    select
        customer_id,
        customer_name,
        customer_segment,
        customer_status,
        sales_region,
        account_manager_name
    from {{ ref('stg_customers') }}

),

products as (

    select
        product_id,
        product_name,
        product_family,
        pricing_model,
        is_active_product
    from {{ ref('stg_products') }}

),

final as (

    select
        s.subscription_id,
        s.customer_id,
        s.product_id,

        c.customer_name,
        c.customer_segment,
        c.customer_status,
        c.sales_region,
        c.account_manager_name,

        p.product_name,
        p.product_family,
        p.pricing_model,
        p.is_active_product,

        s.subscription_tier,
        s.subscription_status,
        s.billing_frequency,
        s.seats,
        s.mrr_usd,
        s.arr_usd,
        case
            when s.seats > 0 then s.mrr_usd / s.seats
        end                                     as mrr_per_seat_usd,

        s.start_date,
        s.end_date,
        s.is_active,
        s.is_churned,
        s.tenure_months

    from subscriptions s
    inner join customers c on c.customer_id = s.customer_id
    inner join products p  on p.product_id = s.product_id

)

select * from final
