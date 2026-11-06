with pesajes as (
    select * from {{ ref('stg_bas__pesajes') }}
),

entradas as (
    select
        id_viaje,
        cla_planta,
        cla_bascula,
        fecha_hora_utc as fecha_entrada_utc,
        case when unidad_peso = 'LB' then peso * 0.45359237 else peso end as peso_entrada_kg
    from pesajes
    where tipo_pesaje = 'E'
    qualify row_number() over (partition by id_viaje order by fecha_hora_utc) = 1
),

salidas as (
    select
        id_viaje,
        cla_planta,
        cla_bascula,
        fecha_hora_utc as fecha_salida_utc,
        case when unidad_peso = 'LB' then peso * 0.45359237 else peso end as peso_salida_kg
    from pesajes
    where tipo_pesaje = 'S'
    qualify row_number() over (partition by id_viaje order by fecha_hora_utc desc) = 1
)

select
    coalesce(e.id_viaje, s.id_viaje) as id_viaje,
    coalesce(e.cla_planta, s.cla_planta) as cla_planta,
    coalesce(e.cla_bascula, s.cla_bascula) as cla_bascula,
    e.fecha_entrada_utc,
    s.fecha_salida_utc,
    e.peso_entrada_kg,
    s.peso_salida_kg,
    case 
        when s.peso_salida_kg is not null and e.peso_entrada_kg is not null 
        then s.peso_salida_kg - e.peso_entrada_kg 
    end as peso_bascula_neto_kg,
    case 
        when s.fecha_salida_utc is not null and e.fecha_entrada_utc is not null 
        then date_diff('second', e.fecha_entrada_utc, s.fecha_salida_utc) / 60.0 
    end as estancia_minutos
from entradas e
full outer join salidas s on s.id_viaje = e.id_viaje
