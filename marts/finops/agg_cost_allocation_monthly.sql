--
-- MART · finops - label based cost allocation (incremental)
--
-- Shows how much of each customer's monthly spend can be attributed to
-- an environment / team / cost centre, and how much stays unallocated
-- because the label is missing on the usage line.
--
-- Rebuilt a whole month at a time - the share-of-spend window is scoped
-- to customer x month, so month-level replacement is lossless.
--

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

allocated as (

    select
        customer_id,
        customer_name,
        customer_segment,
        usage_month,
        cloud_provider,

        coalesce(environment, 'unallocated')    as environment,
        coalesce(team, 'unallocated')           as team,
        coalesce(cost_centre, 'unallocated')    as cost_centre,
        coalesce(application, 'unallocated')    as application,

        count(*)                                as usage_line_count,
        sum(net_cost_usd)                       as net_cost_usd,
        sum(credit_amount_usd)                  as credit_amount_usd,
        sum(effective_cost_usd)                 as effective_cost_usd,
        sum(total_savings_usd)                  as total_savings_usd,
        sum(effective_cost_usd) filter (where cost_centre is null) as unallocated_cost_usd

    from usage
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9

),

final as (

    select
        *,
        sum(effective_cost_usd) over (
            partition by customer_id, usage_month
        )                                       as customer_month_effective_cost_usd,
        case
            when sum(effective_cost_usd) over (partition by customer_id, usage_month) > 0
                then effective_cost_usd
                     / sum(effective_cost_usd) over (partition by customer_id, usage_month)
        end                                     as share_of_customer_month_spend,
        (cost_centre = 'unallocated')           as is_missing_cost_centre
    from allocated

)

select * from final
