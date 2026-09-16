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
        s.customer_id,
        ba as billing_account
    from source as s
    cross join unnest(s.billing_accounts) as ba

),

renamed as (

    select
        billing_account.billing_account_id      as billing_account_id,
        customer_id,
        billing_account.cloud_provider          as cloud_provider,
        billing_account.currency                as billing_currency,
        billing_account.payment_terms           as payment_terms,
        billing_account.is_reseller_account     as is_reseller_account,
        billing_account.activated_on            as activated_on
    from exploded

)

select * from renamed
