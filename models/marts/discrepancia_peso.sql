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

viajes_pesados as (
    select
        p.id_viaje,
        p.cla_planta,
        coalesce(e.anio_mes, strftime(p.fecha_salida_utc, '%Y-%m')) as anio_mes,
        p.peso_bascula_neto_kg,
        d.peso_doc_kg,
        case
            when d.peso_doc_kg is not null and d.peso_doc_kg > 0
            and abs(p.peso_bascula_neto_kg - d.peso_doc_kg) / d.peso_doc_kg > 0.02
            then 1 else 0
        end as tiene_discrepancia
    from pesajes p
    join partidas d on d.id_viaje = p.id_viaje
    left join embarques e on e.id_viaje = p.id_viaje
)

select
    cast(anio_mes as varchar) as anio_mes,
    cast(cla_planta as integer) as cla_planta,
    cast(count(*) as integer) as num_viajes_pesados,
    cast(sum(tiene_discrepancia) as integer) as num_viajes_con_discrepancia,
    cast(round(100.0 * sum(tiene_discrepancia) / nullif(count(*), 0), 2) as decimal(18, 2)) as pct_viajes_con_discrepancia
from viajes_pesados
group by anio_mes, cla_planta
