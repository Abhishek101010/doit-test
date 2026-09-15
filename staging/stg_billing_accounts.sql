{#
    STAGING - billing accounts (one row per cloud billing account)

    Explodes the nested `billing_accounts` array. This is the join key
    between the customer master data and the cloud billing export.
#}

{{
    config(
        materialized = 'view',
        schema = 'staging',
        tags = ['staging', 'billing_accounts']
    )
}}

with source as (

    select
        customer_id,
        billing_accounts
    from {{ ref('raw_customers') }}

),

exploded as (

    select
        customer_id,
        unnest(billing_accounts) as billing_account
    from source

),

renamed as (

    select
        struct_extract(billing_account, 'billing_account_id')            as billing_account_id,
        customer_id,
        struct_extract(billing_account, 'cloud_provider')                as cloud_provider,
        struct_extract(billing_account, 'currency')                      as billing_currency,
        struct_extract(billing_account, 'payment_terms')                 as payment_terms,
        struct_extract(billing_account, 'is_reseller_account')           as is_reseller_account,
        cast(struct_extract(billing_account, 'activated_on') as date)    as activated_on
    from exploded

)

select * from renamed
