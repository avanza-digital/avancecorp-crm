-- reversa-b11.sql — deshace 20261006042144_crm_bases_cargadas_conversion.sql y deja el estado vivo de ANTES, byte a byte:
-- los diez cuerpos (md5 de prosrc de producción, 05/10/2026), las firmas viejas de private.conversion_divisor_empresa y de
-- private.conversion_divisor_empresa_totales (sin cierres_base_cargada) con su ACL y su comentario, el comentario de la puerta
-- de coordinación, las cuatro huellas del censo analítico (resellado) y SIN el ayudante.
-- Se NIEGA si ya hay cierres de contactos de base: revertir les quitaría su peso (un número que la gente ya vio).
-- Se NIEGA también si otra función (fuera de las diez de B11) ya llama al ayudante: borrarlo la dejaría rota y pg_depend
-- no ve esa llamada; y si el censo analítico no está vigente y sellado antes de empezar (no se resella sobre un sello roto).
-- Antes de revertir en producción: publicar la pantalla anterior NO hace falta (la pantalla nueva tolera la clave ausente).
-- Uso: psql … -X -v ON_ERROR_STOP=1 -c "$(cat supabase/scripts/base-gestion/reversa-b11.sql)"   (un mensaje, como la migración)

begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
declare r record;
begin
  if not exists (select 1 from pg_locks l
                  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.mode = 'ExclusiveLock'
                    and l.objsubid = 1
                    and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'reversa B11: falta el candado de migraciones' using errcode = 'P0409';
  end if;
  for r in select * from (values
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])', '155ce2b12754718388c8ca1644c84c90', '{postgres=X/postgres}'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', 'fec614f0df11c6d411bf132c776cce6e', '{postgres=X/postgres}'),
    ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)', '2f0f891b41b25c902d6cfd4ab369af5d', '{postgres=X/postgres}'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', '09e538d7be92bf8755411bec0737b34d', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.metricas_conversiones_implementacion(date,date,text)', '309c951204d9cd81a38ed049d1319d06', '{postgres=X/postgres}'),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)', '41df911eccb0e66021760335145bb0e1', '{postgres=X/postgres}'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', '417defaf8d982bfc628b3469984fa802', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa(date,date)', 'bf90ba99a8404c0889606354ef289335', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa_totales(date,date)', 'cf38266452df03960ca07d856d59b346', '{postgres=X/postgres}'),
    ('crm.conversion_divisor_coordinacion_fn(date,date,date)', 'b7dd99499a7668938a1417b259bc0626', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.conversion_origen_con_cierre(text)', '3c7ded558914426ea4f6a08830db1b43', '{postgres=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'reversa B11: % no es el de B11; revisar antes de revertir', r.firma using errcode = 'P0409';
    end if;
  end loop;
  -- Nadie fuera de las piezas de B11 llama al ayudante que se va a borrar (pg_depend no ve las llamadas en el texto).
  if exists (select 1 from pg_proc p
              where p.prosrc like '%conversion_origen_con_cierre%'
                and p.oid not in (to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'), to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'), to_regprocedure('private.conversion_divisor_empresa(date,date)'), to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'), to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'),
                                  to_regprocedure('private.conversion_origen_con_cierre(text)'))) then
    raise exception 'reversa B11: otra función ya usa private.conversion_origen_con_cierre; no se puede borrar' using errcode = 'P0409';
  end if;
  -- Las dos privadas del divisor (drop + create) siguen con sus dos únicos llamadores.
  if exists (select 1 from pg_proc p
              where p.prosrc ~ 'conversion_divisor_empresa(_totales)?\s*\('
                and p.oid not in (to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'),
                                  to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'))) then
    raise exception 'reversa B11: hay un llamador nuevo del divisor de empresa; revisar antes de revertir' using errcode = 'P0409';
  end if;
  -- El censo analítico se resella al final: antes debe estar vigente (las cuatro declaraciones) y con el sello al día.
  if (select count(*) from private.analitica_leads_citas_exenciones e
        join pg_proc p on p.oid = to_regprocedure(e.objeto)
       where to_regprocedure(e.objeto) in (to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'))
         and e.huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))) <> 4 then
    raise exception 'reversa B11: una declaracion analitica de las funciones tocadas no esta vigente' using errcode = 'P0409';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'reversa B11: el sello del censo analitico no esta al dia' using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id
              where la.resultado = 'convertido' and l.origen = 'base_cargada')
     or exists (select 1 from crm.conversion_acreditaciones ca where ca.origen = 'base_cargada') then
    raise exception 'reversa B11: ya hay cierres de contactos de base; revertir les quitaría su peso' using errcode = 'P0409';
  end if;
end;
$preflight$;

create temporary table b11_censo_antes on commit drop as
  select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c;

-- private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[]): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION private.conversion_cierres(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric, p_leads uuid[])
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select 'cierre'::text, la.analista_id, la.lead_id, null::uuid,
  l.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(la.lead_id), l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  coalesce(la.resultado_en, la.finalizado_en), 0,
  case when private.cierre_externo_anulado(la.lead_id) then 0
    when l.origen = 'referido' then
      case when p_periodo is not null then p_factor else
        private.peso_referido_conversion(date_trunc('month',
          coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')::date) end
    when l.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.lead_asignaciones la
join crm.leads l on l.id = la.lead_id
where la.resultado = 'convertido'
  -- La política previa conserva agosto y todos los meses anteriores.
  and (not exists(select 1 from crm.conversion_politica where activada_en is not null)
    or coalesce(la.resultado_en, la.finalizado_en) < '2026-09-01 00:00:00 America/Lima'::timestamptz)
  and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
  and coalesce(la.resultado_en, la.finalizado_en) < p_fin
  and (p_global or la.analista_id = any(p_visibles))
  and (p_leads is null or la.lead_id in (select id from unnest(p_leads) seleccion(id)))
union all
select 'cierre'::text, ca.analista_id, ca.lead_id, null::uuid,
  ca.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(ca.lead_id), ca.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  ca.fecha_comercial::timestamp at time zone 'America/Lima', 0,
  case when private.cierre_externo_anulado(ca.lead_id) then 0
    when ca.origen = 'referido' then
      case when p_periodo is not null then p_factor
        else private.peso_referido_conversion(ca.periodo_comercial) end
    when ca.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.conversion_acreditaciones ca
join crm.leads l on l.id=ca.lead_id
where ca.estado='acreditada'
  and exists(select 1 from crm.conversion_politica where activada_en is not null)
  -- No reabrir agosto por la acreditación en septiembre de un contrato viejo.
  and ca.periodo_comercial >= date '2026-09-01'
  and (ca.fecha_comercial::timestamp at time zone 'America/Lima') >= p_ini
  and (ca.fecha_comercial::timestamp at time zone 'America/Lima') < p_fin
  and (p_global or ca.analista_id = any(p_visibles))
  and (p_leads is null or ca.lead_id in (select id from unnest(p_leads) seleccion(id)))
  -- Una fuente retirada no sigue fabricando cierres en un mes abierto.
  -- El hecho y su auditoría sobreviven; un mes sellado se sirve por su foto.
  and private.conversion_exclusion_fuente(ca.fuente_tipo,ca.fuente_id)='elegible';
$function$;

-- private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION private.registrar_ajuste_si_mes_cerrado(p_lead_id uuid, p_motivo text, p_por uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;
  v_acreditacion crm.conversion_acreditaciones%rowtype;
  v_acreditacion_actual crm.conversion_acreditaciones%rowtype;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- Desde septiembre, el reloj de crédito y la prueba de que SE ABONÓ salen
  -- del hecho de acreditación, no del mes de leads.convertido_en.
  if exists(select 1 from crm.conversion_politica where activada_en is not null)
    and exists(select 1 from crm.lead_asignaciones la where la.lead_id=p_lead_id
    and la.resultado='convertido' and coalesce(la.resultado_en,la.finalizado_en)
      >= '2026-09-01 00:00 America/Lima'::timestamptz) then
    select * into v_acreditacion
    from crm.conversion_acreditaciones ca where ca.lead_id=p_lead_id
      and ca.estado='acreditada' and ca.periodo_comercial>=date '2026-09-01';
    if not found then return null; end if;
    v_periodo:=v_acreditacion.periodo_comercial;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    select * into v_acreditacion_actual from crm.conversion_acreditaciones where lead_id=p_lead_id;
    if v_acreditacion_actual is distinct from v_acreditacion then
      raise exception 'La acreditacion cambio durante la anulacion; vuelve a intentar' using errcode='PT409';
    end if;
    if not exists(select 1 from crm.periodos_cerrados pc where pc.periodo=v_periodo) then
      return null;
    end if;
    if v_acreditacion.incluida_en_sello is distinct from true then return null; end if;
    v_acreditado:=v_acreditacion.analista_id;
    v_numerador:=case when v_acreditacion.origen='referido' then
      private.peso_referido_conversion(v_periodo)
      when v_acreditacion.origen in ('landing','formulario') then 1 else 0 end;
    if v_acreditado is null or v_numerador<=0 then return null; end if;
    -- Para referidos prevalece el peso de la foto que efectivamente se pagó.
    if exists(select 1 from crm.conversion_acreditaciones ca
      where ca.lead_id=p_lead_id and ca.origen='referido') then
      select pc.ponderacion_referido into v_numerador from crm.periodos_cerrados pc
        where pc.periodo=v_periodo;
    end if;
    if v_numerador is null or v_numerador<=0 then return null; end if;
  else
  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  -- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;

  end if;

  -- ATR-4 (Miguel 31/08): «solo la conversion, siempre». La deuda de un mes
  -- sellado ya NO carga capital: el capital del analista se queda en su
  -- produccion y el de la empresa en el AUM. Solo se descuenta la conversion.
  v_pen := 0; v_usd := 0; v_detalle := '[]'::jsonb;

  -- Con capital siempre 0, la deuda existe SOLO si la conversion valia algo.
  -- numerador 0 (cierre sin episodio) => NULL POR DISENO declarado: el rastro
  -- queda en la alerta del vigia (f6c_ajuste_sin_episodio) y en la anulacion
  -- misma; no se fabrica una deuda vacia.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;

$function$;

-- private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION private.conversion_mensual_por_vendedor(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(analista_id uuid, divisor integer, divisor_aproximado integer, divisor_por_motivo jsonb, cierres_no_referidos integer, cierres_referidos integer, cierres_de_arrastre integer, numerador numeric, conversion_pct numeric, procedencia jsonb, referidos_recibidos integer, referidos_aporta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
with ep as (
  select e.* from private.conversion_episodios(
    p_ini, p_fin,
    case when date_trunc('month', p_ini at time zone 'America/Lima') =
      date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')
      then date_trunc('month', p_ini at time zone 'America/Lima')::date end,
    p_global, p_visibles, p_factor
  ) e
), recibidos as (
  select e.analista_id, e.lead_id, e.fue_referido, e.motivo, e.aproximado, e.aporte_divisor
  from ep e where e.tipo = 'recibido'
), cierres as (
  select e.analista_id, e.lead_id, e.fue_referido, e.mes_origen,
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from ep e where e.tipo = 'cierre' and not e.anulado
    and e.origen in ('landing', 'formulario', 'referido')
), motivos as (
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r where r.aporte_divisor > 0
  group by r.analista_id, r.motivo
), motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m group by m.analista_id
), agg_div as (
  select r.analista_id,
    sum(r.aporte_divisor)::int as divisor,
    coalesce(sum(r.aporte_divisor) filter (where r.aproximado), 0)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r group by r.analista_id
), agg_cie as (
  select c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c group by c.analista_id
), aportes as (
  select e.analista_id,
    sum(e.aporte_divisor)::int as divisor,
    sum(e.aporte_numerador) as numerador,
    coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.fue_referido), 0) as aporte_referidos
  from ep e group by e.analista_id
), proc as (
  select c.analista_id, c.mes_cubo,
    (count(distinct c.lead_id) filter (where not c.fue_referido)
     + count(distinct c.lead_id) filter (where c.fue_referido))::int as cierres,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos
  from (
    select c0.analista_id, c0.lead_id, c0.fue_referido,
      case when
        (extract(year from p_ini at time zone 'America/Lima')::int * 12
         + extract(month from p_ini at time zone 'America/Lima')::int)
        - (extract(year from c0.mes_origen)::int * 12
           + extract(month from c0.mes_origen)::int) <= 11
      then c0.mes_origen end as mes_cubo
    from cierres c0
  ) c
  group by c.analista_id, c.mes_cubo
), proc_json as (
  select p.analista_id,
    jsonb_agg(jsonb_build_object(
      'mes', case when p.mes_cubo is not null then to_char(p.mes_cubo, 'YYYY-MM') end,
      'mes_nombre', case when p.mes_cubo is not null
        then private.etiqueta_mes_es(p.mes_cubo) else 'anteriores' end,
      'anio', case when p.mes_cubo is not null then extract(year from p.mes_cubo)::int end,
      'cierres', p.cierres, 'cierres_referidos', p.cierres_referidos
    ) order by p.mes_cubo desc nulls last) as procedencia
  from proc p group by p.analista_id
)
select
  a.analista_id,
  a.divisor,
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  a.numerador,
  case when a.divisor > 0 then round(100.0 * a.numerador / a.divisor, 2) end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  case when a.divisor > 0 then round(100.0 * a.aporte_referidos / a.divisor, 2) end
from aportes a
left join agg_div d on d.analista_id is not distinct from a.analista_id
left join agg_cie c on c.analista_id is not distinct from a.analista_id
left join motivos_json mj on mj.analista_id is not distinct from a.analista_id
left join proc_json pj on pj.analista_id is not distinct from a.analista_id;
end;
$function$;

-- crm.metricas_conversiones_equipo_fn(date,date): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION crm.metricas_conversiones_equipo_fn(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_mes_actual date := date_trunc('month', v_hoy)::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_cosecha_fin timestamptz;
  v_mes date;
  v_factor numeric;
  v_periodo date;
  v_es_mes_historico boolean := false;
  v_cerrado boolean := false;
  v_meta_periodo_id uuid;
  v_revision integer;
  v_cerrado_en timestamptz;
  v_cierre_automatico boolean;
  v_payload jsonb;
  v_oficial jsonb;
  v_sin_fila integer;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion de parametros (identica a la global).
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;

  -- 3) Ambito vigente por defecto. Solo un mes CERRADO lo sustituye por el
  -- ambito sellado; un historico aun abierto usa el mismo recorte vigente que
  -- cumplimiento_metas_fn durante la ventana de ajuste.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  -- La cosecha madura hasta hoy: un lead que entro en el rango puede cerrar
  -- despues, y esa maduracion es el sentido de la lectura por cosecha.
  v_cosecha_fin := greatest(v_fin, v_ahora);

  v_mes := date_trunc('month', p_hasta)::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- Identifica la foto mensual del roster; los rangos parciales también
  -- contienen cartera, siempre acotada por la fecha efectiva de operación.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  -- Solo un mes calendario ANTERIOR cambia de poblacion. Un rango libre y el
  -- mes actual conservan la semantica vigente de roster activo.
  v_es_mes_historico := v_periodo is not null and v_periodo < v_mes_actual;

  -- Para cualquier mes calendario (historico o el vigente) se publica el mismo
  -- token que conversion/cumplimiento. Un rango libre no finge tener revision.
  if v_periodo is not null then
    select pc.meta_revision, pc.cerrado_en, pc.automatico
      into v_revision, v_cerrado_en, v_cierre_automatico
    from crm.periodos_cerrados pc
    where pc.periodo = v_periodo;

    if found then
      v_cerrado := true;
    else
      v_cerrado := false;
      select mp.id, mp.revision into v_meta_periodo_id, v_revision
      from crm.meta_periodos mp
      where mp.periodo = v_periodo
      order by mp.revision desc
      limit 1;
      v_revision := coalesce(v_revision, 0);
    end if;
  end if;

  if v_es_mes_historico and v_cerrado and not v_global then
    -- El ambito de los episodios tambien debe ser el SELLADO. Cambiar solo
    -- las filas del roster mostraria al vendedor historico con ceros.
    select coalesce(
      array_agg(f.vendedor_id order by f.vendedor_id), '{}'::uuid[]
    ) into v_visibles
    from private.cierre_mes_visible(v_periodo, v_uid) f;
  end if;

  with roster as materialized (
    -- Mes sellado: quien estaba en la foto, con el supervisor de ese mes. No se
    -- vuelve a preguntar si hoy sigue activo o conserva rol de vendedor.
    select f.vendedor_id
    from private.cierre_mes_visible(v_periodo, v_uid) f
    where v_es_mes_historico and v_cerrado

    union all

    -- Mes historico aun abierto: ultima publicacion mensual, exactamente la
    -- poblacion que cumplimiento_metas_fn devuelve durante el ajuste.
    select mv.vendedor_id
    from crm.metas_vendedor mv
    where v_es_mes_historico
      and not v_cerrado
      and mv.meta_periodo_id = v_meta_periodo_id
      and (v_global or mv.vendedor_id = any(v_visibles))

    union all

    -- Mes actual y rangos libres: comportamiento anterior, sin cambios.
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where not v_es_mes_historico
      and e.rol_crm = 'vendedor'
      and e.activo is true
      and p.activo is true
      and (v_global or e.perfil_id = any(v_visibles))
  ),
  -- TABLA-BASE, ya recortada al ambito del que pregunta. Para un cierre, el
  -- array v_visibles fue sustituido por los vendedores de su foto.
  ep_flujo as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, v_global, v_visibles, v_factor
    ) e
  ),
  -- Esta pierna va GLOBAL a proposito. `cohorte` conserva el primer analista
  -- mientras el ledger acredita a quien lo cerro. El conjunto no
  -- sale al payload; solo prueba cierres de leads ya recortados en `cohorte`.
  ep_cosecha as materialized (
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null::date, true, '{}'::uuid[], v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
  ),
  cohorte as materialized (
    select e.lead_id, e.analista_id as vendedor_id,
      (e.lead_id in (select ec.lead_id from ep_cosecha ec)) as contrato
    from ep_flujo e
    where e.tipo = 'recibido' and e.analista_id is not null
  ),
  responsables_resumen as (
    select r.vendedor_id,
      count(c.lead_id)::int as leads,
      count(c.lead_id) filter (where c.contrato)::int as clientes
    from roster r
    left join cohorte c on c.vendedor_id = r.vendedor_id
    group by r.vendedor_id
  ),
  nucleo_vendedor as (
    select e.analista_id,
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
    from ep_flujo e
    group by e.analista_id
  ),
  comparacion as (
    select
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nucleo_vendedor nv
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, v_global, v_visibles, v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda_paridad as (
    select
      coalesce(sum(c.delta), 0) as desvio,
      count(*)::int as filas
    from comparacion c
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'alcance', case when v_global then 'global' else 'equipo' end,
    'revision', case when v_periodo is null then null else v_revision end,
    'cierre', case
      when v_periodo is null then null
      when v_cerrado then jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cerrado_en,
        'automatico', v_cierre_automatico
      )
      else jsonb_build_object('cerrado', false)
    end,
    'periodo', jsonb_build_object(
      'desde', p_desde,
      'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1,
      'zona', 'America/Lima'
    ),
    'nucleo', jsonb_build_object(
      'base', 'llegada_unica',
      'atribucion', 'primer_analista',
      -- 23/09/2026: publicaba `v_factor`, que es el peso del REFERIDO. El nucleo ya
      -- aplica el de la RENOVACION desde 20260923155859, asi que esta clave decia
      -- un peso y el calculo usaba otro. Hoy no se nota porque los dos valen 0,15;
      -- el dia que se separen, el front (`conversion-vendedores.ts:272`, que hace
      -- `peso_renovacion ?? peso_referido`) ponderaria el desglose de renovaciones
      -- con el peso equivocado. Se declara el que de verdad se aplica.
      'peso_renovacion', private.peso_renovacion_conversion(v_mes),
      'incluye_cartera', true,
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      -- DECLARACION (Ola 1a, 22/09/2026). Cuatro claves que NO cambian ninguna
      -- cifra: dicen de donde sale la que ya se publicaba.
      --   es_mes_calendario: el rango es un mes calendario completo (la
      --     condicion de Miguel del 21/09 para poder delegar en la mensual).
      --     Es exactamente `v_periodo is not null`, la misma prueba que esta
      --     funcion ya usaba para identificar la foto del roster.
      --   fuente: 'rango_vivo' SIEMPRE, porque esta puerta sigue calculando
      --     por su cuenta sobre ep_flujo. El dia que delegue, dira 'mensual'.
      --   sellado: null = «no se delego en la foto oficial». El estado del mes
      --     sigue viajando aparte, en el bloque `cierre`.
      --   ajuste_aplicado: false = esta puerta NO resta la deuda de anulacion
      --     de un mes ya sellado. Es el hecho que hace posible la discrepancia
      --     que esta ola viene a hacer VISIBLE antes de corregirla.
      'es_mes_calendario', v_periodo is not null,
      'fuente', 'rango_vivo',
      'sellado', null,
      'ajuste_aplicado', false
    ),
    'sondas', jsonb_build_object(
      'paridad_nucleo', sp.desvio,
      'paridad_filas', sp.filas,
      'cuadra', case when sp.desvio is null or sp.filas = 0 then null
                     else sp.desvio = 0 end,
      'divisor_fuera_del_roster', (
        select coalesce(sum(nv2.divisor), 0)::int
        from nucleo_vendedor nv2
        where nv2.analista_id is null
           or nv2.analista_id not in (select r2.vendedor_id from roster r2)
      ),
      'numerador_fuera_del_roster', (
        select coalesce(sum(
          nv3.numerador
        ), 0)
        from nucleo_vendedor nv3
        where nv3.analista_id is null
           or nv3.analista_id not in (select r3.vendedor_id from roster r3)
      ),
      'cierres_anulados', (
        select count(*)::int from ep_flujo e where e.tipo = 'cierre' and e.anulado
      ),
      'clientes_acreditados_a_otro_dueno', (
        select count(*)::int
        from cohorte c
        join crm.lead_asignaciones la on la.lead_id = c.lead_id
        where c.contrato
          and la.resultado = 'convertido'
          and la.analista_id is distinct from c.vendedor_id
      )
    ),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', rr.vendedor_id,
          'leads', rr.leads,
          'clientes', rr.clientes,
          'conversion_pct', case when rr.leads > 0
            then round(100.0 * rr.clientes / rr.leads, 1) end,
          'nucleo_divisor', coalesce(nv.divisor, 0),
          'nucleo_numerador', coalesce(
            nv.numerador, 0),
          'nucleo_conversion_pct', case when coalesce(nv.divisor, 0) > 0
            then round(100.0 * nv.numerador / nv.divisor, 2) end
        )
        order by rr.clientes desc, rr.leads desc, rr.vendedor_id
      )
      from responsables_resumen rr
      left join nucleo_vendedor nv on nv.analista_id = rr.vendedor_id
    ), '[]'::jsonb)
  ) into v_payload
  from sonda_paridad sp;

  -- ══ OLA 1b · LA SUSTITUCION ════════════════════════════════════════════
  -- REGLA DE MIGUEL (21/09/2026): mes calendario completo y sin filtro de
  -- fuente -> la cifra la sirve `crm.conversion_mensual_fn`. Esta funcion no
  -- tiene filtro de fuente en su firma, asi que la condicion se reduce a
  -- `v_periodo is not null`, que es la misma prueba que ya usaba.
  --
  -- Aqui la cifra es POR VENDEDOR: se reescriben las tres claves `nucleo_*` de
  -- cada fila con las de la oficial, emparejando por `vendedor_id`. Lo demas
  -- de la fila (`leads`, `clientes`, `conversion_pct` de la cohorte) es OTRA
  -- medida y no se toca.
  --
  -- El alcance NO se amplia: `crm.conversion_mensual_fn` recorta por
  -- `auth.uid()` igual que esta funcion, y su gate es mas ancho
  -- (vendedor/supervisor/gerencia/lector) que el de aqui
  -- (supervisor/gerencia/lector), asi que quien llega hasta este punto ya pasa
  -- el suyo.
  --
  -- Y si un vendedor del roster NO tiene fila en la oficial, su cifra no se
  -- fabrica: se cuenta en `sondas.sin_fila_en_la_oficial` para que la pantalla
  -- pueda ocultar el numero en vez de pintar un cero tranquilizador.
  if v_periodo is not null then
    v_oficial := crm.conversion_mensual_fn(v_periodo);

    select count(*)::int into v_sin_fila
      from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb)) f(e)
     where not exists (
       select 1 from jsonb_array_elements(coalesce(v_oficial -> 'responsables', '[]'::jsonb)) r(v)
        where (r.v ->> 'vendedor_id') = (f.e ->> 'vendedor_id'));

    v_payload := jsonb_set(v_payload, '{nucleo}',
      (v_payload -> 'nucleo') || jsonb_build_object(
        'fuente', 'mensual',
        'sellado', coalesce((v_oficial #>> '{cierre,cerrado}')::boolean, false),
        'ajuste_aplicado', true,
        -- 🔑 LA PONDERACION DE LA FOTO, al lado de la cifra de la foto. Cierra
        -- el P2 de Codex (23/09): una cifra sellada no puede publicarse sin
        -- decir con que pesos se calculo.
        --
        -- 🔴 ADITIVA, no sustitutiva, y eso es deliberado. La primera version
        -- movia `peso_referido`/`peso_renovacion` al peso sellado, y Codex lo
        -- refuto en la segunda vuelta con un contraejemplo: esas dos claves
        -- ROTULAN EL DESGLOSE (`conversion-vendedores.ts:258,272`), que se
        -- recalcula vivo. Un cliente con bundle viejo —que no conoce esta clave
        -- nueva— habria rotulado con el peso de la foto un desglose calculado
        -- con el peso de hoy. El servidor anterior publicaba ahi el vivo y
        -- acertaba: era una REGRESION. Asi, quien no conozca
        -- `ponderacion_oficial` ve exactamente lo de siempre.
        'ponderacion_oficial', v_oficial #> '{ponderacion}',
        -- El total del recalculo vivo, conservado al lado: sin el, la distancia
        -- entre la cifra oficial y la que esta funcion calcularia solo se podria
        -- deducir de una igualdad que la delegacion rompe. `NucleoEquipoSchema`
        -- del front es `v.object`, asi que la clave no molesta a nadie.
        'recalculo_vivo', jsonb_build_object(
          'divisor', (select coalesce(sum((f.e ->> 'nucleo_divisor')::int), 0)
                        from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb)) f(e)),
          'numerador', (select coalesce(sum((f.e ->> 'nucleo_numerador')::numeric), 0)
                        from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb)) f(e)))
        ), false);

    v_payload := jsonb_set(v_payload, '{sondas}',
      (v_payload -> 'sondas') || jsonb_build_object(
        'sin_fila_en_la_oficial', v_sin_fila), false);

    v_payload := jsonb_set(v_payload, '{responsables}',
      coalesce((
        select jsonb_agg(
          -- 🔴 A quien la oficial NO tiene, NO se le toca la cifra: se queda la
          -- que calculo esta funcion. Sobrescribirla con ceros le borraria de
          -- la pantalla lo que si tiene. (Medido el 22/09 en la puerta #5, que
          -- comparte esta trampa: 3 de 21 analistas sin fila en la oficial, y
          -- uno de ellos un SUPERVISOR ACTIVO con numerador 2.) Aqui hoy son
          -- 0, y `sondas.sin_fila_en_la_oficial` lo vigila.
          case when o.v is null then f.e
               else f.e || jsonb_build_object(
                 'nucleo_divisor', (o.v -> 'divisor'),
                 'nucleo_numerador', (o.v -> 'numerador'),
                 'nucleo_conversion_pct', (o.v -> 'conversion_pct'))
          end
          order by f.ord)
          from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb))
               with ordinality f(e, ord)
          left join lateral (
            select r.v from jsonb_array_elements(coalesce(v_oficial -> 'responsables', '[]'::jsonb)) r(v)
             where (r.v ->> 'vendedor_id') = (f.e ->> 'vendedor_id') limit 1
          ) o on true
      ), '[]'::jsonb), false);
  end if;

  -- Un roster mensual ya fue validado por su propia fuente. Volver a filtrarlo
  -- por el rol ACTUAL borraria precisamente a las bajas historicas. Rangos
  -- libres y mes actual conservan la defensa previa.
  if v_es_mes_historico then
    return v_payload;
  end if;

  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

-- private.metricas_conversiones_implementacion(date,date,text): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION private.metricas_conversiones_implementacion(p_desde date, p_hasta date, p_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_cosecha_fin timestamptz;
  v_ahora timestamptz := now();
  v_mes date;
  v_factor numeric;
  v_periodo date;
  v_payload jsonb;
  v_autorizado boolean;
  v_oficial jsonb;
begin
  select exists (
    select 1 from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo and e.rol_crm = 'gerencia'
  ) or private.es_lector_global() into v_autorizado;
  if v_uid is null or not coalesce(v_autorizado, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  -- La cosecha mira hasta HOY: un lead que entro en el rango puede haber
  -- cerrado despues, y esa maduracion es justamente lo que la lectura por
  -- cosecha responde («de ese lote, cuantos acabaron cerrando»).
  v_cosecha_fin := greatest(v_fin, v_ahora);

  -- Peso del referido del mes del `hasta` — la MISMA regla que usa el heroe
  -- de HOY para el mes del rango.
  v_mes := date_trunc('month', p_hasta)::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- El periodo identifica una ventana mensual; ya NO habilita/deshabilita
  -- cartera: el núcleo limita toda operación a su fecha efectiva en el rango.
  -- En rangos libres aplica el peso de cada mes dentro del propio núcleo.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  with vendedores_base as materialized (
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo and p.activo and e.rol_crm = 'vendedor'
  ),
  -- ── TABLA-BASE ──────────────────────────────────────────────────────────
  -- Flujo comercial del rango: llegadas únicas y aportes del núcleo.
  ep_flujo as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, true, null, v_factor
    ) e
  ),
  -- Cierres del ledger que sirven de numerador a la COSECHA: los de sus
  -- leads, ocurran cuando ocurran (hasta hoy). Sin anulados.
  ep_cosecha as materialized (
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null, true, null, v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
  ),
  cohorte_base as materialized (
    -- F1.3b: el capital del lead se mide por los caminos VIVOS y HASTA HOY
    -- (lectura de cosecha: «de ese lote, cuanto ha producido»): contratos del
    -- portal de su perfil + cierres en coops vigentes. Aqui muere la primera
    -- de las dos ultimas lecturas del enlace jamas poblado (leads.contrato_id).
    select l.id, l.origen, l.etapa, l.categoria_interes, l.creado_en,
      l.convertido_en, l.perfil_id, l.contrato_id, l.asignado_supervisor_id,
      l.creado_por, llegada.analista_id as vendedor_id,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           '-infinity'::timestamptz,
           'infinity'::timestamptz, true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           '-infinity'::timestamptz,
           'infinity'::timestamptz, true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_usd
    from ep_flujo llegada
    join crm.leads l on l.id = llegada.lead_id
    where llegada.tipo = 'recibido'
      -- Filtro de ORIGEN (pedido de Miguel 27/08): recorta el LOTE — cohorte,
      -- embudo, origenes, categorias, responsables y tendencia beben todos de
      -- aqui. 'sin_origen' selecciona los leads sin origen registrado. El
      -- nucleo y las sondas de paridad NO se filtran (miden el MES de la
      -- empresa y esta pantalla ya no los pinta): el payload declara el
      -- filtro en `origen_filtrado` para que nadie confunda las dos aguas.
      and (p_origen is null or coalesce(l.origen, 'sin_origen') = p_origen)
  ),
  -- N1: citas clasificadas por el núcleo, sobre el lote de llegadas. El
  -- instante disponible es vence_en (fecha prevista); no se inventa una fecha
  -- física de asistencia ni una identidad de persona distinta de lead_id.
  citas_reales_ep as materialized (
    select ce.*
    from private.citas_episodios(v_ini, v_ahora, v_ahora) ce
    where ce.realizada and ce.debio_ocurrir
  ),
  citas_reales_cohorte as materialized (
    select cb.id as lead_id,
      count(ce.tarea_id) filter (where ce.vence_en >= cb.creado_en)::int
        as citas_realizadas,
      count(ce.tarea_id) filter (where ce.vence_en < cb.creado_en)::int
        as citas_anteriores_al_alta
    from cohorte_base cb
    left join citas_reales_ep ce on ce.lead_id = cb.id
    group by cb.id
  ),
  senales as materialized (
    select cb.*,
      (cb.vendedor_id is not null or cb.asignado_supervisor_id is not null or exists (
        select 1 from crm.lead_asignaciones la where la.lead_id = cb.id
      )) as h_asignado,
      exists (
        select 1 from crm.actividades a
        where a.lead_id = cb.id and (
          a.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada')
          or (a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' in (
            'contactado','reunion_agendada','propuesta_enviada','convertido'
          ))
        )
      ) as h_contacto,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id and t.tipo = 'reunion'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'reunion_agendada'
      ) as h_reunion_agendada,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id
          and t.tipo = 'reunion' and t.estado = 'completada'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id and a.tipo = 'reunion_realizada'
      ) as h_reunion_realizada,
      exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'propuesta_enviada'
      ) or cb.etapa = 'propuesta_enviada' as h_propuesta,
      -- ANTES: (perfil_id is not null or etapa = 'convertido') / (contrato_id is not null)
      -- AHORA: el cierre del LEDGER, sin anulados. Un cierre anulado por
      -- gerencia deja de contar aqui igual que en el nucleo.
      (cb.id in (select ec.lead_id from ep_cosecha ec)) as h_cliente,
      (cb.id in (select ec.lead_id from ep_cosecha ec)) as h_contrato
    from cohorte_base cb
  ),
  cohorte as materialized (
    select s.*,
      (cr.citas_realizadas > 0) as cita_real,
      cr.citas_realizadas as citas_realizadas_reales,
      cr.citas_anteriores_al_alta,
      h_asignado as asignado,
      (h_contacto or h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as contactado,
      (h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_agendada,
      (h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_realizada,
      (h_propuesta or h_cliente or h_contrato) as propuesta,
      (h_cliente or h_contrato) as cliente,
      h_contrato as contrato
    from senales s
    join citas_reales_cohorte cr on cr.lead_id = s.id
  ),
  resumen as (
    select
      count(*)::int as leads,
      count(*) filter (where asignado)::int as asignados,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cita_real)::int as leads_con_cita_real,
      coalesce(sum(citas_realizadas_reales), 0)::int as citas_realizadas_reales,
      coalesce(sum(citas_anteriores_al_alta), 0)::int as citas_anteriores_al_alta,
      count(*) filter (where propuesta)::int as propuestas,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte
  ),
  -- ── NUCLEO (cifra principal) ────────────────────────────────────────────
  -- Se agrupa POR ANALISTA con la misma aritmetica del nucleo y luego se suma.
  -- OJO: el total NO tiene por que ser la suma de `responsables`: aqui entran
  -- TODOS los analistas con episodios (supervisores incluidos), mientras que
  -- `responsables` sale del roster de vendedores activos y ademas el wrapper
  -- publico elimina del array a quien no sea vendedor. La sonda
  -- `divisor_fuera_del_roster` mide exactamente ese hueco.
  nucleo_vendedor as (
    select e.analista_id,
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
    from ep_flujo e
    group by e.analista_id
  ),
  nucleo as (
    select
      coalesce(sum(nv.divisor), 0)::int as divisor,
      coalesce(sum(nv.referidos_recibidos), 0)::int as referidos_recibidos,
      coalesce(sum(nv.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(nv.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(nv.operaciones), 0)::int as operaciones,
      coalesce(sum(nv.numerador), 0)::numeric as numerador
    from nucleo_vendedor nv
  ),
  -- Sonda de paridad: cuando el rango es un mes exacto, este recomputo debe
  -- coincidir EXACTAMENTE con el nucleo. Si no, el front avisa.
  -- Sonda de paridad: compara TODOS los terminos (divisor, ambos tipos de
  -- cierre y el numerador entero — que es donde vive la cartera), y declara
  -- cuantas filas comparo: sin filas la paridad no prueba nada y se dice
  -- (`cuadra` = null), en vez de dar un cero tranquilizador y vacuo.
  comparacion as (
    select nv.analista_id as a_nuevo, cm.analista_id as a_nucleo,
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nucleo_vendedor nv
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, null, v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda_paridad as (
    select
      coalesce(sum(c.delta), 0) as desvio,
      count(*)::int as filas
    from comparacion c
  ),
  produccion as (
    select
      (select count(*)::int from crm.leads l
        where l.convertido_en >= v_ini and l.convertido_en < v_fin) as clientes,
      -- F1.3 (27/08): el enlace leads.contrato_id JAMAS se poblo (auditoria en
      -- prod: 0 enlaces historicos, S/ 0 eterno con capital real cerrado) y
      -- ningun flujo lo escribe. El camino VIVO es el perfil nacido del lead
      -- (leads.perfil_id = contratos.cliente_id) mas los cierres en
      -- cooperativas (crm.cierres_externos por lead, sin anulados). La columna
      -- contrato_id no se toca: en produccion no se borra nada.
      ((select count(*)::int from (select * from public.contratos where not es_demo) c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id))
       + (select count(*)::int from crm.cierres_externos ce
          where ce.anulado_en is null
            and (coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date between p_desde and p_hasta)) as contratos,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_usd,
      -- Sonda F1.3: convertidos del rango SIN rastro de capital (ni perfil ni
      -- cierre externo vigente). El hueco se declara; el front lo rotula.
      (select count(*)::int from crm.leads l
        where l.convertido_en >= v_ini and l.convertido_en < v_fin
          and l.perfil_id is null
          and not exists (select 1 from crm.cierres_externos ce
                          where ce.lead_id = l.id and ce.es_cierre_inicial and ce.anulado_en is null)) as sin_rastro
  ),
  origenes as (
    select coalesce(origen, 'sin_origen') as origen,
      count(*)::int as leads,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cita_real)::int as leads_con_cita_real,
      coalesce(sum(citas_realizadas_reales), 0)::int as citas_realizadas_reales,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados,
      coalesce(sum(capital_lead_pen), 0) as capital_pen,
      coalesce(sum(capital_lead_usd), 0) as capital_usd
    from cohorte group by coalesce(origen, 'sin_origen')
  ),
  categorias as (
    select coalesce(categoria_interes, 'sin_categoria') as categoria,
      count(*)::int as leads,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte group by coalesce(categoria_interes, 'sin_categoria')
  ),
  responsables_resumen as (
    select vb.vendedor_id,
      count(c.id)::int as leads,
      count(c.id) filter (where c.contactado)::int as contactados,
      count(c.id) filter (where c.reunion_realizada)::int as reuniones_realizadas,
      count(c.id) filter (where c.cita_real)::int as leads_con_cita_real,
      coalesce(sum(c.citas_realizadas_reales), 0)::int as citas_realizadas_reales,
      count(c.id) filter (where c.contrato)::int as contratos
    from vendedores_base vb
    left join cohorte c on c.vendedor_id = vb.vendedor_id
    group by vb.vendedor_id
  ),
  capital_responsables as (
    -- F1.3b: capital DEL RANGO por vendedor, por los caminos vivos — contratos
    -- del portal (fecha de cierre en el rango) de perfiles nacidos de SUS
    -- leads (el `in` dedupe si dos leads compartieran perfil) + sus cierres en
    -- coops del rango. Aqui muere la ULTIMA lectura del enlace jamas poblado.
    select vb.vendedor_id,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_usd
    from vendedores_base vb
  )
  select jsonb_build_object(
    'version', 1,
    'origen_filtrado', p_origen,
    'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1, 'zona', 'America/Lima'
    ),
    'nucleo', jsonb_build_object(
      -- ── EL CONTRATO DE LA UNIFICACION (Ola 1a: DECLARAR, sin sustituir) ────
      -- Esta puerta publica el NUMERO GRANDE de Resumen y Conversiones, y hoy
      -- lo CALCULA ella: `conversion_pct` sale de su propia division sobre
      -- `ep_flujo`. Llama a `conversion_mensual_por_vendedor`, pero SOLO dentro
      -- del CTE `comparacion`, cuya unica salida es `sondas.paridad_nucleo`:
      -- esa llamada nunca toca la clave publicada.
      --
      -- 🔑 ESTE PASO NO CAMBIA NI UN NUMERO. Solo DECLARA de donde sale. La
      -- sustitucion —pedirle el bloque a `crm.conversion_mensual_fn` cuando el
      -- rango es un mes completo— es el paso siguiente y va aparte, porque
      -- mueve el heroe que ve gerencia y merece su propio ensayo.
      --
      -- Mientras tanto, declarar ya sirve: el dia que exista un mes sellado o
      -- una deuda cruzando meses, esta pantalla dira EN SU PAQUETE que su cifra
      -- es un recalculo en vivo, en vez de callarlo. Hoy el desacuerdo seria
      -- mudo; con esto, es legible.
      --
      -- `v_periodo` YA distingue el mes calendario, y bien: exige dia 1, mismo
      -- mes, y fin de mes O HOY (regla de Miguel: para el mes vigente, «mes
      -- completo» es del 1 a hoy). `v_hoy` va en hora de Lima.
      'es_mes_calendario', v_periodo is not null,
      -- Hasta que se haga la sustitucion, SIEMPRE es un recalculo en vivo. Se
      -- dice tal cual: mentir aqui seria peor que callar.
      'fuente', 'rango_vivo',
      -- `null` = «no se delego, asi que no se sabe si el mes esta sellado».
      -- NO es lo mismo que `false`, que afirmaria que no lo esta.
      'sellado', null,
      -- Su numerador no descuenta la deuda por cierres anulados: esa resta vive
      -- en la LECTURA mensual, y esta puerta no la hace.
      'ajuste_aplicado', false,
      'llegadas', (select count(*) from ep_flujo e where e.tipo = 'recibido'),
      'altas_manuales', (select count(*) from ep_flujo e
        where e.tipo = 'recibido' and not e.fue_referido and e.aporte_divisor = 0),
      'renovaciones', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'renovacion'),
      'upgrades', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'upgrade'),
      'aporte_cartera', (select coalesce(sum(e.aporte_numerador), 0) from ep_flujo e where e.tipo = 'operacion'),
      'base', 'llegada_unica',
      'atribucion', 'primer_analista',
      -- 23/09/2026: publicaba `v_factor`, el peso del REFERIDO, mientras el nucleo
      -- ya aplica el de la RENOVACION. Misma correccion que en
      -- crm.metricas_conversiones_equipo_fn: se declara el que se aplica.
      'peso_renovacion', private.peso_renovacion_conversion(v_mes),
      'incluye_cartera', true,
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      'divisor', n.divisor,
      'referidos_recibidos', n.referidos_recibidos,
      'cierres_no_referidos', n.cierres_no_referidos,
      'cierres_referidos', n.cierres_referidos,
      'operaciones_cartera', n.operaciones,
      'numerador', n.numerador,
      -- DOS decimales, como el nucleo real: este numero DEBE poder compararse
      -- byte a byte con el heroe de HOY, no redondearse distinto.
      'conversion_pct', case when n.divisor > 0
        then round(100.0 * n.numerador / n.divisor, 2) end,
      'referidos_cierran_pct', case when n.referidos_recibidos > 0
        then round(100.0 * n.cierres_referidos / n.referidos_recibidos, 1) end
    ),
    'cosecha', jsonb_build_object(
      'base', 'alta',
      'madura_hasta', v_cosecha_fin,
      'leads', r.leads,
      'cerraron', r.clientes,
      'conversion_pct', case when r.leads > 0
        then round(100.0 * r.clientes / r.leads, 1) end
    ),
    'citas_reales', jsonb_build_object(
      'version', 1,
      'unidad', 'lead_id',
      'base', 'llegadas_unicas',
      'fecha_cita', 'vence_en',
      'seguimiento_hasta', v_ahora,
      'origen_filtrado', p_origen,
      'atribucion', 'primer_analista',
      'leads_base', r.leads,
      'leads_con_cita_real', r.leads_con_cita_real,
      'citas_realizadas', r.citas_realizadas_reales,
      'citas_anteriores_al_alta', r.citas_anteriores_al_alta,
      'pct_llegadas_con_cita_real', case when r.leads > 0
        then round(100.0 * r.leads_con_cita_real / r.leads, 1) end
    ),
    'conversion_operaciones', jsonb_build_object(
      'version', 1,
      'lectura', 'viva',
      'completo', true,
      'desde', p_desde,
      'hasta', p_hasta,
      'zona', 'America/Lima',
      'origen_filtrado', null,
      'cantidad', (
        select count(*)::int from ep_flujo e where e.tipo = 'operacion'
      ),
      'aporte_total', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e where e.tipo = 'operacion'
      ),
      'detalle', coalesce((
        select jsonb_agg(jsonb_build_object(
          'operacion_id', e.operacion_id,
          'analista_id', e.analista_id,
          'categoria', e.categoria,
          'periodo', e.mes_origen,
          'fecha_numerador', e.fecha_numerador,
          'aporte_numerador', e.aporte_numerador
        ) order by e.fecha_numerador, e.operacion_id)
        from ep_flujo e
        where e.tipo = 'operacion' and e.operacion_id is not null
      ), '[]'::jsonb)
    ),
    'cierres_por_semana', jsonb_build_object(
      'version', 1,
      'desde', p_desde,
      'hasta', p_hasta,
      'base', 'fecha_numerador',
      'atribucion', 'autor_cierre',
      'agrupacion', 'bloques_7_dias_desde_inicio',
      'zona', 'America/Lima',
      'origen_filtrado', p_origen,
      'incluye_operaciones_cartera', false,
      'cierres', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      'aporte_cierres', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      -- El total global conserva cierres de bajas, supervisores o autor nulo,
      -- mientras responsables[] sólo enumera vendedores activos. El residual
      -- hace visible esa diferencia sin reasignar el cierre a otra persona.
      'cierres_fuera_del_roster', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
          and (e.analista_id is null or not exists (
            select 1 from vendedores_base vb
            where vb.vendedor_id = e.analista_id
          ))
      ),
      'aporte_cierres_fuera_del_roster', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
          and (e.analista_id is null or not exists (
            select 1 from vendedores_base vb
            where vb.vendedor_id = e.analista_id
          ))
      ),
      'semanas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'semana', semanal.semana,
          'desde', semanal.desde,
          'hasta', semanal.hasta,
          'cierres', semanal.cierres,
          'aporte_cierres', semanal.aporte_cierres,
          'cierres_fuera_del_roster', semanal.cierres_fuera_del_roster,
          'aporte_cierres_fuera_del_roster', semanal.aporte_cierres_fuera_del_roster
        ) order by semanal.semana)
        from (
          select gs.semana_indice + 1 as semana,
            p_desde + (gs.semana_indice * 7) as desde,
            least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
            count(distinct e.lead_id)::int as cierres,
            coalesce(sum(e.aporte_numerador), 0) as aporte_cierres,
            count(distinct e.lead_id) filter (
              where e.analista_id is null or not exists (
                select 1 from vendedores_base vb
                where vb.vendedor_id = e.analista_id
              )
            )::int as cierres_fuera_del_roster,
            coalesce(sum(e.aporte_numerador) filter (
              where e.analista_id is null or not exists (
                select 1 from vendedores_base vb
                where vb.vendedor_id = e.analista_id
              )
            ), 0) as aporte_cierres_fuera_del_roster
          from generate_series(
            0, ((p_hasta - p_desde) / 7)
          ) as gs(semana_indice)
          left join ep_flujo e
            on e.tipo = 'cierre' and not e.anulado
           and e.origen in ('landing', 'formulario', 'referido')
           and (p_origen is null or e.origen = p_origen)
           and (e.fecha_numerador at time zone 'America/Lima')::date
               between p_desde + (gs.semana_indice * 7)
                   and least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
          group by gs.semana_indice
        ) semanal
      ), '[]'::jsonb)
    ),
    'sondas', jsonb_build_object(
      'paridad_nucleo', sp.desvio,
      'paridad_filas', sp.filas,
      -- null = la sonda NO probo nada (rango sin mes, o sin una sola fila que
      -- comparar). Un true solo se afirma cuando hubo sustancia.
      'cuadra', case when sp.desvio is null or sp.filas = 0 then null
                     else sp.desvio = 0 end,
      'episodios_sin_origen', (
        select count(*)::int from ep_flujo e
        where e.tipo in ('recibido','cierre') and e.origen is null
      ),
      'cierres_anulados', (
        select count(*)::int from ep_flujo e
        where e.tipo = 'cierre' and e.anulado
      ),
      -- Cuanto divisor NO aparecera en `responsables`: episodios de analistas
      -- fuera del roster de vendedores activos (supervisores, bajas). Sin esto
      -- el desglose parece que no suma el total y nadie sabe por que.
      'divisor_fuera_del_roster', (
        select coalesce(sum(nv2.divisor), 0)::int
        from nucleo_vendedor nv2
        where nv2.analista_id is null
           or nv2.analista_id not in (select vb2.vendedor_id from vendedores_base vb2)
      ),
      -- Numerador que tampoco aparecera en `responsables`, por la misma razon
      -- que el divisor: analistas con cierres/cartera fuera del roster.
      'numerador_fuera_del_roster', (
        select coalesce(sum(
          nv3.numerador
        ), 0)
        from nucleo_vendedor nv3
        where nv3.analista_id is null
           or nv3.analista_id not in (select vb3.vendedor_id from vendedores_base vb3)
      ),
      -- Leads que la ficha da por convertidos pero SIN cierre elegible (o con
      -- el cierre anulado) en el ledger: el desacuerdo entre las dos verdades,
      -- medido en vez de tapado. Nombre explicito: «elegible», no «cierre».
      'cohorte_convertidos_sin_cierre_elegible', (
        select count(*)::int from cohorte c2
        where (c2.perfil_id is not null or c2.etapa = 'convertido')
          and c2.id not in (select ec2.lead_id from ep_cosecha ec2)
      ),
      -- El desacuerdo INVERSO: cierre elegible cuyo lead no figura convertido
      -- en su ficha. Sin esta, la sonda solo miraba en una direccion.
      'cierres_sin_ficha_convertida', (
        select count(*)::int from cohorte c3
        where c3.id in (select ec3.lead_id from ep_cosecha ec3)
          and c3.perfil_id is null and c3.etapa is distinct from 'convertido'
      ),
      -- Leads cuyo origen en la FICHA no coincide con el del ledger: mientras
      -- sea 0, rotular `peso_en_nucleo` sobre la fila de origen es seguro; si
      -- sube, la barra «Referido» de la ficha y la del nucleo hablan de
      -- poblaciones distintas (aviso de F3).
      'origen_ficha_distinto_del_ledger', (
        select count(*)::int
        from cohorte c4
        join (
          select e4.lead_id, bool_or(e4.fue_referido) as ref_ledger
          from ep_flujo e4 where e4.tipo = 'recibido' group by e4.lead_id
        ) l4 on l4.lead_id = c4.id
        where (c4.origen = 'referido') is distinct from l4.ref_ledger
      ),
      -- Operaciones de cartera contadas cuya fecha cae FUERA del rango pedido
      -- (solo puede pasar con fechas futuras dentro del mes en curso). NO se
      -- descuentan: el heroe de HOY las cuenta igual y la paridad manda; se
      -- DECLARAN para que F3 avise.
      'cartera_fuera_del_rango', (
        select count(*)::int from ep_flujo e
        where e.tipo = 'operacion'
          and (e.fecha_numerador at time zone 'America/Lima')::date not between p_desde and p_hasta
      ),
      -- F1.3b (hallazgo MEDIO-1 del auditor): un cliente puede volver como
      -- lead NUEVO de OTRO vendedor (los unicos de leads excluyen convertido y
      -- la edge reutiliza el perfil por DNI). Si pasa, su capital de portal
      -- cuenta ENTERO para ambos vendedores y el desglose suma mas que el
      -- total. Hoy es 0 (medido 27/08); esta sonda lo vigila para siempre y
      -- el front avisa si sube.
      'perfiles_con_leads_de_varios_vendedores', (
        select count(*)::int from (
          select l2.perfil_id
          from crm.leads l2
          where l2.perfil_id is not null and l2.vendedor_id is not null
          group by l2.perfil_id
          having count(distinct l2.vendedor_id) > 1
        ) dobles
      )
    ),
    'cohorte', jsonb_build_object(
      'leads', r.leads, 'asignados', r.asignados, 'contactados', r.contactados,
      'reuniones_agendadas', r.reuniones_agendadas,
      'reuniones_realizadas', r.reuniones_realizadas,
      'propuestas', r.propuestas, 'clientes', r.clientes,
      'contratos', r.contratos, 'descartados', r.descartados,
      'conversion_clientes_pct', case when r.leads > 0 then round(100.0 * r.clientes / r.leads, 1) end,
      'conversion_contratos_pct', case when r.leads > 0 then round(100.0 * r.contratos / r.leads, 1) end,
      'conversion_resueltos_pct', case when r.clientes + r.descartados > 0
        then round(100.0 * r.clientes / (r.clientes + r.descartados), 1) end
    ),
    'produccion', jsonb_build_object(
      'clientes', p.clientes, 'contratos', p.contratos,
      'capital_pen', p.capital_pen, 'capital_usd', p.capital_usd,
      'sin_rastro', p.sin_rastro
    ),
    'embudo', jsonb_build_array(
      jsonb_build_object('etapa','leads','cantidad',r.leads,'pct_anterior',case when r.leads > 0 then 100 else null end,'pct_total',case when r.leads > 0 then 100 else null end),
      jsonb_build_object('etapa','contactados','cantidad',r.contactados,'pct_anterior',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_agendadas','cantidad',r.reuniones_agendadas,'pct_anterior',case when r.contactados > 0 then round(100.0*r.reuniones_agendadas/r.contactados,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_agendadas/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_realizadas','cantidad',r.reuniones_realizadas,'pct_anterior',case when r.reuniones_agendadas > 0 then round(100.0*r.reuniones_realizadas/r.reuniones_agendadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_realizadas/r.leads,1) end),
      jsonb_build_object('etapa','propuestas','cantidad',r.propuestas,'pct_anterior',case when r.reuniones_realizadas > 0 then round(100.0*r.propuestas/r.reuniones_realizadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.propuestas/r.leads,1) end),
      jsonb_build_object('etapa','clientes','cantidad',r.clientes,'pct_anterior',case when r.propuestas > 0 then round(100.0*r.clientes/r.propuestas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.clientes/r.leads,1) end),
      jsonb_build_object('etapa','contratos','cantidad',r.contratos,'pct_anterior',case when r.clientes > 0 then round(100.0*r.contratos/r.clientes,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contratos/r.leads,1) end)
    ),
    'origenes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'origen', o.origen, 'leads', o.leads, 'contactados', o.contactados,
        'reuniones_agendadas', o.reuniones_agendadas,
        'reuniones_realizadas', o.reuniones_realizadas,
        'leads_con_cita_real', o.leads_con_cita_real,
        'citas_realizadas', o.citas_realizadas_reales,
        'clientes', o.clientes, 'contratos', o.contratos, 'descartados', o.descartados,
        'conversion_clientes_pct', case when o.leads > 0 then round(100.0*o.clientes/o.leads,1) end,
        'conversion_contratos_pct', case when o.leads > 0 then round(100.0*o.contratos/o.leads,1) end,
        'conversion_resueltos_pct', case when o.clientes+o.descartados > 0 then round(100.0*o.clientes/(o.clientes+o.descartados),1) end,
        -- D6: el referido NO pesa 1 en el nucleo. Viaja el peso para que la
        -- barra se pueda rotular sin recalcular nada (F3).
        'peso_en_nucleo', case when o.origen = 'referido' then v_factor else 1 end,
        -- La MISMA cifra de la fila con cada cierre pesando lo que pesa en el
        -- numero grande (el referido, v_factor). La calcula el servidor para que
        -- la pantalla solo la muestre (Miguel, 23/09: «el servidor siempre que
        -- haga todo»).
        'conversion_ponderada_pct', case when o.leads > 0
          then round(100.0 * o.contratos * (case when o.origen = 'referido' then v_factor else 1 end)
                     / o.leads, 1) end,
        'fuera_del_divisor_del_nucleo', o.origen = 'referido',
        'capital_pen', o.capital_pen, 'capital_usd', o.capital_usd
      ) order by o.contratos desc, o.clientes desc, o.leads desc, o.origen) from origenes o
    ), '[]'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoria', c.categoria, 'leads', c.leads, 'clientes', c.clientes,
        'contratos', c.contratos, 'descartados', c.descartados,
        'conversion_pct', case when c.leads > 0 then round(100.0*c.contratos/c.leads,1) end
      ) order by c.contratos desc, c.leads desc, c.categoria) from categorias c
    ), '[]'::jsonb),
    'responsables', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', rr.vendedor_id,
        'leads', rr.leads,
        'contactados', rr.contactados,
        'reuniones_realizadas', rr.reuniones_realizadas,
        'leads_con_cita_real', rr.leads_con_cita_real,
        'citas_realizadas', rr.citas_realizadas_reales,
        'clientes', rr.contratos,
        'conversion_pct', case when rr.leads > 0 then round(100.0*rr.contratos/rr.leads,1) end,
        -- Cifra principal por vendedor (nucleo): la MISMA que Ranking y Metas.
        'nucleo_divisor', coalesce(nv.divisor, 0),
        'nucleo_numerador', coalesce(
          nv.numerador, 0),
        'nucleo_conversion_pct', case when coalesce(nv.divisor, 0) > 0
          then round(100.0 * nv.numerador / nv.divisor, 2) end,
        'capital_pen', cr.capital_pen,
        'capital_usd', cr.capital_usd,
        'cierres_por_semana', coalesce((
          select jsonb_agg(jsonb_build_object(
            'semana', cierre_semanal.semana,
            'desde', cierre_semanal.desde,
            'hasta', cierre_semanal.hasta,
            'cierres', cierre_semanal.cierres,
            'aporte_cierres', cierre_semanal.aporte_cierres
          ) order by cierre_semanal.semana)
          from (
            select gs.semana_indice + 1 as semana,
              p_desde + (gs.semana_indice * 7) as desde,
              least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
              count(distinct e.lead_id)::int as cierres,
              coalesce(sum(e.aporte_numerador), 0) as aporte_cierres
            from generate_series(
              0, ((p_hasta - p_desde) / 7)
            ) as gs(semana_indice)
            left join ep_flujo e
              on e.tipo = 'cierre' and not e.anulado
             and e.origen in ('landing', 'formulario', 'referido')
             and e.analista_id = rr.vendedor_id
             and (p_origen is null or e.origen = p_origen)
             and (e.fecha_numerador at time zone 'America/Lima')::date
                 between p_desde + (gs.semana_indice * 7)
                     and least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
            group by gs.semana_indice
          ) cierre_semanal
        ), '[]'::jsonb),
        'tendencia_semanal', coalesce((
          select jsonb_agg(jsonb_build_object(
            'semana', semanal.semana,
            'desde', semanal.desde,
            'hasta', semanal.hasta,
            'leads', semanal.leads,
            'clientes', semanal.clientes,
            'conversion_pct', case when semanal.leads > 0
              then round(100.0*semanal.clientes/semanal.leads,1) end
          ) order by semanal.semana)
          from (
            select gs.semana_indice + 1 as semana,
              p_desde + (gs.semana_indice * 7) as desde,
              least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
              count(c.id)::int as leads,
              count(c.id) filter (where c.contrato)::int as clientes
            from generate_series(0, ((p_hasta - p_desde) / 7)) as gs(semana_indice)
            left join cohorte c on c.vendedor_id = rr.vendedor_id
              and (c.creado_en at time zone 'America/Lima')::date >= p_desde + (gs.semana_indice * 7)
              and (c.creado_en at time zone 'America/Lima')::date <= least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
            group by gs.semana_indice
          ) semanal
        ), '[]'::jsonb)
      ) order by rr.contratos desc, rr.leads desc, rr.vendedor_id)
      from responsables_resumen rr
      join capital_responsables cr on cr.vendedor_id = rr.vendedor_id
      left join nucleo_vendedor nv on nv.analista_id = rr.vendedor_id
    ), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join produccion p cross join nucleo n cross join sonda_paridad sp;

  -- ══ OLA 1b · LA SUSTITUCION ════════════════════════════════════════════
  -- REGLA DE MIGUEL (21/09/2026): mes calendario completo y sin filtro de
  -- fuente -> la cifra la sirve `crm.conversion_mensual_fn`. Cualquier otro
  -- caso -> calculo en vivo, DECLARADO.
  --
  -- Aqui se cumple la primera mitad. Lo de arriba sigue calculandose igual y
  -- sigue alimentando `sondas.paridad_nucleo`; lo que cambia es QUE SE PUBLICA
  -- en las tres claves de la cifra cuando la condicion se da.
  --
  -- Por que la oficial y no un recalculo: la mensual sabe hacer dos cosas que
  -- esta puerta no hace y no debe aprender —servir la FOTO SELLADA de un mes
  -- cerrado, y restar la deuda de los cierres anulados de un mes ya sellado—.
  -- Duplicar esas dos reglas aqui seria crear la tercera copia; pedirselas es
  -- lo que hace que la cifra sea UNA.
  --
  -- Su gate es MAS ANCHO que el de esta funcion (vendedor/supervisor/gerencia/
  -- lector global frente a gerencia/lector global), asi que quien llega hasta
  -- aqui siempre pasa el suyo: no se abre ninguna puerta. Y como recorta por
  -- `auth.uid()`, el alcance del que pregunta se respeta —aqui, gerencia, que
  -- es global—.
  if v_periodo is not null and p_origen is null then
    v_oficial := crm.conversion_mensual_fn(v_periodo);
    v_payload := jsonb_set(v_payload, '{nucleo}',
      (v_payload -> 'nucleo') || jsonb_build_object(
        'fuente', 'mensual',
        -- Ahora SI se sabe si el mes esta sellado, porque lo dice la oficial.
        'sellado', coalesce((v_oficial #>> '{cierre,cerrado}')::boolean, false),
        -- La lectura mensual descuenta la deuda por cierres anulados.
        'ajuste_aplicado', true,
        'divisor', v_oficial #> '{total,divisor}',
        'numerador', v_oficial #> '{total,numerador}',
        'conversion_pct', v_oficial #> '{total,conversion_pct}',
        -- 🔑 LA PONDERACION DE LA FOTO, al lado de la cifra de la foto. Cierra
        -- el P2 de Codex (23/09): una cifra sellada no puede publicarse sin
        -- decir con que pesos se calculo.
        --
        -- 🔴 ADITIVA, no sustitutiva, y eso es deliberado. La primera version
        -- movia `peso_referido`/`peso_renovacion` al peso sellado, y Codex lo
        -- refuto en la segunda vuelta con un contraejemplo: esas dos claves
        -- ROTULAN EL DESGLOSE (`conversion-vendedores.ts:258,272`), que se
        -- recalcula vivo. Un cliente con bundle viejo —que no conoce esta clave
        -- nueva— habria rotulado con el peso de la foto un desglose calculado
        -- con el peso de hoy. El servidor anterior publicaba ahi el vivo y
        -- acertaba: era una REGRESION. Asi, quien no conozca
        -- `ponderacion_oficial` ve exactamente lo de siempre.
        'ponderacion_oficial', v_oficial #> '{ponderacion}',
        -- Lo que ESTA funcion habria publicado, conservado al lado. Sin esto,
        -- la distancia entre la cifra oficial y el recalculo vivo solo se podria
        -- DEDUCIR de una igualdad que la propia delegacion rompe
        -- (`conversion-vendedores.ts:183` compara el divisor del paquete sin
        -- filtro contra el de los paquetes CON filtro, que no delegan). Con
        -- `recalculo_vivo` la pantalla puede decir «4,16 % oficial · 4,32 %
        -- recalculado» en vez de quedarse en blanco.
        -- Cabe sin romper nada: `NucleoConversionesSchema` del front es
        -- `v.object` (`app/src/lib/metricas-conversiones.ts`), que ignora lo
        -- que no conoce.
        'recalculo_vivo', jsonb_build_object(
          'divisor', v_payload #> '{nucleo,divisor}',
          'numerador', v_payload #> '{nucleo,numerador}',
          'conversion_pct', v_payload #> '{nucleo,conversion_pct}')
      ), false);
  end if;
  -- Fuera de esa condicion no se toca nada: el bloque sigue diciendo
  -- `fuente: rango_vivo`, `sellado: null`, `ajuste_aplicado: false`, que es la
  -- verdad de un rango libre o de una consulta con filtro de origen.

  return v_payload;
end;
$function$;

-- private.metricas_distribucion_leads_v3_core(date,date,timestamptz): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION private.metricas_distribucion_leads_v3_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_oficial jsonb;
  v_base jsonb;
  v_hoy date := (p_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz := p_desde::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  v_mes date := date_trunc('month', p_hasta)::date;
  v_factor numeric;
  v_periodo date;
  v_nucleo jsonb;
  v_div_total integer;
  v_num_total numeric;
  v_ref_total integer;
  v_div_sin_analista integer;
  v_num_sin_analista numeric;
  v_anulados integer;
  v_sin_origen integer;
  v_paridad numeric;
  v_paridad_filas integer;
  v_analistas jsonb;
  v_usd_conv integer;
  v_usd_desc integer;
  v_sin_ficha integer;
begin
  v_base := private.metricas_distribucion_leads_v2_core(p_desde, p_hasta, p_ahora);
  v_factor := private.peso_referido_conversion(v_mes);

  -- (auditor RLS, objecion 10) Si el motor v2 renombrara las claves de las
  -- que esta funcion LEE, el coalesce de la punteria fabricaria ceros en
  -- silencio — exactamente lo que este plan vino a matar. Falla ruidosa.
  if exists (
    select 1 from jsonb_array_elements(v_base->'analistas') fila(elemento)
    where (fila.elemento#>'{pen,cohorte}' ? 'convertidos') is distinct from true
       or (fila.elemento#>'{pen,cohorte}' ? 'descartados') is distinct from true
       or (fila.elemento->'usd_no_segmentado' ? 'convertidos') is distinct from true
       or (fila.elemento->'usd_no_segmentado' ? 'descartados') is distinct from true
  ) or exists (
    select 1 from jsonb_array_elements(v_base->'analistas') fila(elemento),
                  jsonb_array_elements(fila.elemento#>'{pen,rangos}') rango(elemento)
    where (rango.elemento->'cohorte' ? 'convertidos') is distinct from true
       or (rango.elemento->'cohorte' ? 'descartados') is distinct from true
  ) or (v_base->'resumen' ? 'convertidos_pen') is distinct from true
    or (v_base->'resumen' ? 'descartados_pen') is distinct from true then
    raise exception 'Contrato interno v2 inesperado: faltan las claves de conversion'
      using errcode = '55000';
  end if;

  -- El núcleo admite también rangos parciales y aplica su ventana a cartera.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  -- Esta pantalla solo la ve gerencia o un lector global (el gate vive en
  -- `..._autorizada`, aguas arriba), asi que la tabla-base va SIEMPRE global.
  with ep as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, true, '{}'::uuid[], v_factor
    ) e
  ),
  nv as (
    select e.analista_id,
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
    from ep e
    group by e.analista_id
  ),
  agg as (
    select
      coalesce(jsonb_object_agg(
        nv.analista_id::text,
        jsonb_build_object(
          'nucleo_divisor', nv.divisor,
          'nucleo_referidos_recibidos', nv.referidos_recibidos,
          'nucleo_numerador',
            nv.numerador,
          'nucleo_conversion_pct', case when nv.divisor > 0
            then round(100.0 * nv.numerador / nv.divisor, 2) end
        )
      ) filter (where nv.analista_id is not null), '{}'::jsonb) as mapa,
      coalesce(sum(nv.divisor), 0)::int as div_total,
      coalesce(sum(nv.numerador), 0) as num_total,
      coalesce(sum(nv.referidos_recibidos), 0)::int as ref_total,
      coalesce(sum(nv.divisor) filter (where nv.analista_id is null), 0)::int as div_sin,
      coalesce(sum(
        nv.numerador
      ) filter (where nv.analista_id is null), 0) as num_sin
    from nv
  ),
  extras as (
    select
      count(*) filter (where e.tipo = 'cierre' and e.anulado)::int as anulados,
      count(*) filter (where e.tipo = 'recibido' and e.origen is null)::int as sin_origen
    from ep e
  ),
  -- Sonda de paridad contra el nucleo REAL (el que sirve HOY/Metas). Solo se
  -- calcula cuando va a valer algo: con `v_periodo` NULL el resultado se
  -- descarta y esta pierna es la mas cara.
  comparacion as (
    select
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nv
    -- `=` y no `is not distinct from`: PG no admite este ultimo en un FULL
    -- JOIN (no es hash/merge-joinable). Es seguro porque ninguna de las dos
    -- relaciones puede traer `analista_id` NULL en el lado que importa; si eso
    -- cambiara, la sonda gritaria (paridad <> 0) en vez de callarse.
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda as (
    select
      coalesce(sum(c.delta), 0) as desvio,
      count(*)::int as filas
    from comparacion c
  )
  select agg.mapa, agg.div_total, agg.num_total, agg.ref_total, agg.div_sin, agg.num_sin,
         extras.anulados, extras.sin_origen, sonda.desvio, sonda.filas
    into v_nucleo, v_div_total, v_num_total, v_ref_total, v_div_sin_analista, v_num_sin_analista,
         v_anulados, v_sin_origen, v_paridad, v_paridad_filas
    from agg cross join extras cross join sonda;

  -- ── Por analista: punteria PEN/USD, sus rangos, y su cifra del nucleo ─────
  select coalesce(jsonb_agg(
    jsonb_set(
      fila.elemento || jsonb_build_object(
        'conversion',
        jsonb_build_object(
          'pen', private.conversion_punteria(
            (fila.elemento#>>'{pen,cohorte,convertidos}')::int,
            (fila.elemento#>>'{pen,cohorte,descartados}')::int),
          'usd', private.conversion_punteria(
            (fila.elemento#>>'{usd_no_segmentado,convertidos}')::int,
            (fila.elemento#>>'{usd_no_segmentado,descartados}')::int)
        )
        || coalesce(v_nucleo->(fila.elemento->>'analista_id'), jsonb_build_object(
             'nucleo_divisor', 0,
             'nucleo_referidos_recibidos', 0,
             'nucleo_numerador', 0::numeric,
             'nucleo_conversion_pct', null
           ))
      ),
      '{pen,rangos}',
      rr.rangos,
      false
    ) order by fila.orden
  ), '[]'::jsonb)
  into v_analistas
  from jsonb_array_elements(v_base->'analistas') with ordinality as fila(elemento, orden)
  cross join lateral (
    select coalesce(jsonb_agg(
      rango.elemento || jsonb_build_object(
        'conversion', private.conversion_punteria(
          (rango.elemento#>>'{cohorte,convertidos}')::int,
          (rango.elemento#>>'{cohorte,descartados}')::int)
      ) order by rango.orden
    ), '[]'::jsonb) as rangos
    from jsonb_array_elements(fila.elemento#>'{pen,rangos}') with ordinality as rango(elemento, orden)
  ) rr;

  v_base := jsonb_set(v_base, '{analistas}', v_analistas, false);

  -- (auditor RLS, objecion 9) Los totales nucleo_* del resumen suman TODOS
  -- los analistas del ledger; el array `analistas` solo trae a quien sigue en
  -- el roster de vendedores/supervisores. Un ex-vendedor reenrolado conserva
  -- su historia: cuenta en el resumen y no tiene ficha. Esta sonda lo dice.
  select count(*) into v_sin_ficha
    from jsonb_object_keys(v_nucleo) k
   where k not in (
     select fila.elemento->>'analista_id'
       from jsonb_array_elements(v_base->'analistas') fila(elemento));

  -- ── Resumen: lo mismo, a nivel de toda la casa ────────────────────────────
  -- El USD del resumen lo suma HOY el navegador (`cierresUsd`, la suma en
  -- cliente de `distribucion-leads-gerencia.tsx:341-345`). Se suma aqui, de los
  -- MISMOS elementos, para que el numero sea identico y el front deje de
  -- hacerlo.
  select
    coalesce(sum((elemento#>>'{usd_no_segmentado,convertidos}')::int), 0),
    coalesce(sum((elemento#>>'{usd_no_segmentado,descartados}')::int), 0)
  into v_usd_conv, v_usd_desc
  from jsonb_array_elements(v_base->'analistas') as fila(elemento);

  v_base := jsonb_set(
    v_base,
    '{resumen}',
    (v_base->'resumen') || jsonb_build_object(
      'conversion', jsonb_build_object(
        'pen', private.conversion_punteria(
          (v_base#>>'{resumen,convertidos_pen}')::int,
          (v_base#>>'{resumen,descartados_pen}')::int),
        'usd', private.conversion_punteria(v_usd_conv, v_usd_desc),
        'nucleo_divisor', v_div_total,
        'nucleo_referidos_recibidos', v_ref_total,
        'nucleo_numerador', v_num_total,
        'nucleo_conversion_pct', case when v_div_total > 0
          then round(100.0 * v_num_total / v_div_total, 2) end,
        -- DECLARACION (Ola 1a, 22/09/2026). Cuatro claves que NO cambian
        -- ninguna cifra: dicen de donde sale la que ya se publicaba.
        --   es_mes_calendario: `v_periodo is not null` — la MISMA prueba que
        --     esta funcion ya usaba mas arriba para pedirle la cartera al
        --     nucleo. Es la condicion de Miguel (21/09) para poder delegar.
        --   fuente: 'rango_vivo' SIEMPRE: esta puerta calcula por su cuenta
        --     sobre `ep`. El dia que delegue en crm.conversion_mensual_fn
        --     dira 'mensual'.
        --   sellado: null = «no se delego en la foto oficial».
        --   ajuste_aplicado: false = NO resta la deuda de anulacion de un mes
        --     ya sellado. Ese es el hecho que puede hacerla discrepar de la
        --     cifra oficial, y declararlo es lo que lo vuelve visible.
        -- Van SOLO en el resumen, no en la ficha de cada analista: describen
        -- el calculo entero, no a un analista. El front las lee opcionales en
        -- los dos sitios (`ConversionNucleoEntries`), asi que su ausencia en
        -- la ficha no rompe nada.
        'es_mes_calendario', v_periodo is not null,
        'fuente', 'rango_vivo',
        'sellado', null,
        'ajuste_aplicado', false
      )
    ),
    false
  );

  v_base := jsonb_set(v_base, '{version}', '3'::jsonb, false);
  v_base := jsonb_set(
    v_base,
    '{alcances}',
    (v_base->'alcances') || jsonb_build_object(
      'conversion_punteria', 'CERRADOS_ENTRE_RESUELTOS',
      'conversion_nucleo', 'LLEGADAS_UNICAS_PRIMER_ANALISTA',
      'conversion_incluye_cartera', true
    ),
    false
  );

  -- ── Sondas: para que F3 pueda OCULTAR un numero en vez de fabricar un cero ─
  v_base := jsonb_set(
    v_base,
    '{sondas}',
    jsonb_build_object(
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      'paridad_nucleo', v_paridad,
      'paridad_filas', v_paridad_filas,
      'cuadra', case when v_paridad is null or v_paridad_filas = 0 then null
                     else v_paridad = 0 end,
      -- Episodios que NO apareceran en `analistas` (analista nulo en la
      -- tabla-base): si esto crece, el resumen y la suma de fichas dejan de
      -- cuadrar y hay que saberlo.
      'divisor_sin_analista', v_div_sin_analista,
      'numerador_sin_analista', v_num_sin_analista,
      'cierres_anulados', v_anulados,
      'episodios_sin_origen', v_sin_origen,
      'nucleo_sin_ficha', v_sin_ficha
    ),
    true
  );

  -- ══ OLA 1b · LA SUSTITUCION ════════════════════════════════════════════
  -- REGLA DE MIGUEL (21/09/2026): mes calendario completo y sin filtro de
  -- fuente -> la cifra la sirve `crm.conversion_mensual_fn`. Este motor no
  -- recibe filtro de fuente, asi que la condicion es `v_periodo is not null`,
  -- la misma prueba que ya usaba para pedirle la cartera al nucleo.
  --
  -- Se sustituyen las TRES claves de la cifra en los DOS sitios donde viajan:
  -- el resumen y la ficha de cada analista. Si solo se hiciera el resumen, la
  -- ficha de un analista aqui y la misma ficha en Gestion de equipo dirian
  -- cosas distintas el dia que haya deuda — justo lo que esta ola viene a
  -- matar.
  --
  -- `nucleo_referidos_recibidos` NO se delega: es un recuento descriptivo que
  -- la oficial no publica por vendedor, y fabricar un 0 seria mentir.
  --
  -- Si un analista NO tiene fila en la oficial, su `nucleo_conversion_pct`
  -- queda en `null` —«no se sabe»— y nunca en 0. El postflight lo cuenta y
  -- exige que hoy no le pase a ninguno. La cuenta NO viaja en `sondas`: el
  -- front las valida con `v.strictObject` y una clave nueva tumbaria el
  -- payload entero. Entrara con su front, no antes.
  --
  -- Y nada de `set_config` aqui: esta funcion es STABLE.
  -- 🔴 LA GUARDA DE IDENTIDAD, Y POR QUE EXISTE. Este motor NO es
  -- `security definer` y no tiene gate propio: el gate vive aguas arriba, en
  -- `private.metricas_distribucion_leads_autorizada`. Pero
  -- `crm.conversion_mensual_fn` SI exige identidad y responde 42501 sin ella.
  -- Medido el 22/09: el unico llamante en la base es esa funcion autorizada
  -- (que siempre trae actor), pero en el repo hay scripts de gate que llaman a
  -- este motor DIRECTAMENTE, en una sesion de operador sin claims
  -- (`supabase/scripts/test-f2-distribucion-v3.sql`,
  --  `supabase/scripts/test-conversion-llegadas.sql`). Sin esta guarda,
  -- esos gates pasarian a morir con «No autorizado».
  --
  -- Sin identidad no se puede preguntar a la oficial, asi que se sigue
  -- calculando en vivo Y SE DECLARA como tal (`fuente: rango_vivo` con
  -- `es_mes_calendario: true`, que es justo «era delegable y no se delego»).
  -- Ninguna pantalla puede caer aqui: para llegar a este motor desde una
  -- pantalla hay que pasar antes por el gate, que exige actor.
  if v_periodo is not null and (select auth.uid()) is not null then
    v_oficial := crm.conversion_mensual_fn(v_periodo);

    v_base := jsonb_set(v_base, '{resumen,conversion}',
      (v_base #> '{resumen,conversion}') || jsonb_build_object(
        'fuente', 'mensual',
        'sellado', coalesce((v_oficial #>> '{cierre,cerrado}')::boolean, false),
        'ajuste_aplicado', true,
        'nucleo_divisor', v_oficial #> '{total,divisor}',
        'nucleo_numerador', v_oficial #> '{total,numerador}',
        'nucleo_conversion_pct', v_oficial #> '{total,conversion_pct}'
      ), false);

    v_base := jsonb_set(v_base, '{analistas}',
      coalesce((
        select jsonb_agg(
          -- 🔴 A quien la oficial NO tiene, NO se le toca la cifra. Medido el
          -- 22/09: 3 de 21 analistas no tienen fila en la oficial (18
          -- responsables) y uno de ellos, un SUPERVISOR ACTIVO, llevaba
          -- `nucleo_numerador = 2`. Sobrescribirlo con el coalesce a 0 le
          -- habria borrado dos puntos de la pantalla en silencio. Su cifra se
          -- queda como la calculo esta funcion: ni se fabrica ni se pierde.
          -- El TOTAL sigue siendo el de la oficial, que si los cuenta.
          jsonb_set(f.e, '{conversion}',
            case when o.v is null then (f.e -> 'conversion')
                 else (f.e -> 'conversion') || jsonb_build_object(
                   'nucleo_divisor', (o.v -> 'divisor'),
                   'nucleo_numerador', (o.v -> 'numerador'),
                   'nucleo_conversion_pct', (o.v -> 'conversion_pct'))
            end, false)
          order by f.ord)
          from jsonb_array_elements(coalesce(v_base -> 'analistas', '[]'::jsonb))
               with ordinality f(e, ord)
          left join lateral (
            select r.v from jsonb_array_elements(coalesce(v_oficial -> 'responsables', '[]'::jsonb)) r(v)
             where (r.v ->> 'vendedor_id') = (f.e ->> 'analista_id') limit 1
          ) o on true
      ), '[]'::jsonb), false);
  end if;

  return v_base;
end;
$function$;

-- crm.conversion_mensual_sin_cartera_fn(date): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION crm.conversion_mensual_sin_cartera_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_alcance text;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_suelo timestamptz;
  v_suelo_mes date;
  v_medible boolean;
  v_motivo_no_medible text;
  v_motivo_roster text;
  v_es_historico_abierto boolean := false;
  v_payload jsonb;
  v_cierre crm.periodos_cerrados%rowtype;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO. Nunca RLS implicita: esta
  --    funcion es SECURITY DEFINER y las policies no se evaluan. ALLOWLIST, no
  --    «rol_crm is not null»: ese idioma (el de cumplimiento_metas_fn) dejaria
  --    pasar al COORDINADOR, que aqui esta denegado por contrato.
  --    Orden deliberado: un actor denegado recibe 42501 aunque el periodo sea
  --    basura, para que el codigo de error no funcione como oraculo.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion del periodo.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;

  -- 3) ¿MES CERRADO? Entonces se sirve la foto y no se calcula nada. Va aqui,
  --    despues del gate y de validar el periodo, para que un mes cerrado
  --    responda igual de fail-closed que uno abierto.
  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  if found then
    with visibles as (
      select f.* from private.cierre_mes_visible(p_periodo, v_uid) f
    ), fuera_foto as materialized (
      select e.value as fila
      from jsonb_array_elements(
        coalesce(v_cierre.cobertura->'fuera_ranking', '[]'::jsonb)
      ) e
      where v_global and e.value->'conversion' <> 'null'::jsonb
      union all
      select jsonb_build_object('conversion', v_cierre.cobertura->'conversion_sin_analista')
      where v_global and v_cierre.cobertura ? 'conversion_sin_analista'
    ), resumen as (
      -- El total suma la foto rankeable y el agregado empresarial congelado.
      -- Las identidades externas nunca se materializan como responsables.
      select
        count(*)::int as analistas,
        (coalesce(sum(v.divisor), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor}')::int)
                      from fuera_foto f), 0))::int as divisor,
        (coalesce(sum(v.divisor_aproximado), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor_aproximado}')::int)
                      from fuera_foto f), 0))::int as divisor_aproximado,
        (coalesce(sum(v.cierres_no_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_no_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_no_referidos,
        (coalesce(sum(v.cierres_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_referidos,
        (coalesce(sum(v.cierres_de_arrastre), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_de_arrastre}')::int)
                      from fuera_foto f), 0))::int as cierres_de_arrastre,
        (coalesce(sum(v.referidos_recibidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,referidos_recibidos}')::int)
                      from fuera_foto f), 0))::int as referidos_recibidos,
        (coalesce(sum(v.numerador), 0::numeric)
          + coalesce((select sum((f.fila#>>'{conversion,numerador}')::numeric)
                      from fuera_foto f), 0::numeric)) as numerador
      from visibles v
    ), motivos as (
      select e.key as motivo, sum(e.value::int)::int as n
      from (
        select v.divisor_por_motivo from visibles v
        union all
        select coalesce(f.fila#>'{conversion,divisor_por_motivo}', '{}'::jsonb)
        from fuera_foto f
      ) dm, jsonb_each_text(dm.divisor_por_motivo) e
      group by e.key
    )
    select jsonb_build_object(
      'version', 1,
      'generado_en', v_ahora,
      'alcance', v_alcance,
      'periodo', jsonb_build_object(
        'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
        'mes_nombre', private.etiqueta_mes_es(p_periodo),
        'anio', extract(year from p_periodo)::int,
        'zona', 'America/Lima',
        'desde', p_periodo::timestamp at time zone 'America/Lima',
        'hasta', (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'
      ),
      'ponderacion', jsonb_build_object(
        'referido', v_cierre.ponderacion_referido,
        -- 23/09/2026: la foto guarda SU peso de renovacion desde `20260923172517`.
        -- Antes se RECONSTRUIA desde el del referido, cierto solo mientras los dos
        -- valieran lo mismo. Ahora se lee el que se guardo. El `coalesce` cubre las
        -- fotos anteriores a esa columna: para ellas se conserva EXACTAMENTE la
        -- regla con la que se sellaron. Una foto no se reescribe.
        'renovacion', coalesce(
          v_cierre.ponderacion_renovacion,
          case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
            then v_cierre.ponderacion_referido else 1 end),
        'fuente', 'crm.conversion_pesos'
      ),
      -- La fuente indica la semántica sellada. Las fotos anteriores no se
      -- reescriben ni se hacen pasar por llegadas únicas.
      'fuentes', jsonb_build_object(
        'divisor', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then 'crm.leads.creado_en' else 'crm.lead_asignaciones.asignado_en' end,
        'numerador', 'crm.lead_asignaciones.resultado_en',
        'referido', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then 'crm.leads.origen' else 'crm.lead_asignaciones.origen' end
      ),
      -- LA CLAVE NUEVA. El front la usa para decir «cerrado el 10/09, ya no
      -- cambia»; un cliente viejo la ignora y no se entera de nada.
      'cierre', jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cierre.cerrado_en,
        'automatico', v_cierre.automatico
      ),
      'cobertura', jsonb_build_object(
        'medible', coalesce((v_cierre.cobertura->>'medible')::boolean, false),
        'suelo_historico', v_cierre.cobertura->>'suelo_historico',
        'motivo_no_medible', v_cierre.cobertura->>'motivo_no_medible',
        'divisor_aproximado', (select r.divisor_aproximado from resumen r),
        'divisor_por_motivo', coalesce(
          (select jsonb_object_agg(m.motivo, m.n) from motivos m), '{}'::jsonb),
        -- La sonda de cierres sin episodio se calculaba sobre datos vivos; en un
        -- mes sellado no se recalcula (mentiria sobre el momento del sello) y se
        -- declara en cero, que es lo que la foto puede afirmar.
        'cierres_sin_episodio', 0,
        -- La producción de supervisores u otras identidades no rankeables se
        -- conserva en el total, pero no se convierte en una fila de analista.
        'fuera_de_roster', jsonb_build_object(
          'analistas', (select count(*)::int from fuera_foto f where f.fila->>'persona_id' is not null),
          'divisor', coalesce((select sum(
            (f.fila#>>'{conversion,divisor}')::int) from fuera_foto f), 0)::int,
          'cierres', coalesce((select sum(
            (f.fila#>>'{conversion,cierres_no_referidos}')::int
            + (f.fila#>>'{conversion,cierres_referidos}')::int
          ) from fuera_foto f), 0)::int,
          'numerador', coalesce((select sum(
            (f.fila#>>'{conversion,numerador}')::numeric
          ) from fuera_foto f), 0::numeric))
      ),
      'total', (
        select jsonb_build_object(
          'analistas', r.analistas,
          'divisor', r.divisor,
          'cierres_no_referidos', r.cierres_no_referidos,
          'cierres_referidos', r.cierres_referidos,
          'cierres_de_arrastre', r.cierres_de_arrastre,
          'referidos_recibidos', r.referidos_recibidos,
          'numerador', r.numerador,
          'conversion_pct', case when r.divisor > 0
            then round(100.0 * r.numerador / r.divisor, 2) end,
          'referidos_aporta_pct', case when r.divisor > 0
            then round(100.0 * v_cierre.ponderacion_referido * r.cierres_referidos / r.divisor, 2) end
        ) from resumen r),
      'responsables', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'vendedor_id', v.vendedor_id,
            'supervisor_id', v.supervisor_id,
            'divisor', v.divisor,
            'cierres_no_referidos', v.cierres_no_referidos,
            'cierres_referidos', v.cierres_referidos,
            'cierres_de_arrastre', v.cierres_de_arrastre,
            'numerador', v.numerador,
            'conversion_pct', v.conversion_pct,
            'estado', v.estado,
            'procedencia', v.procedencia,
            'referidos', jsonb_build_object(
              'recibidos', v.referidos_recibidos,
              'cerrados', v.cierres_referidos,
              'dados_de_alta', v.referidos_dados_de_alta,
              'aporta_pct', v.referidos_aporta_pct
            ),
            -- En un mes cerrado ya no queda nada pendiente de ese mes: lo que se
            -- pudo descontar se descontó al sellar, y lo que no, sigue vivo en
            -- el mes siguiente. Por eso `pendiente` es 0 y `aplicado` no.
            'ajuste', jsonb_build_object(
              'aplicado', v.ajuste_numerador,
              'pendiente', 0,
              'origenes', '[]'::jsonb)
          )
          order by v.conversion_pct desc nulls last,
                   v.numerador desc, v.divisor desc, v.vendedor_id
        )
        from visibles v
      ), '[]'::jsonb)
    ) into v_payload;

    -- ⚠️ SIN `filtrar_desglose_sujetos_crm`. Esa defensa descarta a quien hoy no
    -- sea vendedor, y sobre una foto de pago borraria justo a quien se fue del
    -- equipo — el caso que el sello congela el nombre para conservar.
    return v_payload;
  end if;

  -- 4) Mes ABIERTO. Quien sale NOMBRADO lo decide una sola regla del nucleo,
  -- `private.roster_conversion_mensual`: el mes vigente conserva el roster
  -- operativo; uno anterior aun abierto (ventana de ajuste), la ultima
  -- publicacion de ESE mes.
  v_es_historico_abierto := p_periodo < v_mes_actual;

  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  v_factor := private.peso_referido_conversion(p_periodo);

  select min(la.asignado_en)
    into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  v_suelo_mes := date_trunc('month', v_suelo at time zone 'America/Lima')::date;

  if v_suelo is null then
    v_medible := false;
    v_motivo_no_medible := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo_no_medible := case
      when p_periodo < v_suelo_mes then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo_no_medible := null;
  end if;

  if v_alcance = 'propio'
     and not exists (
       select 1 from private.roster_conversion_mensual(p_periodo, false, array[v_uid]) r
        where r.vendedor_id = v_uid
     ) then
    select vs.motivo
      into v_motivo_roster
    from private.vendedores_sin_supervisor() vs
    where vs.vendedor_id = v_uid;

    v_medible := false;
    v_motivo_no_medible := coalesce(v_motivo_roster, 'sin_supervisor');
  end if;

  with roster as materialized (
    select r.vendedor_id, r.supervisor_id
    from private.roster_conversion_mensual(p_periodo, v_global, v_visibles) r
  ),
  base as materialized (
    -- LA CIFRA POR PERSONA sale de UNA sola pieza del nucleo, la misma que usa
    -- Metas: bruto, deuda de meses ya pagados, neto y porcentaje sobre el neto.
    select n.*
    from private.conversion_neta_por_vendedor(p_periodo, v_global, v_visibles) n
  ),
  alta_referidos as materialized (
    select l.creado_por as analista_id, count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini
      and l.creado_en < v_fin
      and l.creado_por is not null
      and (v_global or l.creado_por = any(v_visibles))
    group by l.creado_por
  ),
  filas as (
    select
      r.vendedor_id,
      r.supervisor_id,
      coalesce(b.divisor, 0) as divisor,
      coalesce(b.divisor_aproximado, 0) as divisor_aproximado,
      coalesce(b.divisor_por_motivo, '{}'::jsonb) as divisor_por_motivo,
      coalesce(b.cierres_no_referidos, 0) as cierres_no_referidos,
      coalesce(b.cierres_referidos, 0) as cierres_referidos,
      coalesce(b.cierres_de_arrastre, 0) as cierres_de_arrastre,
      -- NETO de lo que se le debe descontar y porcentaje sobre el neto, tal
      -- como los sirve la pieza. Quien no tiene fila (ni actividad ni deuda)
      -- queda en cero y sin porcentaje, igual que antes.
      coalesce(b.numerador, 0::numeric) as numerador,
      b.conversion_pct,
      coalesce(b.ajuste_pendiente, 0::numeric) as ajuste_pendiente,
      coalesce(b.ajuste_origenes, '[]'::jsonb) as ajuste_origenes,
      coalesce(b.procedencia, '[]'::jsonb) as procedencia,
      coalesce(b.referidos_recibidos, 0) as referidos_recibidos,
      b.referidos_aporta_pct,
      coalesce(a.dados_de_alta, 0) as dados_de_alta
    from roster r
    left join base b on b.analista_id = r.vendedor_id
    left join alta_referidos a on a.analista_id = r.vendedor_id
  ),
  fuera as (
    -- Quien produjo dentro del ambito pero NO esta en el roster: el que se dio
    -- de baja a mitad de mes, el supervisor con cartera propia, el vendedor
    -- sin supervisor. Sigue siendo un AGREGADO SIN IDENTIDAD (ningun uuid
    -- sale), pero desde D8 (Miguel, 27/08/2026) ademas de declararse en
    -- `cobertura.fuera_de_roster` se SUMA al total: por eso aqui se agregan
    -- tambien los desgloses que `resumen` necesita. BRUTO a proposito
    -- (`numerador_bruto`): el ajuste de meses ya pagados se descuenta por fila
    -- del roster y el ex-roster no tiene fila donde descontarlo. Solo cuenta
    -- quien aparece en el nucleo (`en_nucleo`): una deuda sin actividad no es
    -- produccion.
    select
      count(b.analista_id)::int as analistas,
      coalesce(sum(b.divisor), 0)::int as divisor,
      coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
      coalesce(sum(b.numerador_bruto), 0::numeric) as numerador,
      coalesce(sum(b.divisor_aproximado), 0)::int as divisor_aproximado,
      coalesce(sum(b.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(b.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(b.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
      coalesce(sum(b.referidos_recibidos), 0)::int as referidos_recibidos
    from base b
    where b.en_nucleo
      and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
  ),
  motivos_totales as (
    -- D8: el desglose por motivo cubre TODO el divisor que el total cuenta —
    -- las filas del roster y las del agregado fuera de roster. Sin la segunda
    -- pierna, `divisor_por_motivo` dejaria de cuadrar con `total.divisor`.
    select e.key as motivo, sum(e.value::int)::int as n
    from (
      select f.divisor_por_motivo from filas f
      union all
      select coalesce(b.divisor_por_motivo, '{}'::jsonb)
      from base b
      where b.en_nucleo
        and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
    ) dm, jsonb_each_text(dm.divisor_por_motivo) e
    group by e.key
  ),
  sonda as (
    select count(*)::int as cierres_sin_episodio
    from crm.leads l
    where l.etapa = 'convertido'
      and l.origen in ('landing', 'formulario', 'referido')
      and l.convertido_en >= v_ini
      and l.convertido_en < v_fin
      and (v_global
           or l.vendedor_id = any(v_visibles)
           or l.asignado_supervisor_id = any(v_visibles)
           or exists (
             select 1
             from crm.lead_asignaciones lv
             where lv.lead_id = l.id
               and lv.analista_id = any(v_visibles)
           ))
      and not exists (
        select 1
        from crm.lead_asignaciones la
        where la.lead_id = l.id
          and la.resultado = 'convertido'
          and coalesce(la.resultado_en, la.finalizado_en) >= v_ini
          and coalesce(la.resultado_en, la.finalizado_en) < v_fin
      )
  ),
  resumen as (
    -- D8 (Miguel, 27/08/2026): el total de empresa INCLUYE la produccion fuera
    -- de roster — el mismo agregado sin identidad que declara
    -- `cobertura.fuera_de_roster`. Con el agregado en cero el total queda
    -- identico al de antes. Quien sale del roster a mitad de mes cuenta aqui
    -- entero (el roster es estado ACTUAL, no historico): su mes se mueve al
    -- agregado y su fila desaparece de `responsables`; con esto el mes abierto
    -- dice lo mismo que dira su foto al sellarse, donde todo el que produjo
    -- entra con nombre (20260815003742, «no hay fuera de roster en una foto»).
    select
      count(*)::int as analistas,
      (coalesce(sum(f.divisor), 0)
        + (select fr.divisor from fuera fr))::int as divisor,
      (coalesce(sum(f.divisor_aproximado), 0)
        + (select fr.divisor_aproximado from fuera fr))::int as divisor_aproximado,
      (coalesce(sum(f.cierres_no_referidos), 0)
        + (select fr.cierres_no_referidos from fuera fr))::int as cierres_no_referidos,
      (coalesce(sum(f.cierres_referidos), 0)
        + (select fr.cierres_referidos from fuera fr))::int as cierres_referidos,
      (coalesce(sum(f.cierres_de_arrastre), 0)
        + (select fr.cierres_de_arrastre from fuera fr))::int as cierres_de_arrastre,
      (coalesce(sum(f.referidos_recibidos), 0)
        + (select fr.referidos_recibidos from fuera fr))::int as referidos_recibidos,
      (coalesce(sum(f.numerador), 0::numeric)
        + (select fr.numerador from fuera fr)) as numerador
    from filas f
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'alcance', v_alcance,
    'periodo', jsonb_build_object(
      'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(p_periodo),
      'anio', extract(year from p_periodo)::int,
      'zona', 'America/Lima',
      'desde', v_ini,
      'hasta', v_fin
    ),
    'ponderacion', jsonb_build_object(
      'referido', v_factor,
      -- 23/09/2026: publicaba `v_factor`, el peso del REFERIDO, mientras el
      -- nucleo aplica el de la RENOVACION desde `20260923155839`. Declaraba un
      -- peso y se calculaba con otro.
      'renovacion', private.peso_renovacion_conversion(p_periodo),
      'fuente', 'crm.conversion_pesos'
    ),
    'fuentes', jsonb_build_object(
      'divisor', 'crm.leads.creado_en',
      'numerador', 'crm.lead_asignaciones.resultado_en',
      'referido', 'crm.leads.origen'
    ),
    -- Mes abierto: se dice explicitamente que NO esta cerrado, para que la
    -- pantalla no tenga que deducirlo de la ausencia de la clave.
    'cierre', jsonb_build_object('cerrado', false),
    'cobertura', jsonb_build_object(
      'medible', v_medible,
      'suelo_historico', v_suelo,
      'motivo_no_medible', v_motivo_no_medible,
      'divisor_aproximado', (select r.divisor_aproximado from resumen r),
      'divisor_por_motivo', coalesce(
        (select jsonb_object_agg(mt.motivo, mt.n) from motivos_totales mt),
        '{}'::jsonb),
      'cierres_sin_episodio', (select s.cierres_sin_episodio from sonda s),
      'fuera_de_roster', (
        select jsonb_build_object(
          'analistas', fr.analistas,
          'divisor', fr.divisor,
          'cierres', fr.cierres,
          'numerador', fr.numerador
        ) from fuera fr)
    ),
    'total', (
      select jsonb_build_object(
        'analistas', r.analistas,
        'divisor', r.divisor,
        'cierres_no_referidos', r.cierres_no_referidos,
        'cierres_referidos', r.cierres_referidos,
        'cierres_de_arrastre', r.cierres_de_arrastre,
        'referidos_recibidos', r.referidos_recibidos,
        'numerador', r.numerador,
        'conversion_pct', case when r.divisor > 0
          then round(100.0 * r.numerador / r.divisor, 2) end,
        'referidos_aporta_pct', case when r.divisor > 0
          then round(100.0 * v_factor * r.cierres_referidos / r.divisor, 2) end
      ) from resumen r),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', f.vendedor_id,
          'supervisor_id', f.supervisor_id,
          'divisor', f.divisor,
          'cierres_no_referidos', f.cierres_no_referidos,
          'cierres_referidos', f.cierres_referidos,
          'cierres_de_arrastre', f.cierres_de_arrastre,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'estado', case
            when f.divisor > 0 then 'medible'
            when f.referidos_recibidos > 0 then 'solo_referidos'
            when (f.cierres_no_referidos + f.cierres_referidos) > 0 then 'solo_arrastre'
            else 'sin_actividad'
          end,
          'procedencia', f.procedencia,
          'referidos', jsonb_build_object(
            'recibidos', f.referidos_recibidos,
            'cerrados', f.cierres_referidos,
            'dados_de_alta', f.dados_de_alta,
            'aporta_pct', f.referidos_aporta_pct
          ),
          -- Lo que se le esta descontando de meses ya pagados, con su
          -- procedencia. Un numero que baja sin explicacion es una llamada a
          -- soporte; con el motivo al lado es una consecuencia.
          'ajuste', jsonb_build_object(
            'pendiente', f.ajuste_pendiente,
            'origenes', f.ajuste_origenes
          )
        )
        order by f.conversion_pct desc nulls last,
                 f.numerador desc,
                 f.divisor desc,
                 f.vendedor_id
      )
      from filas f
    ), '[]'::jsonb)
  ) into v_payload;

  -- El roster historico ya fue validado por su publicacion mensual. Aplicarle
  -- el rol/actividad de hoy borraria precisamente a una baja de ese mes.
  if v_es_historico_abierto then
    return v_payload;
  end if;
  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

-- crm.conversion_divisor_coordinacion_fn(date,date,date): texto vivo de antes de B11
CREATE OR REPLACE FUNCTION crm.conversion_divisor_coordinacion_fn(p_periodo date DEFAULT NULL::date, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date;
  v_hasta date;
  v_es_mes boolean;
  v_totales record;
  v_payload jsonb;
begin
  -- 1) Gate primero: un actor denegado recibe 42501 aunque el período sea inválido.
  --    `is not true`: un NULL del gate también deniega.
  if private.puede_operar_reparto_crm() is not true then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista'
      using errcode = '42501';
  end if;

  -- 2) Validación del período: mes (por defecto el vigente) o rango inclusivo.
  if p_desde is null and p_hasta is null then
    v_desde := coalesce(p_periodo, v_mes_actual);
    if v_desde <> pg_catalog.date_trunc('month', v_desde)::date then
      raise exception 'Periodo invalido: debe ser el primer dia del mes'
        using errcode = '22023';
    end if;
    if v_desde > v_mes_actual then
      raise exception 'Periodo invalido: el mes no puede ser futuro'
        using errcode = '22023';
    end if;
    v_hasta := (v_desde + interval '1 month' - interval '1 day')::date;
  else
    if p_periodo is not null then
      raise exception 'Periodo invalido: indica el mes o el rango, no los dos'
        using errcode = '22023';
    end if;
    if p_desde is null or p_hasta is null then
      raise exception 'Periodo invalido: indica ambas fechas del rango'
        using errcode = '22023';
    end if;
    if p_desde > p_hasta then
      raise exception 'Periodo invalido: la fecha inicial no puede ser posterior a la final'
        using errcode = '22023';
    end if;
    if p_hasta > v_hoy then
      raise exception 'Periodo invalido: el rango no admite fechas futuras'
        using errcode = '22023';
    end if;
    if p_hasta - p_desde > 365 then
      raise exception 'Periodo invalido: el rango maximo es de 366 dias'
        using errcode = '22023';
    end if;
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;
  v_es_mes := v_desde = pg_catalog.date_trunc('month', v_desde)::date
    and v_hasta = (pg_catalog.date_trunc('month', v_desde) + interval '1 month' - interval '1 day')::date;

  -- 3) Delegar: el núcleo decide mes/rango y abierto/sellado; aquí solo se da forma.
  select t.* into strict v_totales from private.conversion_divisor_empresa_totales(v_desde, v_hasta) t;

  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'alcance', 'global',
    'periodo', pg_catalog.jsonb_build_object(
      'modo', case when v_es_mes then 'mes' else 'rango' end,
      'mes', case when v_es_mes then pg_catalog.to_char(v_desde, 'YYYY-MM') end,
      'mes_nombre', case when v_es_mes then private.etiqueta_mes_es(v_desde) end,
      'anio', case when v_es_mes then extract(year from v_desde)::integer end,
      'zona', 'America/Lima',
      'desde', v_desde,
      'hasta', v_hasta,
      'dias', (v_hasta - v_desde) + 1,
      'cruza_meses_sellados', v_totales.cruza_sellados
    ),
    'sellado', v_totales.sellado,
    'peso_referido', v_totales.peso_referido,
    'peso_renovacion', v_totales.peso_renovacion,
    'fuente', pg_catalog.jsonb_build_object(
      'divisor', 'private.conversion_neta_por_vendedor',
      'origen', 'private.conversion_episodios',
      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado',
      -- 'foto' = mes sellado servido de crm.cierre_mes_vendedor; 'mensual' = mes abierto
      -- con la pieza de Metas (bruto, ajuste, neto); 'rango_vivo' = tramo libre calculado
      -- en vivo sin ajustes ni fotos (precedente: crm.metricas_conversiones_equipo_fn).
      'modo', case when v_totales.sellado then 'foto' when v_es_mes then 'mensual' else 'rango_vivo' end
    ),
    'empresa', pg_catalog.jsonb_build_object(
      'divisor', v_totales.divisor,
      'numerador', v_totales.numerador,
      'conversion_pct', v_totales.conversion_pct,
      'divisor_formulario', v_totales.divisor_formulario,
      'divisor_landing', v_totales.divisor_landing,
      'numerador_bruto', v_totales.numerador_bruto,
      'ajuste_pendiente', v_totales.ajuste_pendiente,
      'desglose_disponible', v_totales.desglose_disponible,
      'cierres', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'formulario', v_totales.cierres_formulario,
        'landing', v_totales.cierres_landing,
        'referido', v_totales.cierres_referido,
        'referido_aporte', v_totales.cierres_referido_aporte,
        'oficina', v_totales.cierres_oficina,
        'otros', v_totales.cierres_otros
      ) end,
      'cartera', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'upgrade', v_totales.upgrade,
        'renovacion', v_totales.renovacion,
        'renovacion_aporte', v_totales.renovacion_aporte
      ) end
    ),
    'sin_analista', case when v_totales.sin_analista_presente then pg_catalog.jsonb_build_object(
      'divisor', v_totales.sin_analista_divisor,
      'numerador', v_totales.sin_analista_numerador
    ) end,
    'analistas', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'analista_id', f.analista_id,
          'nombre', f.nombre,
          'supervisor_id', f.supervisor_id,
          'supervisor_nombre', f.supervisor_nombre,
          'en_nucleo', f.en_nucleo,
          'divisor', f.divisor,
          'divisor_formulario', f.divisor_formulario,
          'divisor_landing', f.divisor_landing,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'numerador_bruto', f.numerador_bruto,
          'ajuste_pendiente', f.ajuste_pendiente,
          'desglose_disponible', f.desglose_disponible,
          'cierres', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'formulario', f.cierres_formulario,
            'landing', f.cierres_landing,
            'referido', f.cierres_referido,
            'referido_aporte', f.cierres_referido_aporte,
            'oficina', f.cierres_oficina,
            'otros', f.cierres_otros
          ) end,
          'cartera', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'upgrade', f.upgrade,
            'renovacion', f.renovacion,
            'renovacion_aporte', f.renovacion_aporte
          ) end
        )
        order by f.nombre nulls last, f.analista_id
      )
      from private.conversion_divisor_empresa(v_desde, v_hasta) f
      where f.analista_id is not null
    ), '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.conversion_divisor_coordinacion_fn(date,date,date) is
  'Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados; si toca meses sellados lo declara en periodo.cruza_meses_sellados y fuente.modo = rango_vivo). Los cierres de orígenes que no pesan (oficina y otros) se cuentan aparte. Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads.';

drop function private.conversion_divisor_empresa_totales(date,date);
drop function private.conversion_divisor_empresa(date,date);
CREATE OR REPLACE FUNCTION private.conversion_divisor_empresa(p_desde date, p_hasta date)
 RETURNS TABLE(analista_id uuid, nombre text, supervisor_id uuid, supervisor_nombre text, en_nucleo boolean, divisor integer, divisor_formulario integer, divisor_landing integer, numerador numeric, conversion_pct numeric, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_es_mes boolean;
  v_mes date;
  v_cierre crm.periodos_cerrados%rowtype;
  v_peso_renovacion numeric;
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_es_mes := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (pg_catalog.date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
  v_mes := pg_catalog.date_trunc('month', p_hasta)::date;

  if v_es_mes then
    select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_desde;
  end if;

  -- Mes SELLADO: la foto por persona tal cual se selló. El desglose de cierres
  -- sale de lo que la foto guarda (origenes_ranking.filas y cartera) con los
  -- pesos sellados; el desglose por origen de las llegadas no está en la foto.
  if v_cierre.periodo is not null then
    v_peso_renovacion := coalesce(
      v_cierre.ponderacion_renovacion,
      case when v_cierre.cobertura ->> 'modelo_conversion' = 'llegadas_v2'
        then v_cierre.ponderacion_referido else 1 end);
    return query
    with foto as (
      select f.*,
        coalesce(
          coalesce((f.origenes_ranking ->> 'disponible')::boolean, false)
            and f.cartera ? 'conversiones_upgrade' and f.cartera ? 'conversiones_renovacion',
          false
        ) as con_desglose
      from crm.cierre_mes_vendedor f
      where f.periodo = p_desde
    ),
    por_origen as (
      select f.vendedor_id,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'formulario')::integer as formulario,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'landing')::integer as landing,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'referido')::integer as referido,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'oficina')::integer as oficina,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' not in ('formulario', 'landing', 'referido', 'oficina', 'ajuste'))::integer as otros
      from foto f
      cross join lateral pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(f.origenes_ranking -> 'filas') = 'array'
          then f.origenes_ranking -> 'filas' else '[]'::jsonb end) as o(fila)
      where f.con_desglose
      group by f.vendedor_id
    )
    select f.vendedor_id,
           f.nombre_completo,
           f.supervisor_id,
           f.supervisor_nombre,
           true,
           f.divisor,
           null::integer,
           null::integer,
           f.numerador,
           f.conversion_pct,
           null::numeric,
           null::numeric,
           case when f.con_desglose then coalesce(o.formulario, 0) end,
           case when f.con_desglose then coalesce(o.landing, 0) end,
           case when f.con_desglose then coalesce(o.referido, 0) end,
           case when f.con_desglose then coalesce(o.referido, 0) * v_cierre.ponderacion_referido end,
           case when f.con_desglose then coalesce(o.oficina, 0) end,
           case when f.con_desglose then coalesce(o.otros, 0) end,
           -- `conversiones_*` (primera operación ELEGIBLE por cliente y mes) es lo que
           -- suma el numerador; `operaciones_*` cuenta todas y NO sirve aquí.
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_upgrade')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) * v_peso_renovacion end,
           f.con_desglose
    from foto f
    left join por_origen o on o.vendedor_id = f.vendedor_id
    order by f.nombre_completo;
    return;
  end if;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(v_mes);

  return query
  with base as materialized (
    -- LA CIFRA POR PERSONA sale de UNA sola pieza del núcleo según el modo (ver
    -- conversion_divisor_base): la misma que usa Metas para un mes, la de rango
    -- en vivo para cualquier otro tramo.
    select b.* from private.conversion_divisor_base(p_desde, p_hasta) b
  ),
  episodios as materialized (
    -- Mes exacto: p_periodo = ese mes (peso de renovación del período). Rango:
    -- p_periodo nulo, el núcleo pondera cada operación por su propio mes.
    select e.*
    from private.conversion_episodios(v_ini, v_fin, case when v_es_mes then p_desde end, true, null::uuid[], v_factor) e
  ),
  por_origen as materialized (
    -- El mismo aporte que suma el divisor, abierto por el origen del lead. Referido
    -- y alta manual aportan 0 en el núcleo, así que aquí tampoco pesan.
    select e.analista_id,
           (sum(e.aporte_divisor) filter (where e.origen = 'formulario'))::integer as divisor_formulario,
           (sum(e.aporte_divisor) filter (where e.origen = 'landing'))::integer as divisor_landing
    from episodios e
    where e.tipo = 'recibido'
    group by e.analista_id
  ),
  cierres as materialized (
    -- De dónde salen los cierres: los MISMOS episodios que suman el numerador,
    -- agrupados. Formulario y landing aportan 1 por cierre; referido, su peso;
    -- oficina no pesa; upgrade aporta 1 y renovación su propio peso.
    select e.analista_id,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'formulario'))::integer as cierres_formulario,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'landing'))::integer as cierres_landing,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'referido'))::integer as cierres_referido,
           coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.origen = 'referido'), 0::numeric) as cierres_referido_aporte,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'oficina'))::integer as cierres_oficina,
           -- Otros orígenes admitidos (otro, web, campaña, whatsapp…) tampoco pesan; se cuentan para no esconderlos.
           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'landing', 'referido', 'oficina')))::integer as cierres_otros,
           (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'upgrade'))::integer as upgrade,
           (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'))::integer as renovacion,
           coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'), 0::numeric) as renovacion_aporte
    from episodios e
    where e.tipo in ('cierre', 'operacion') and not e.anulado
    group by e.analista_id
  ),
  roster as materialized (
    -- El supervisor del MES de `hasta` (roster de metas de ese período), no el
    -- de hoy. Una fila por analista aunque el roster trajera repetidos.
    select distinct on (r.vendedor_id) r.vendedor_id, r.supervisor_id
    from private.roster_conversion_mensual(v_mes, true, null::uuid[]) r
    order by r.vendedor_id, r.supervisor_id nulls last
  )
  select b.analista_id,
         perfil.nombre_completo,
         case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end,
         jefe.nombre_completo,
         b.en_nucleo,
         b.divisor,
         coalesce(o.divisor_formulario, 0),
         coalesce(o.divisor_landing, 0),
         b.numerador,
         b.conversion_pct,
         b.numerador_bruto,
         b.ajuste_pendiente,
         coalesce(c.cierres_formulario, 0),
         coalesce(c.cierres_landing, 0),
         coalesce(c.cierres_referido, 0),
         coalesce(c.cierres_referido_aporte, 0::numeric),
         coalesce(c.cierres_oficina, 0),
         coalesce(c.cierres_otros, 0),
         coalesce(c.upgrade, 0),
         coalesce(c.renovacion, 0),
         coalesce(c.renovacion_aporte, 0::numeric),
         true
  from base b
  left join por_origen o on o.analista_id is not distinct from b.analista_id
  left join cierres c on c.analista_id is not distinct from b.analista_id
  left join roster r on r.vendedor_id = b.analista_id
  left join crm.equipo equipo on equipo.perfil_id = b.analista_id
  left join public.perfiles perfil on perfil.id = b.analista_id
  left join public.perfiles jefe
    on jefe.id = case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end
  order by perfil.nombre_completo nulls last;
end;
$function$;

revoke all on function private.conversion_divisor_empresa(date,date) from public, anon, authenticated, service_role;
comment on function private.conversion_divisor_empresa(date,date) is
  'Núcleo (30/09/2026, v2 con desglose y rango): conversión por analista con ámbito de toda la empresa, para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Un mes calendario exacto usa la pieza mensual neta (Metas) y, si está sellado, la foto (crm.cierre_mes_vendedor: origenes_ranking y cartera) sin recalcular; cualquier otro rango se calcula en vivo (bruto = neto). Agrupa los episodios de private.conversion_episodios: llegadas por origen (divisor), cierres por origen (formulario, landing, referido con su aporte, oficina sin peso) y cartera (upgrade, renovación con su aporte). numerador_bruto = partes. La fila con analista_id nulo es la producción sin analista atribuible. Sin autorización dentro y sin ejecutores de la API.';

CREATE OR REPLACE FUNCTION private.conversion_divisor_empresa_totales(p_desde date, p_hasta date)
 RETURNS TABLE(sellado boolean, peso_referido numeric, peso_renovacion numeric, divisor integer, numerador numeric, conversion_pct numeric, divisor_formulario integer, divisor_landing integer, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean, cruza_sellados boolean, sin_analista_presente boolean, sin_analista_divisor integer, sin_analista_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_cierre crm.periodos_cerrados%rowtype;
  v_es_mes boolean;
  v_mes date;
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_es_mes := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (pg_catalog.date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
  v_mes := pg_catalog.date_trunc('month', p_hasta)::date;
  if v_es_mes then
    select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_desde;
  end if;

  return query
  with filas as materialized (
    select f.* from private.conversion_divisor_empresa(p_desde, p_hasta) f
  ),
  fuera_foto as materialized (
    -- Mes sellado: la producción congelada fuera del ranking y la que no tuvo
    -- analista se suman al total de la empresa, igual que en la puerta mensual.
    -- Solo un OBJETO cuenta; un JSON null o la ausencia de la clave es ausencia.
    select e.value as fila
    from pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'fuera_ranking') = 'array'
        then v_cierre.cobertura -> 'fuera_ranking' else '[]'::jsonb end
    ) e
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(e.value -> 'conversion') = 'object'
    union all
    select pg_catalog.jsonb_build_object('conversion', v_cierre.cobertura -> 'conversion_sin_analista')
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'conversion_sin_analista') = 'object'
  ),
  suma as (
    select
      (coalesce(sum(f.divisor), 0)
        + coalesce((select sum((x.fila #>> '{conversion,divisor}')::integer) from fuera_foto x), 0))::integer as divisor,
      (coalesce(sum(f.numerador), 0::numeric)
        + coalesce((select sum((x.fila #>> '{conversion,numerador}')::numeric) from fuera_foto x), 0::numeric)) as numerador,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_formulario), 0)::integer end as divisor_formulario,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_landing), 0)::integer end as divisor_landing,
      case when v_cierre.periodo is null then coalesce(sum(f.numerador_bruto), 0::numeric) end as numerador_bruto,
      case when v_cierre.periodo is null then coalesce(sum(f.ajuste_pendiente), 0::numeric) end as ajuste_pendiente,
      -- Desglose de la empresa: suma de las filas con desglose. En un mes sellado
      -- solo si TODAS las filas de la foto lo traen Y el total no incluye producción
      -- congelada fuera de las filas (fuera_ranking / sin analista), que no tiene
      -- desglose: si no, la suma de partes no sería la del numerador.
      coalesce(bool_and(f.desglose_disponible), v_cierre.periodo is null)
        and (v_cierre.periodo is null or not exists (select 1 from fuera_foto)) as desglose_disponible,
      coalesce(sum(f.cierres_formulario), 0)::integer as cierres_formulario,
      coalesce(sum(f.cierres_landing), 0)::integer as cierres_landing,
      coalesce(sum(f.cierres_referido), 0)::integer as cierres_referido,
      coalesce(sum(f.cierres_referido_aporte), 0::numeric) as cierres_referido_aporte,
      coalesce(sum(f.cierres_oficina), 0)::integer as cierres_oficina,
      coalesce(sum(f.cierres_otros), 0)::integer as cierres_otros,
      coalesce(sum(f.upgrade), 0)::integer as upgrade,
      coalesce(sum(f.renovacion), 0)::integer as renovacion,
      coalesce(sum(f.renovacion_aporte), 0::numeric) as renovacion_aporte
    from filas f
  ),
  sin_analista as (
    select true as presente, f.divisor, f.numerador
    from filas f
    where v_cierre.periodo is null and f.analista_id is null
    union all
    select true,
      (v_cierre.cobertura #>> '{conversion_sin_analista,divisor}')::integer,
      (v_cierre.cobertura #>> '{conversion_sin_analista,numerador}')::numeric
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'conversion_sin_analista') = 'object'
  )
  select
    v_cierre.periodo is not null,
    coalesce(v_cierre.ponderacion_referido, private.peso_referido_conversion(v_mes)),
    case when v_cierre.periodo is null then private.peso_renovacion_conversion(v_mes)
      else coalesce(v_cierre.ponderacion_renovacion,
        case when v_cierre.cobertura ->> 'modelo_conversion' = 'llegadas_v2'
          then v_cierre.ponderacion_referido else 1 end) end,
    s.divisor,
    s.numerador,
    case when s.divisor > 0 then pg_catalog.round(100.0 * s.numerador / s.divisor, 2) end,
    s.divisor_formulario,
    s.divisor_landing,
    s.numerador_bruto,
    s.ajuste_pendiente,
    case when s.desglose_disponible then s.cierres_formulario end,
    case when s.desglose_disponible then s.cierres_landing end,
    case when s.desglose_disponible then s.cierres_referido end,
    case when s.desglose_disponible then s.cierres_referido_aporte end,
    case when s.desglose_disponible then s.cierres_oficina end,
    case when s.desglose_disponible then s.cierres_otros end,
    case when s.desglose_disponible then s.upgrade end,
    case when s.desglose_disponible then s.renovacion end,
    case when s.desglose_disponible then s.renovacion_aporte end,
    s.desglose_disponible,
    -- Un rango libre que toca meses ya sellados se calcula EN VIVO (como la puerta
    -- de Gerencia) y puede discrepar de la foto: se declara para que la pantalla avise.
    (not v_es_mes) and exists (
      select 1 from crm.periodos_cerrados pc
      where pc.periodo between pg_catalog.date_trunc('month', p_desde)::date and v_mes
    ),
    coalesce((select sa.presente from sin_analista sa limit 1), false),
    (select sa.divisor from sin_analista sa limit 1),
    (select sa.numerador from sin_analista sa limit 1)
  from suma s;
end;
$function$;

revoke all on function private.conversion_divisor_empresa_totales(date,date) from public, anon, authenticated, service_role;
comment on function private.conversion_divisor_empresa_totales(date,date) is
  'Núcleo (30/09/2026, v2 con desglose y rango): total de la empresa y producción sin analista para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Mes abierto o rango: suma de private.conversion_divisor_empresa. Mes sellado: foto por persona + cobertura.fuera_ranking + conversion_sin_analista de crm.periodos_cerrados (solo objetos), la misma suma que la puerta mensual oficial; el desglose solo se sirve si todas las filas de la foto lo traen. Nunca recalcula un mes sellado. Sin autorización dentro y sin ejecutores de la API.';

drop function private.conversion_origen_con_cierre(text);

update private.analitica_leads_citas_exenciones e set
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
from pg_proc p
where p.oid = to_regprocedure(e.objeto)
  and to_regprocedure(e.objeto) in (to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'));
update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id;

do $postflight$
declare r record;
begin
  for r in select * from (values
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])', 'b1d6c336d198036db4ddad83a075ebdb', '{postgres=X/postgres}'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', '00b17e7774f821eb04f0802f18039569', '{postgres=X/postgres}'),
    ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)', '6e62d66e1c9536a50657245d6e633f56', '{postgres=X/postgres}'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', 'cbae26a3031e01580068c9336baf798b', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.metricas_conversiones_implementacion(date,date,text)', '1a0e7f7fd01977e556a13fea14ddc5aa', '{postgres=X/postgres}'),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)', 'd73e12275649b756b71de50fd176d697', '{postgres=X/postgres}'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', 'f613d94208b035f241c4e13b351c55be', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa(date,date)', '5700d2770d1796440aa0184b035d623a', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa_totales(date,date)', 'e97995f5ffd9109fce87f2e5dafb11a6', '{postgres=X/postgres}'),
    ('crm.conversion_divisor_coordinacion_fn(date,date,date)', 'b881b83ca8d4dd2f0f081d736828c8c5', '{postgres=X/postgres,authenticated=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl
                    and p.prosecdef = (r.firma <> 'private.metricas_distribucion_leads_v3_core(date,date,timestamptz)')) then
      raise exception 'reversa B11 postflight: % no volvió al texto vivo', r.firma;
    end if;
  end loop;
  if to_regprocedure('private.conversion_origen_con_cierre(text)') is not null then
    raise exception 'reversa B11 postflight: el ayudante sigue vivo';
  end if;
  if exists (select 1 from pg_proc p where p.prosrc like '%conversion_origen_con_cierre%') then
    raise exception 'reversa B11 postflight: queda una función que nombra al ayudante borrado';
  end if;
  if md5(coalesce(obj_description(to_regprocedure('private.conversion_divisor_empresa(date,date)'), 'pg_proc'), '')) <> md5('Núcleo (30/09/2026, v2 con desglose y rango): conversión por analista con ámbito de toda la empresa, para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Un mes calendario exacto usa la pieza mensual neta (Metas) y, si está sellado, la foto (crm.cierre_mes_vendedor: origenes_ranking y cartera) sin recalcular; cualquier otro rango se calcula en vivo (bruto = neto). Agrupa los episodios de private.conversion_episodios: llegadas por origen (divisor), cierres por origen (formulario, landing, referido con su aporte, oficina sin peso) y cartera (upgrade, renovación con su aporte). numerador_bruto = partes. La fila con analista_id nulo es la producción sin analista atribuible. Sin autorización dentro y sin ejecutores de la API.') then
    raise exception 'reversa B11 postflight: comentario de % sin reponer', 'private.conversion_divisor_empresa(date,date)';
  end if;
  if md5(coalesce(obj_description(to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'), 'pg_proc'), '')) <> md5('Núcleo (30/09/2026, v2 con desglose y rango): total de la empresa y producción sin analista para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Mes abierto o rango: suma de private.conversion_divisor_empresa. Mes sellado: foto por persona + cobertura.fuera_ranking + conversion_sin_analista de crm.periodos_cerrados (solo objetos), la misma suma que la puerta mensual oficial; el desglose solo se sirve si todas las filas de la foto lo traen. Nunca recalcula un mes sellado. Sin autorización dentro y sin ejecutores de la API.') then
    raise exception 'reversa B11 postflight: comentario de % sin reponer', 'private.conversion_divisor_empresa_totales(date,date)';
  end if;
  if md5(coalesce(obj_description(to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'), 'pg_proc'), '')) <> md5('Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados; si toca meses sellados lo declara en periodo.cruza_meses_sellados y fuente.modo = rango_vivo). Los cierres de orígenes que no pesan (oficina y otros) se cuentan aparte. Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads.') then
    raise exception 'reversa B11 postflight: comentario de % sin reponer', 'crm.conversion_divisor_coordinacion_fn(date,date,date)';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'reversa B11 postflight: el sello del censo no quedo al dia';
  end if;
  if exists ((select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes
              except select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c)
             union all
             (select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c
              except select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes)) then
    raise exception 'reversa B11 postflight: el censo analitico cambio';
  end if;
end;
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
