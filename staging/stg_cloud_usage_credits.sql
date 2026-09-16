{#
    STAGING - cloud usage credits (one row per usage line / credit)

    Explodes the nested `credits` array. Amounts are negative because a
    credit reduces the net cost of the usage line.

    Partitioned and incremental on `usage_date`; whole days are overwritten
    because a usage line can gain or lose credits on restatement, so a
    per-credit unique key would leave orphans behind.
#}

{{
    config(
        materialized = incremental_or_table(),
        schema = 'staging',
        incremental_strategy = 'insert_overwrite',
        partition_by = {
            'field': 'usage_date',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by = ['customer_id', 'credit_type'],
        tags = ['staging', 'cloud_usage', 'incremental']
    )
}}

with source as (

    select
        usage_id,
        usage_date,
        customer_id,
        billing_account_id,
        cloud_provider,
        credits
    from {{ ref('raw_cloud_usage') }}
    where array_length(credits) > 0
    {{ incremental_date_filter('usage_date', relation = this, target_column = 'usage_date', operator = 'and') }}

),

exploded as (

    select
        s.usage_id,
        s.usage_date,
        s.customer_id,
        s.billing_account_id,
        s.cloud_provider,
        c as credit
    from source as s
    cross join unnest(s.credits) as c

),

renamed as (

    select
        credit.credit_id                    as credit_id,
        usage_id,
        usage_date,
        date_trunc(usage_date, month)       as usage_month,
        customer_id,
        billing_account_id,
        cloud_provider,
        credit.credit_type                  as credit_type,
        credit.amount_usd                   as credit_amount_usd,
        abs(credit.amount_usd)              as credit_abs_amount_usd
    from exploded

)

select * from renamed
