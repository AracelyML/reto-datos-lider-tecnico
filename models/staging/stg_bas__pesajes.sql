with pesajes as (
    {{ cdc_latest(source('landing_bas', 'bas_pesaje'), ['IdPesaje']) }}
)
select
    cast(IdPesaje as integer) as id_pesaje,
    cast(ClaPlanta as integer) as cla_planta,
    cast(ClaBascula as integer) as cla_bascula,
    cast(IdViaje as integer) as id_viaje,
    {{ clean_code('TipoPesaje') }} as tipo_pesaje,
    cast(FechaHoraUTC as timestamp) as fecha_hora_utc,
    cast(Peso as decimal(18, 4)) as peso,
    {{ clean_code('UnidadPeso') }} as unidad_peso,
    cast(_ab_cdc_lsn as bigint) as cdc_lsn,
    cast(_ab_cdc_updated_at as timestamp) as cdc_updated_at_utc
from pesajes
