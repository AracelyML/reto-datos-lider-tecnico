{#-
    Grano: un viaje embarcado.
    Regla 2: solo TRA y ENT. Regla 1: fecha real, si no la final, en hora local de planta;
    una planta sin zona registrada queda en hora de Monterrey, la del origen (H9).
    Regla 5: a tiempo si la fecha de entrega del POD es menor o igual a la fecha compromiso,
    comparando fechas: el compromiso no trae hora (H8).
-#}
with viajes as (
    select
        v.*,
        {{ hora_local_planta('coalesce(v.fecha_real_embarque, v.fecha_embarque_final)', "coalesce(z.zona_horaria, 'America/Monterrey')") }} as fecha_embarque_local,
        coalesce(z.zona_horaria, 'America/Monterrey') as zona_horaria
    from {{ ref('stg_fle__viajes') }} v
    left join {{ ref('zona_horaria_planta') }} z on z.cla_planta = v.cla_planta
    where v.estatus in ('TRA', 'ENT')
),

partidas as (
    select id_viaje, sum(peso_kg) / 1000 as toneladas, count(*) as num_partidas
    from {{ ref('stg_fle__viaje_partidas') }}
    group by id_viaje
)

select
    v.id_viaje,
    v.cla_planta,
    v.estatus,
    v.fecha_embarque_local as fecha_embarque,
    strftime(v.fecha_embarque_local, '%Y-%m') as anio_mes,
    v.fecha_real_embarque is null as fecha_embarque_es_final,
    v.fecha_compromiso,
    v.costo_flete_mxn,
    coalesce(p.toneladas, 0) as toneladas,
    coalesce(p.num_partidas, 0) as num_partidas,
    {{ hora_local_planta('e.fecha_entrega', 'v.zona_horaria') }} as fecha_entrega,
    e.id_viaje is not null as tiene_pod,
    case when e.id_viaje is not null then cast({{ hora_local_planta('e.fecha_entrega', 'v.zona_horaria') }} as date) <= cast(v.fecha_compromiso as date) end as a_tiempo
from viajes v
left join partidas p on p.id_viaje = v.id_viaje
left join {{ ref('stg_fle__entregas') }} e on e.id_viaje = v.id_viaje
