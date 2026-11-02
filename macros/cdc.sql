{#- Estándar para tablas landing de réplica CDC (Airbyte). -#}

{#- Última versión de cada llave según LSN; descarta llaves cuya última versión está borrada.
    Varios cambios de una misma transacción comparten LSN: el desempate mantiene el resultado determinista. -#}
{% macro cdc_latest(relation, key_columns, lsn='_ab_cdc_lsn') -%}
    select *
    from {{ relation }}
    qualify row_number() over (
        partition by {{ key_columns | join(', ') }}
        order by cast({{ lsn }} as bigint) desc, _ab_cdc_updated_at desc, _airbyte_extracted_at desc, _entrega desc
    ) = 1
    and _ab_cdc_deleted_at is null
{%- endmacro %}

{#- Todas las versiones distintas de cada llave (una por LSN), para historial / SCD2. -#}
{% macro cdc_versions(relation, key_columns, lsn='_ab_cdc_lsn') -%}
    select *
    from {{ relation }}
    qualify row_number() over (
        partition by {{ key_columns | join(', ') }}, {{ lsn }}
        order by _ab_cdc_updated_at desc, _airbyte_extracted_at desc, _entrega desc
    ) = 1
{%- endmacro %}

{#- Texto de catálogo: sin espacios y en mayúsculas. -#}
{% macro clean_code(column) -%}
    upper(trim({{ column }}))
{%- endmacro %}

{#- Fecha del origen; 1900-01-01 es el centinela de "no capturado". -#}
{% macro source_timestamp(column) -%}
    case when {{ column }} like '1900-01-01%' then null else cast({{ column }} as timestamp) end
{%- endmacro %}
