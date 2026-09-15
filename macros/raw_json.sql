{#
    Reads a landed JSON file from the raw data folder as a DuckDB relation.

    The files are pretty-printed JSON arrays of nested objects, so we ask
    DuckDB to auto-detect the schema (structs / lists are preserved).

    Usage:  select * from {{ raw_json('customers') }}
#}
{% macro raw_json(file_name) -%}
    read_json(
        '{{ var("raw_data_path") }}/{{ file_name }}.json',
        format = 'array',
        auto_detect = true,
        maximum_depth = -1
    )
{%- endmacro %}


{#
    Converts a list of {key, value} structs into a MAP so labels can be
    looked up by key downstream, e.g. labels_map['env'].
#}
{% macro labels_to_map(labels_column) -%}
    map_from_entries(
        list_transform({{ labels_column }}, x -> struct_pack(key := x.key, value := x.value))
    )
{%- endmacro %}


{#
    Pulls a single label value out of the nested {key, value} array,
    returning NULL when the label is not present on the row.

    Usage:  {{ label_value('labels', 'env') }} as environment
#}
{% macro label_value(labels_column, key) -%}
    struct_extract(
        list_extract(
            list_filter({{ labels_column }}, x -> x.key = '{{ key }}'),
            1
        ),
        'value'
    )
{%- endmacro %}
