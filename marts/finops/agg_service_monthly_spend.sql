{#
    MART · finops - monthly spend by provider / service (incremental)

    Answers "where is the money going?" and ranks services within each
    customer month so the top cost drivers surface immediately.

    The ranking window is partitioned by customer and month, so rebuilding
    whole months keeps the ranks correct.
#}

{{
    config(
        materialized = 'incremental',
        schema = 'marts',
        unique_key = 'usage_month',
        incremental_strategy = 'delete+insert',
        tags = ['marts', 'finops', 'incremental']
    )
}}

with usage as (

    select * from {{ ref('fct_cloud_usage_daily') }}
    {{ incremental_month_filter('usage_month') }}

),

aggregated as (

    select
        customer_id,
        customer_name,
        customer_segment,
        usage_month,
        cloud_provider,
        service_id,
        service_name,
        service_category,

        count(*)                                        as usage_line_count,
        count(distinct sku_id)                          as sku_count,
        count(distinct cloud_region)                    as region_count,

        sum(usage_quantity)                             as usage_quantity,
        sum(list_cost_usd)                              as list_cost_usd,
        sum(discount_usd)                               as discount_usd,
        sum(net_cost_usd)                               as net_cost_usd,
        sum(credit_amount_usd)                          as credit_amount_usd,
        sum(effective_cost_usd)                         as effective_cost_usd,
        sum(total_savings_usd)                          as total_savings_usd

    from usage
    group by 1, 2, 3, 4, 5, 6, 7, 8

),

ranked as (

    select
        *,
        sum(effective_cost_usd) over (
            partition by customer_id, usage_month
        )                                               as customer_month_effective_cost_usd,
        row_number() over (
            partition by customer_id, usage_month
            order by effective_cost_usd desc
        )                                               as service_cost_rank
    from aggregated

)

select
    *,
    case
        when customer_month_effective_cost_usd > 0
            then effective_cost_usd / customer_month_effective_cost_usd
    end                                                 as share_of_customer_month_spend
from ranked
