{#
    MART · finops - cloud usage fact (incremental)

    The atomic FinOps fact: one row per usage line (day / billing account
    / SKU) enriched with customer and billing account attributes so the
    BI layer never has to touch the staging models.

    Incremental on `usage_date`: the table is partitioned by day and dbt
    overwrites exactly the partitions covered by the lookback window. The
    dimension joins are safe to re-apply because only the freshly loaded
    window is re-enriched.
#}

{{
    config(
        materialized = incremental_or_table(),
        schema = 'marts',
        incremental_strategy = 'insert_overwrite',
        partition_by = {
            'field': 'usage_date',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by = ['customer_id', 'cloud_provider', 'service_id'],
        tags = ['marts', 'finops', 'incremental']
    )
}}

with usage_lines as (

    select * from {{ ref('stg_cloud_usage') }}
    {{ incremental_date_filter('usage_date') }}

),

customers as (

    select
        customer_id,
        customer_name,
        customer_segment,
        customer_status,
        sales_region,
        account_manager_name
    from {{ ref('dim_customers') }}

),

accounts as (

    select
        billing_account_id,
        billing_currency,
        payment_terms,
        is_reseller_account
    from {{ ref('dim_billing_accounts') }}

),

final as (

    select
        u.usage_id,
        u.usage_date,
        u.usage_month,
        u.usage_day_name,
        u.is_weekend,

        -- customer / account context
        u.customer_id,
        c.customer_name,
        c.customer_segment,
        c.customer_status,
        c.sales_region,
        c.account_manager_name,

        u.billing_account_id,
        a.billing_currency,
        a.payment_terms,
        a.is_reseller_account,

        -- resource context
        u.cloud_provider,
        u.project_id,
        u.project_name,
        u.service_id,
        u.service_name,
        u.service_category,
        u.sku_id,
        u.sku_description,
        u.cloud_region,
        u.cloud_zone,

        -- allocation labels
        u.environment,
        u.team,
        u.cost_centre,
        u.application,

        -- measures
        u.usage_quantity,
        u.usage_unit,
        u.list_unit_price_usd,
        u.list_cost_usd,
        u.discount_usd,
        u.discount_rate,
        u.net_cost_usd,
        u.credit_amount_usd,
        u.credit_count,
        u.effective_cost_usd,
        u.is_flexsave_eligible,
        u.flexsave_savings_usd,
        u.optimisation_savings_usd,
        u.total_savings_usd,
        '{{ var("reporting_currency") }}' as reporting_currency

    from usage_lines u
    inner join customers c on c.customer_id = u.customer_id
    left join accounts a   on a.billing_account_id = u.billing_account_id

)

select * from final
