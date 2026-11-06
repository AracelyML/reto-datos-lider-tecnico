with basculas as (
    {{ cdc_latest(source('landing_bas', 'bas_bascula'), ['ClaPlanta', 'ClaBascula']) }}
)
select
    cast(ClaPlanta as integer) as cla_planta,
    cast(ClaBascula as integer) as cla_bascula,
    trim(NomBascula) as nom_bascula,
    cast(_ab_cdc_lsn as bigint) as cdc_lsn,
    cast(_ab_cdc_updated_at as timestamp) as cdc_updated_at_utc
from basculas
