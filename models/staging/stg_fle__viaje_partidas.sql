with partidas as (
    {{ cdc_latest(source('landing_fle', 'fle_viaje_det'), ['IdViaje', 'IdPartida']) }}
)

select
    cast(IdViaje as integer) as id_viaje,
    cast(IdPartida as integer) as id_partida,
    cast(ClaCliente as integer) as cla_cliente,
    cast(ClaArticulo as integer) as cla_articulo,
    cast(replace(PesoKg, ',', '') as decimal(18, 3)) as peso_kg,
    cast(_ab_cdc_lsn as bigint) as cdc_lsn,
    cast(_ab_cdc_updated_at as timestamp) as cdc_updated_at_utc
from partidas
