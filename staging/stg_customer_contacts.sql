{#
    STAGING - customer contacts (one row per contact)

    Explodes the nested `contacts` array on the raw customer record.
#}

{{
    config(
        materialized = 'view',
        schema = 'staging',
        tags = ['staging', 'customers']
    )
}}

with source as (

    select
        customer_id,
        contacts
    from {{ ref('raw_customers') }}

),

exploded as (

    select
        s.customer_id,
        ct as contact
    from source as s
    cross join unnest(s.contacts) as ct

),

renamed as (

    select
        contact.contact_id      as contact_id,
        customer_id,
        contact.full_name       as contact_name,
        contact.email           as contact_email,
        contact.role            as contact_role,
        contact.is_primary      as is_primary_contact
    from exploded

)

select * from renamed
