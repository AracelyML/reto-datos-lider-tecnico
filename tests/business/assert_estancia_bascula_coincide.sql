with esperado as (
    select
        cla_planta,
        cla_bascula,
        count(*) as num_viajes,
        avg(estancia_minutos) as estancia_promedio_min
    from {{ ref('int_viajes__pesajes') }}
    where estancia_minutos is not null
    group by cla_planta, cla_bascula
),

publicado as (
    select cla_planta, cla_bascula, num_viajes, estancia_promedio_min
    from {{ ref('estancia_bascula') }}
)

select
    coalesce(e.cla_planta, p.cla_planta) as cla_planta,
    coalesce(e.cla_bascula, p.cla_bascula) as cla_bascula,
    e.num_viajes as esperado_viajes,
    p.num_viajes as publicado_viajes,
    e.estancia_promedio_min as esperado_promedio,
    p.estancia_promedio_min as publicado_promedio
from esperado e
full outer join publicado p on p.cla_planta = e.cla_planta and p.cla_bascula = e.cla_bascula
where coalesce(e.num_viajes, 0) <> coalesce(p.num_viajes, 0)
   or abs(coalesce(e.estancia_promedio_min, 0) - coalesce(p.estancia_promedio_min, 0)) > 0.01
