{#
    MART · core - billing account dimension

    The bridge between the customer master data and the cloud billing
    export. One row per cloud billing account.
#}

{{
    config(
        materialized = 'table',
        schema = 'marts',
        tags = ['marts', 'core']
    )
}}

with accounts as (

    select * from {{ ref('stg_billing_accounts') }}

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

usage as (

    select
        billing_account_id,
        min(usage_date)                 as first_usage_date,
        max(usage_date)                 as last_usage_date,
        count(*)                        as usage_line_count,
        sum(effective_cost_usd)         as lifetime_effective_cost_usd
    from {{ ref('stg_cloud_usage') }}
    group by 1

),

final as (

    select
        a.billing_account_id,
        a.customer_id,
        c.customer_name,
        c.customer_segment,
        c.customer_status,
        c.sales_region,
        c.account_manager_name,

        a.cloud_provider,
        a.billing_currency,
        a.payment_terms,
        a.is_reseller_account,
        a.activated_on,

        coalesce(u.usage_line_count, 0)             as usage_line_count,
        coalesce(u.lifetime_effective_cost_usd, 0)  as lifetime_effective_cost_usd,
        u.first_usage_date,
        u.last_usage_date

    from accounts a
    inner join customers c on c.customer_id = a.customer_id
    left join usage u      on u.billing_account_id = a.billing_account_id

)

select * from final
