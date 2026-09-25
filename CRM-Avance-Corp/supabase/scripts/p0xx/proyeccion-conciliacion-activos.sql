-- SOLO LECTURA en producción ANTES del merge: proyecta el backfill S1.
-- No expone números de cuenta ni CCI. Repetir el reporte real de S1 tras merge.
with slots as (
  select p.id as cliente_id, x.moneda, x.banco, x.tipo_cuenta,
         x.numero_cuenta, x.cci, x.titular_distinto,
         x.beneficiario_nombre, x.beneficiario_dni,
         not (x.banco is null and x.tipo_cuenta is null
           and x.numero_cuenta is null and x.cci is null
           and not coalesce(x.titular_distinto, false)
           and x.beneficiario_nombre is null and x.beneficiario_dni is null)
           as poblado
  from public.perfiles p
  cross join lateral (values
    ('PEN', p.banco, p.tipo_cuenta, p.numero_cuenta, p.cci,
     p.titular_distinto, p.beneficiario_nombre, p.beneficiario_dni),
    ('USD', p.banco_usd, p.tipo_cuenta_usd, p.numero_cuenta_usd, p.cci_usd,
     p.titular_distinto_usd, p.beneficiario_nombre_usd, p.beneficiario_dni_usd)
  ) x(moneda, banco, tipo_cuenta, numero_cuenta, cci,
      titular_distinto, beneficiario_nombre, beneficiario_dni)
  where p.rol = 'cliente'
), n as (
  select s.cliente_id, s.moneda, s.poblado,
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
), estado_perfil as (
  select n.*,
    (not (n.numero_con_espacio or n.cci_con_espacio or n.beneficiario_con_espacio)
      and pg_catalog.length(n.banco) between 1 and 100
      and n.tipo_cuenta in ('ahorros', 'corriente')
      and n.numero_cuenta ~ '^[A-Za-z0-9-]{1,30}$'
      and n.cci ~ '^[0-9]{20}$'
      and (not n.titular_distinto or (
        pg_catalog.length(n.beneficiario_nombre) between 1 and 200
        and n.beneficiario_dni ~ '^[0-9]{8,12}$'))) as valida
  from n
), evaluadas as (
  select e.*,
    exists (
      select 1 from crm.cuentas_bancarias cb
      where cb.cliente_id = e.cliente_id and cb.moneda = e.moneda
        and cb.activa is true and cb.cci = e.cci
    ) as mismo_cci,
    exists (
      select 1 from crm.cuentas_bancarias cb
      where cb.cliente_id = e.cliente_id and cb.moneda = e.moneda
        and cb.activa is true and cb.cci = e.cci
        and pg_catalog.lower(cb.banco) = pg_catalog.lower(e.banco)
        and cb.tipo_cuenta = e.tipo_cuenta
        and cb.numero_cuenta = e.numero_cuenta
        and cb.titular_distinto = e.titular_distinto
        and cb.beneficiario_nombre is not distinct from e.beneficiario_nombre
        and cb.beneficiario_dni is not distinct from e.beneficiario_dni
    ) as equivalente
  from estado_perfil e
), candidatas as (
  select cb.cliente_id, cb.moneda
  from crm.cuentas_bancarias cb where cb.activa is true
  union all
  select e.cliente_id, e.moneda
  from evaluadas e
  where e.poblado and e.valida and not e.mismo_cci and not e.equivalente
), conteo as (
  select c.cliente_id, c.moneda, pg_catalog.count(*) as cantidad
  from candidatas c group by c.cliente_id, c.moneda
), pendientes as (
  select ct.numero_contrato, cli.nombre_completo as cliente, cli.dni,
         ct.moneda, coalesce(analista.nombre_completo, 'Sin analista asignado') as analista,
         case
           when e.poblado and (not e.valida or (e.mismo_cci and not e.equivalente))
             then 'perfil_conflictivo'
           when coalesce(c.cantidad, 0) = 0 then 'sin_cuenta'
           when c.cantidad > 1 then 'cuentas_ambiguas'
           else null
         end as motivo
  from public.contratos ct
  join public.perfiles cli on cli.id = ct.cliente_id
  left join public.perfiles analista on analista.id = cli.asesor_perfil_id
  left join evaluadas e on e.cliente_id = ct.cliente_id and e.moneda = ct.moneda
  left join conteo c on c.cliente_id = ct.cliente_id and c.moneda = ct.moneda
  where ct.estado = 'activo'
    and not exists (
      select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = ct.id)
)
select numero_contrato, cliente, dni, moneda, analista, motivo
from pendientes where motivo is not null
order by analista, cliente, moneda, numero_contrato;
