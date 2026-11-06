with pesajes_agregados as (
    select
        cla_planta,
        cla_bascula,
        count(*) as num_viajes,
        avg(estancia_minutos) as estancia_promedio_min
    from {{ ref('int_viajes__pesajes') }}
    where estancia_minutos is not null
    group by cla_planta, cla_bascula
)

select
    cast(b.cla_planta as integer) as cla_planta,
    cast(b.cla_bascula as integer) as cla_bascula,
    cast(b.nom_bascula as varchar) as nom_bascula,
    cast(coalesce(p.num_viajes, 0) as integer) as num_viajes,
    cast(round(p.estancia_promedio_min, 2) as decimal(18, 2)) as estancia_promedio_min
from {{ ref('stg_bas__basculas') }} b
left join pesajes_agregados p on p.cla_planta = b.cla_planta and p.cla_bascula = b.cla_bascula
