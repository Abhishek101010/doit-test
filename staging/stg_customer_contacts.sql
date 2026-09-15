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
        customer_id,
        unnest(contacts) as contact
    from source

),

renamed as (

    select
        struct_extract(contact, 'contact_id')   as contact_id,
        customer_id,
        struct_extract(contact, 'full_name')    as contact_name,
        struct_extract(contact, 'email')        as contact_email,
        struct_extract(contact, 'role')         as contact_role,
        struct_extract(contact, 'is_primary')   as is_primary_contact
    from exploded

)

select * from renamed
