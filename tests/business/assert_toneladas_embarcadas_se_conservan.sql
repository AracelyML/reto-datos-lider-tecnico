{#-
    Regla 3 + 7: ninguna tonelada embarcada se pierde ni se duplica camino al mart.
    Se recalcula desde staging, por un camino independiente del modelo, y se compara por mes y planta.
    Falla si un join multiplica partidas, si un cliente sin maestro se descarta o si cambia el filtro de estatus.
-#}
with esperado as (
    select
        strftime({{ hora_local_planta('coalesce(v.fecha_real_embarque, v.fecha_embarque_final)', "coalesce(z.zona_horaria, 'America/Monterrey')") }}, '%Y-%m') as anio_mes,
        v.cla_planta,
        sum(p.peso_kg) / 1000 as toneladas
    from {{ ref('stg_fle__viaje_partidas') }} p
    join {{ ref('stg_fle__viajes') }} v on v.id_viaje = p.id_viaje
    left join {{ ref('zona_horaria_planta') }} z on z.cla_planta = v.cla_planta
    where v.estatus in ('TRA', 'ENT')
    group by 1, 2
),

publicado as (
    select anio_mes, cla_planta, toneladas_embarcadas from {{ ref('embarques_mensual') }}
)

select
    coalesce(e.anio_mes, p.anio_mes) as anio_mes,
    coalesce(e.cla_planta, p.cla_planta) as cla_planta,
    e.toneladas as esperado,
    p.toneladas_embarcadas as publicado
from esperado e
full outer join publicado p on p.anio_mes = e.anio_mes and p.cla_planta = e.cla_planta
where abs(coalesce(e.toneladas, 0) - coalesce(p.toneladas_embarcadas, 0)) > 0.001
