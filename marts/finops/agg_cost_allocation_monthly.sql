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
        materialized = incremental_or_table(),
        schema = 'marts',
        incremental_strategy = 'insert_overwrite',
        partition_by = {
            'field': 'usage_month',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by = ['customer_id', 'cost_centre'],
        tags = ['marts', 'finops', 'incremental']
    )
}}

with usage_lines as (

    select * from {{ ref('fct_cloud_usage_daily') }}
    {{ incremental_month_filter('usage_month') }}

),

allocated as (

    select
        u.customer_id,
        u.customer_name,
        u.customer_segment,
        u.usage_month,
        u.cloud_provider,

        coalesce(u.environment, 'unallocated')  as environment,
        coalesce(u.team, 'unallocated')         as team,
        coalesce(u.cost_centre, 'unallocated')  as cost_centre,
        coalesce(u.application, 'unallocated')  as application,

        count(*)                                as usage_line_count,
        sum(u.net_cost_usd)                     as net_cost_usd,
        sum(u.credit_amount_usd)                as credit_amount_usd,
        sum(u.effective_cost_usd)               as effective_cost_usd,
        sum(u.total_savings_usd)                as total_savings_usd,
        sum(if(u.cost_centre is null, u.effective_cost_usd, null)) as unallocated_cost_usd

    from usage_lines as u
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
