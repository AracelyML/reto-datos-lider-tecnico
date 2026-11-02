{#- _ab_cdc_updated_at viene en UTC; lo pasa a hora de Monterrey (UTC-6 fijo), la misma en que el origen registra sus fechas (H9). -#}
{% macro utc_to_local(column) -%}
    ({{ column }} - interval 6 hour)
{%- endmacro %}

{#- Fecha del origen (hora de Monterrey, H9) a la hora local de la planta (regla 1), con su zona IANA. -#}
{% macro hora_local_planta(column, zona_horaria) -%}
    timezone({{ zona_horaria }}, {{ column }} at time zone 'America/Monterrey')
{%- endmacro %}
