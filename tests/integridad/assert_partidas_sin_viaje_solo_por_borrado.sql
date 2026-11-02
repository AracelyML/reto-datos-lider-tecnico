{#-
    Relación partidas → viajes. No puede ser un relationships estricto: el origen borra viajes
    sin borrar sus partidas. Falla si una partida apunta a un viaje que nunca existió en la réplica,
    que es un defecto del origen a escalar.
-#}
with viajes_borrados as (
    select distinct cast(IdViaje as integer) as id_viaje
    from {{ source('landing_fle', 'fle_viaje') }}
    where _ab_cdc_deleted_at is not null
)

select p.id_viaje, p.id_partida
from {{ ref('stg_fle__viaje_partidas') }} p
left join {{ ref('stg_fle__viajes') }} v on v.id_viaje = p.id_viaje
left join viajes_borrados b on b.id_viaje = p.id_viaje
where v.id_viaje is null
  and b.id_viaje is null
