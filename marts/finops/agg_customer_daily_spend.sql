{#
    MART · finops - daily spend per customer and cloud provider

    Day-level roll-up used for burn-down charts and anomaly detection.
    The 7 day moving average and day-over-day change make spikes in the
    billing export easy to spot.

    Deliberately **not** incremental: the trailing-7-day window and the
    `lag()` both reach across day (and month) boundaries, so a partial
    rebuild would produce wrong averages at the seam. The grain is small
    (customer x provider x day), so a full rebuild is cheap.
#}

{{
    config(
        materialized = 'table',
        schema = 'marts',
        tags = ['marts', 'finops']
    )
}}

with usage_lines as (

    select * from {{ ref('fct_cloud_usage_daily') }}

),

daily as (

    select
        customer_id,
        customer_name,
        customer_segment,
        sales_region,
        cloud_provider,
        usage_date,
        usage_month,

        count(*)                                            as usage_line_count,
        count(distinct service_id)                          as service_count,
        count(distinct project_id)                          as project_count,

        sum(list_cost_usd)                                  as list_cost_usd,
        sum(discount_usd)                                   as discount_usd,
        sum(net_cost_usd)                                   as net_cost_usd,
        sum(credit_amount_usd)                              as credit_amount_usd,
        sum(effective_cost_usd)                             as effective_cost_usd,
        sum(flexsave_savings_usd)                           as flexsave_savings_usd,
        sum(optimisation_savings_usd)                       as optimisation_savings_usd,
        sum(total_savings_usd)                              as total_savings_usd

    from usage_lines
    group by 1, 2, 3, 4, 5, 6, 7

),

with_trend as (

    select
        *,
        avg(effective_cost_usd) over (
            partition by customer_id, cloud_provider
            order by usage_date
            rows between 6 preceding and current row
        )                                                   as effective_cost_7d_avg_usd,
        lag(effective_cost_usd) over (
            partition by customer_id, cloud_provider
            order by usage_date
        )                                                   as prev_day_effective_cost_usd
    from daily

)

select
    concat(customer_id, '|', cloud_provider, '|', cast(usage_date as string)) as customer_provider_day_key,
    *,
    effective_cost_usd - prev_day_effective_cost_usd                            as day_over_day_change_usd,
    case
        when prev_day_effective_cost_usd > 0
            then effective_cost_usd / prev_day_effective_cost_usd - 1
    end                                                                        as day_over_day_change_pct,
    case
        when effective_cost_7d_avg_usd > 0
            then effective_cost_usd / effective_cost_7d_avg_usd
    end                                                                        as spend_vs_7d_avg_ratio
from with_trend
