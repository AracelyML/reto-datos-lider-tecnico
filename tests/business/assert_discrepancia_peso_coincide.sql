with pesajes as (
    select *
    from {{ ref('int_viajes__pesajes') }}
    where peso_bascula_neto_kg is not null
),

partidas as (
    select
        id_viaje,
        sum(peso_kg) as peso_doc_kg
    from {{ ref('stg_fle__viaje_partidas') }}
    group by id_viaje
),

embarques as (
    select id_viaje, anio_mes
    from {{ ref('fct_embarques') }}
),

esperado as (
    select
        coalesce(e.anio_mes, strftime(p.fecha_salida_utc, '%Y-%m')) as anio_mes,
        p.cla_planta,
        count(*) as num_viajes_pesados,
        sum(case
            when d.peso_doc_kg is not null and d.peso_doc_kg > 0
            and abs(p.peso_bascula_neto_kg - d.peso_doc_kg) / d.peso_doc_kg > 0.02
            then 1 else 0
        end) as num_viajes_con_discrepancia
    from pesajes p
    join partidas d on d.id_viaje = p.id_viaje
    left join embarques e on e.id_viaje = p.id_viaje
    group by 1, 2
),

publicado as (
    select anio_mes, cla_planta, num_viajes_pesados, num_viajes_con_discrepancia
    from {{ ref('discrepancia_peso') }}
)

select
    coalesce(e.anio_mes, p.anio_mes) as anio_mes,
    coalesce(e.cla_planta, p.cla_planta) as cla_planta,
    e.num_viajes_pesados as esperado_pesados,
    p.num_viajes_pesados as publicado_pesados,
    e.num_viajes_con_discrepancia as esperado_discrepancia,
    p.num_viajes_con_discrepancia as publicado_discrepancia
from esperado e
full outer join publicado p on p.anio_mes = e.anio_mes and p.cla_planta = e.cla_planta
where coalesce(e.num_viajes_pesados, 0) <> coalesce(p.num_viajes_pesados, 0)
   or coalesce(e.num_viajes_con_discrepancia, 0) <> coalesce(p.num_viajes_con_discrepancia, 0)
