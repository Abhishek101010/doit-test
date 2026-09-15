{#
    Use the custom schema name as-is (raw / staging / marts) instead of the
    default dbt behaviour of prefixing it with the target schema
    (e.g. `main_staging`). Keeps the layered warehouse easy to browse.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
