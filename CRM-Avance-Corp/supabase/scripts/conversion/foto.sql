-- FOTO DE LA CONVERSIÓN — SOLO LECTURA.
--
-- Devuelve UNA fila con UNA columna json: todo lo que define la conversión de
-- un mes por los cuatro caminos, más el desglose y el reparto por analista.
-- Sirve para lo único que importa al refactorizar: comprobar que un cambio
-- NO MUEVE NINGÚN NÚMERO.
--
-- No salen nombres de personas: los analistas viajan por id. El archivo que se
-- guarda como referencia se puede versionar sin exponer a nadie.
--
-- Uso:
--   supabase db query --linked --file supabase/scripts/conversion/foto.sql
-- Las fechas se cambian abajo, en `parametros`.
begin transaction read only;

do $impersonar$ begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', (select p.id from public.perfiles p
            where private.rol_crm(p.id) = 'gerencia' and p.activo order by p.id limit 1),
    'role', 'authenticated')::text, true);
end $impersonar$;

with parametros as (
  -- 🔴 LA VENTANA SE CALCULA, NO SE ESCRIBE A MANO. Estuvo fijada al
  -- '2026-09-21' y el 22/09 la foto salió ROJA: `crm.conversion_mensual_fn`
  -- IGNORA el `hasta` y responde por el MES ENTERO, mientras el rango y la
  -- distribución respondían del 1 al 21. La foto comparaba un rango parcial
  -- contra un mes completo — el mismo error que este gate existe para cazar,
  -- dentro del propio gate. Con la ventana al día los cuatro caminos coinciden.
  --
  -- «Mes completo», para el mes vigente, es del día 1 A HOY: es la definición
  -- que ya usan `periodoMesCalendario` en el front y la puerta #4 en el
  -- servidor (`or p_hasta = v_hoy`). Y no puede pasar de hoy: la puerta valida
  -- el rango y responde «Periodo invalido».
  --
  -- Para fotografiar un mes PASADO, cambiar `mes` y poner `hasta` en su último
  -- día; para el vigente, dejarlo así.
  select date_trunc('month', (now() at time zone 'America/Lima'))::date as mes,
         least((now() at time zone 'America/Lima')::date,
               (date_trunc('month', (now() at time zone 'America/Lima'))
                 + interval '1 month' - interval '1 day')::date) as hasta
), ventana as (
  select mes, hasta,
         (mes::text || ' 00:00')::timestamp at time zone 'America/Lima' as ini,
         ((hasta + 1)::text || ' 00:00')::timestamp at time zone 'America/Lima' as fin,
         (date_trunc('month', mes) + interval '1 month')::date as mes_siguiente
  from parametros
), ep as (
  select e.* from ventana v, private.conversion_episodios(
    v.ini, v.fin, v.mes, true, null, private.peso_referido_conversion(v.mes)) e
), nucleo as (
  select jsonb_build_object(
    'divisor', sum(aporte_divisor),
    'numerador', round(sum(aporte_numerador), 4),
    'pct', round(100.0 * sum(aporte_numerador) / nullif(sum(aporte_divisor), 0), 2)) j
  from ep
), desglose as (
  select jsonb_agg(x order by x->>'tipo', x->>'origen') j from (
    select jsonb_build_object(
      'tipo', tipo, 'origen', coalesce(origen, '—'), 'hechos', count(*),
      'al_divisor', sum(aporte_divisor),
      'al_numerador', round(sum(aporte_numerador), 4)) x
    from ep group by tipo, origen) t
), deuda as (
  -- La deuda por cierres anulados de meses YA SELLADOS, pendiente de saldar.
  select ap.vendedor_id, ap.numerador as pendiente
  from private.ajuste_pendiente_por_vendedor() ap
), por_analista as (
  select e.analista_id, sum(e.aporte_divisor) as divisor, sum(e.aporte_numerador) as bruto
  from ep e where e.analista_id is not null group by e.analista_id
), conciliacion as (
  -- 🔑 EL TOPE SE APLICA POR VENDEDOR, no sobre los totales.
  -- `private.conversion_con_ajuste` es `greatest(num - pend, 0)`: si la deuda de
  -- alguien supera su bruto, su neto es 0 y la diferencia NO es la resta limpia.
  -- Restar sobre los totales daria otro numero, y seria un falso verde.
  select jsonb_build_object(
    'bruto_numerador',  round(sum(pa.bruto), 4),
    'neto_numerador',   round(sum(private.conversion_con_ajuste(pa.bruto, d.pendiente)), 4),
    'deuda_pendiente',  round(coalesce(sum(d.pendiente), 0), 4),
    'deuda_aplicada',   round(sum(pa.bruto)
                              - sum(private.conversion_con_ajuste(pa.bruto, d.pendiente)), 4),
    'vendedores_con_deuda', count(*) filter (where coalesce(d.pendiente, 0) > 0),
    'vendedores_topados',   count(*) filter (where coalesce(d.pendiente, 0) > pa.bruto)) j
  from por_analista pa left join deuda d on d.vendedor_id = pa.analista_id
), mensual as (
  select crm.conversion_mensual_fn(v.mes) j from ventana v
), rango as (
  select crm.metricas_conversiones_fn(v.mes, v.hasta, null) j from ventana v
), distrib as (
  select crm.metricas_distribucion_leads_v3_fn(v.mes, v.hasta) j from ventana v
), analistas as (
  select jsonb_agg(jsonb_build_object(
      'vendedor_id', r->>'vendedor_id',
      'divisor', (r->>'divisor')::numeric,
      'numerador', (r->>'numerador')::numeric,
      'pct', (r->>'conversion_pct')::numeric)
    order by r->>'vendedor_id') j
  from mensual m, jsonb_array_elements(m.j->'responsables') r
), ledger as (
  select jsonb_build_object(
    'leads_etapa_convertido', (select count(*) from crm.leads where etapa='convertido'),
    'leads_con_cierre_ledger', (select count(distinct lead_id) from crm.lead_asignaciones where resultado='convertido'),
    'convertidos_sin_ledger', (select count(*) from crm.leads l where l.etapa='convertido'
       and not exists (select 1 from crm.lead_asignaciones la where la.lead_id=l.id and la.resultado='convertido')),
    'ledger_sin_etapa_convertido', (select count(*) from crm.leads l where l.etapa<>'convertido'
       and exists (select 1 from crm.lead_asignaciones la where la.lead_id=l.id and la.resultado='convertido')),
    'cierres_anulados', (select count(*) from crm.lead_asignaciones la
       where la.resultado='convertido' and private.cierre_externo_anulado(la.lead_id)),
    'mes_convertido_en_distinto_del_ledger', (select count(*) from crm.leads l
       join crm.lead_asignaciones la on la.lead_id=l.id and la.resultado='convertido'
       where l.convertido_en is not null
         and date_trunc('month', l.convertido_en at time zone 'America/Lima')
           <> date_trunc('month', coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')),
    'ops_elegibles', (select count(*) from crm.operaciones_cartera where elegible_conversion),
    'periodos_cerrados', (select count(*) from crm.periodos_cerrados)) j
)
select jsonb_pretty(jsonb_build_object(
  'version', 2,
  'mes', (select mes from ventana), 'hasta', (select hasta from ventana),
  'caminos', jsonb_build_object(
    'nucleo_directo', (select j from nucleo),
    'mensual', jsonb_build_object(
      'divisor', (select (j->'total'->>'divisor')::numeric from mensual),
      'numerador', (select (j->'total'->>'numerador')::numeric from mensual),
      'pct', (select (j->'total'->>'conversion_pct')::numeric from mensual),
      'cerrado', (select j->'cierre'->>'cerrado' from mensual)),
    'rango', jsonb_build_object(
      'divisor', (select (j->'nucleo'->>'divisor')::numeric from rango),
      'numerador', (select (j->'nucleo'->>'numerador')::numeric from rango),
      'pct', (select (j->'nucleo'->>'conversion_pct')::numeric from rango),
      'cuadra', (select j->'sondas'->>'cuadra' from rango)),
    'distribucion', jsonb_build_object(
      'divisor', (select (j->'resumen'->'conversion'->>'nucleo_divisor')::numeric from distrib),
      'numerador', (select (j->'resumen'->'conversion'->>'nucleo_numerador')::numeric from distrib),
      'pct', (select (j->'resumen'->'conversion'->>'nucleo_conversion_pct')::numeric from distrib))),
  'conciliacion', (select j from conciliacion),
  'cobertura', (select j->'cobertura' from mensual),
  'desglose', (select j from desglose),
  'analistas', (select j from analistas),
  'ledger', (select j from ledger)
)) as foto;

rollback;
