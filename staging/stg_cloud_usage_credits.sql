{#
    STAGING - cloud usage credits (one row per usage line / credit)

    Explodes the nested `credits` array. Amounts are negative because a
    credit reduces the net cost of the usage line.

    Incremental on `usage_date`; the whole day is replaced (delete+insert)
    because a usage line can gain or lose credits on restatement, so a
    per-credit unique key would leave orphans behind.
#}

{{
    config(
        materialized = 'incremental',
        schema = 'staging',
        unique_key = 'usage_date',
        incremental_strategy = 'delete+insert',
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
    where len(credits) > 0
    {{ incremental_date_filter('_usage_date', relation = this, target_column = 'usage_date', operator = 'and') }}

),

exploded as (

    select
        usage_id,
        usage_date,
        customer_id,
        billing_account_id,
        cloud_provider,
        unnest(credits) as credit
    from source

),

renamed as (

    select
        struct_extract(credit, 'credit_id')                     as credit_id,
        usage_id,
        cast(usage_date as date)                                as usage_date,
        date_trunc('month', cast(usage_date as date))           as usage_month,
        customer_id,
        billing_account_id,
        cloud_provider,
        struct_extract(credit, 'credit_type')                   as credit_type,
        cast(struct_extract(credit, 'amount_usd') as double)    as credit_amount_usd,
        abs(cast(struct_extract(credit, 'amount_usd') as double)) as credit_abs_amount_usd
    from exploded

)

select * from renamed
