select
    cast(anio_mes as varchar) as anio_mes,
    cast(segmento_cliente as varchar) as segmento_cliente,
    cast(round(sum(toneladas), 3) as decimal(18, 3)) as toneladas_entregadas,
    cast(round(sum(case when a_tiempo then toneladas else 0 end), 3) as decimal(18, 3)) as toneladas_a_tiempo,
    cast(round(sum(case when a_tiempo then toneladas else 0 end) / nullif(sum(toneladas), 0), 4) as decimal(18, 4)) as pct_a_tiempo
from {{ ref('fct_embarque_partidas') }}
where tiene_pod
group by anio_mes, segmento_cliente
