-- Solo lectura. Replica la validacion y normalizacion del backfill S1.
-- Cuenta las excepciones sin mostrar numero de cuenta, CCI ni beneficiario.
with slots as (
  select p.id as cliente_id, x.moneda, x.banco, x.tipo_cuenta,
         x.numero_cuenta, x.cci, x.titular_distinto,
         x.beneficiario_nombre, x.beneficiario_dni
  from public.perfiles p
  cross join lateral (values
    ('PEN', p.banco, p.tipo_cuenta, p.numero_cuenta, p.cci,
     p.titular_distinto, p.beneficiario_nombre, p.beneficiario_dni),
    ('USD', p.banco_usd, p.tipo_cuenta_usd, p.numero_cuenta_usd, p.cci_usd,
     p.titular_distinto_usd, p.beneficiario_nombre_usd, p.beneficiario_dni_usd)
  ) x(moneda, banco, tipo_cuenta, numero_cuenta, cci,
      titular_distinto, beneficiario_nombre, beneficiario_dni)
  where p.rol = 'cliente'
), normalizadas as (
  select s.cliente_id, s.moneda,
         pg_catalog.btrim(coalesce(s.banco, '')) as banco,
         pg_catalog.lower(pg_catalog.btrim(coalesce(s.tipo_cuenta, ''))) as tipo_cuenta,
         pg_catalog.upper(pg_catalog.btrim(coalesce(s.numero_cuenta, ''))) as numero_cuenta,
         pg_catalog.btrim(coalesce(s.cci, '')) as cci,
         coalesce(s.titular_distinto, false) as titular_distinto,
         case when coalesce(s.titular_distinto, false)
           then pg_catalog.upper(pg_catalog.regexp_replace(
             pg_catalog.btrim(coalesce(s.beneficiario_nombre, '')), '\s+', ' ', 'g'))
           else null end as beneficiario_nombre,
         case when coalesce(s.titular_distinto, false)
           then pg_catalog.btrim(coalesce(s.beneficiario_dni, ''))
           else null end as beneficiario_dni,
         coalesce(s.numero_cuenta, '') ~ '[[:space:]]' as numero_con_espacio,
         coalesce(s.cci, '') ~ '[[:space:]]' as cci_con_espacio,
         (coalesce(s.titular_distinto, false)
           and coalesce(s.beneficiario_dni, '') ~ '[[:space:]]') as beneficiario_con_espacio
  from slots s
), validas as (
  select n.*
  from normalizadas n
  where not (n.numero_con_espacio or n.cci_con_espacio
             or n.beneficiario_con_espacio)
    and pg_catalog.length(n.banco) between 1 and 100
    and n.tipo_cuenta in ('ahorros', 'corriente')
    and n.numero_cuenta ~ '^[A-Za-z0-9-]{1,30}$'
    and n.cci ~ '^[0-9]{20}$'
    and (not n.titular_distinto or (
      pg_catalog.length(n.beneficiario_nombre) between 1 and 200
      and n.beneficiario_dni ~ '^[0-9]{8,12}$'))
), sin_equivalente as (
  select v.*
  from validas v
  where not exists (
    select 1 from crm.cuentas_bancarias cb
    where cb.cliente_id = v.cliente_id and cb.moneda = v.moneda
      and cb.activa is true and cb.cci = v.cci
      and pg_catalog.lower(cb.banco) = pg_catalog.lower(v.banco)
      and cb.tipo_cuenta = v.tipo_cuenta
      and cb.numero_cuenta = v.numero_cuenta
      and cb.titular_distinto = v.titular_distinto
      and cb.beneficiario_nombre is not distinct from v.beneficiario_nombre
      and cb.beneficiario_dni is not distinct from v.beneficiario_dni)
)
select (select pg_catalog.count(*) from validas) as perfiles_validos,
       (select pg_catalog.count(*) from sin_equivalente) as sin_equivalente,
       (select pg_catalog.count(*) from sin_equivalente v
        where exists (
          select 1 from crm.cuentas_bancarias cb
          where cb.cliente_id = v.cliente_id and cb.moneda = v.moneda
            and cb.cci = v.cci and cb.activa is true
        )) as mismo_cci_datos_distintos;
