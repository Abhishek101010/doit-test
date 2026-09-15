{#
    Helpers for working with the nested ARRAY<STRUCT<key, value>> label
    column on the billing export.

    BigQuery has no MAP type, so labels stay as a repeated STRUCT and are
    read with correlated subqueries over UNNEST.
#}


{#
    Pulls a single label value out of the nested {key, value} array,
    returning NULL when the label is not present on the row.

    Usage:  {{ label_value('u.labels', 'env') }} as environment
#}
{% macro label_value(labels_column, key) -%}
    (
        select l.value
        from unnest({{ labels_column }}) as l
        where l.key = '{{ key }}'
        limit 1
    )
{%- endmacro %}


{#
    Total of a numeric field across a nested array, returning 0.0 when the
    array is empty or NULL.

    Usage:  {{ array_sum('u.credits', 'amount_usd') }} as credit_amount_usd
#}
{% macro array_sum(array_column, field_name) -%}
    coalesce(
        (
            select sum(x.{{ field_name }})
            from unnest({{ array_column }}) as x
        ),
        0.0
    )
{%- endmacro %}
