{#
    MART · finops - monthly spend and margin per customer (incremental)

    Combines cloud spend from the billing export with the subscription
    MRR that was live in the same month, giving the classic FinOps view
    of "what the customer spends" vs "what we bill them".

    Incremental by whole month: the table is partitioned by `usage_month`
    at MONTH granularity, so only the months touched by the lookback window
    are recomputed and overwritten. Every aggregate here is contained within
    a month, so month-level replacement is lossless.
#}

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
        cluster_by = ['customer_id', 'customer_segment'],
        tags = ['marts', 'finops', 'incremental']
    )
}}

with usage_lines as (

    select * from {{ ref('fct_cloud_usage_daily') }}
    {{ incremental_month_filter('usage_month') }}

),

monthly_spend as (

    select
        customer_id,
        customer_name,
        customer_segment,
        customer_status,
        sales_region,
        account_manager_name,
        usage_month,

        count(distinct usage_date)              as active_days,
        count(distinct billing_account_id)      as billing_account_count,
        count(distinct cloud_provider)          as cloud_provider_count,
        count(distinct service_id)              as service_count,

        sum(list_cost_usd)                      as list_cost_usd,
        sum(discount_usd)                       as discount_usd,
        sum(net_cost_usd)                       as net_cost_usd,
        sum(credit_amount_usd)                  as credit_amount_usd,
        sum(effective_cost_usd)                 as effective_cost_usd,
        sum(flexsave_savings_usd)               as flexsave_savings_usd,
        sum(optimisation_savings_usd)           as optimisation_savings_usd,
        sum(total_savings_usd)                  as total_savings_usd,
        sum(if(is_flexsave_eligible, effective_cost_usd, null)) as flexsave_eligible_cost_usd

    from usage_lines
    group by 1, 2, 3, 4, 5, 6, 7

),

months as (

    select distinct usage_month from monthly_spend

),

subscription_revenue as (

    select
        m.usage_month,
        s.customer_id,
        sum(s.mrr_usd)                          as subscription_mrr_usd,
        count(*)                                as live_subscription_count
    from months m
    inner join {{ ref('stg_subscriptions') }} s
        on s.start_date <= last_day(m.usage_month, month)
        and (s.end_date is null or s.end_date >= m.usage_month)
    group by 1, 2

),

final as (

    select
        concat(ms.customer_id, '|', cast(ms.usage_month as string))  as customer_month_key,
        ms.customer_id,
        ms.customer_name,
        ms.customer_segment,
        ms.customer_status,
        ms.sales_region,
        ms.account_manager_name,
        ms.usage_month,

        ms.active_days,
        ms.billing_account_count,
        ms.cloud_provider_count,
        ms.service_count,

        ms.list_cost_usd,
        ms.discount_usd,
        ms.net_cost_usd,
        ms.credit_amount_usd,
        ms.effective_cost_usd,
        ms.effective_cost_usd / nullif(ms.active_days, 0)            as avg_daily_effective_cost_usd,

        ms.flexsave_savings_usd,
        ms.optimisation_savings_usd,
        ms.total_savings_usd,
        coalesce(ms.flexsave_eligible_cost_usd, 0)                   as flexsave_eligible_cost_usd,
        case
            when ms.list_cost_usd > 0
                then ms.total_savings_usd / ms.list_cost_usd
        end                                                          as savings_rate,

        coalesce(sr.subscription_mrr_usd, 0)                         as subscription_mrr_usd,
        coalesce(sr.live_subscription_count, 0)                      as live_subscription_count,
        case
            when ms.effective_cost_usd > 0
                then coalesce(sr.subscription_mrr_usd, 0) / ms.effective_cost_usd
        end                                                          as revenue_to_spend_ratio,

        '{{ var("reporting_currency") }}'                            as reporting_currency

    from monthly_spend ms
    left join subscription_revenue sr
        on sr.customer_id = ms.customer_id
        and sr.usage_month = ms.usage_month

)

select * from final
