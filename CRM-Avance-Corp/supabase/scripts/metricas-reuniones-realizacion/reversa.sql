-- REVERSA de 20261013145852_crm_realizacion_cuenta_anticipada.sql («"Realización" cuenta la cita realizada desde que se marca»).
--
-- FALLA CERRADA. Antes de revertir exige que `private.metricas_reuniones_implementacion(date,date)` tenga EXACTAMENTE la
-- definición que dejó la migración: `md5(prosrc)` = `ca6fe61e76bcb8bf2d213acb1b7fc030` Y `md5(pg_get_functiondef)` =
-- `ce852e3740f60a57938e2baf2c0b736d`; que su exención analítica lleve la huella que dejó la migración (`d54d4f87…`) y que el
-- sello coincida con la lista. Se niega si la migración no está aplicada, si alguien cambió el CUERPO después, o si alguien
-- cambió un ATRIBUTO después sin tocar el cuerpo (p. ej. `ALTER FUNCTION … SET lock_timeout`, otro `SET`, INVOKER o algo que
-- entre en la definición): en todos esos casos NO se revierte nada y se revisa a mano (o se corrige hacia delante con otra
-- migración). No se promete tolerancia a derivas. (Ensayado: `armar-ensayo.mjs --reversa-con-set` aplica, añade un
-- `SET lock_timeout` e intenta esta reversa: aborta en el preflight y la foto queda idéntica, SET incluido.)
--
-- QUÉ RESTAURA: el cuerpo anterior, byte a byte el de `20260907194622…:27-354` (`md5(prosrc)` vuelve a
-- `6880150bfda80eddda014068aeb9c7da` y `md5(pg_get_functiondef)` a `cec7ee9ec1c31ddd8fa17f1d42e88fc1`), la huella de la
-- exención analítica (`4b28cc419c1b0d84fdbe43afdd5a0909`, calculada sobre el cuerpo restaurado y comparada con la revisada),
-- el sello de la lista (`private.huella_exenciones_analitica_lc()`) y el comentario anterior. El postflight exige esas huellas,
-- que el censo reconozca la exención, la ficha intacta y la FOTO de los `private.assert_*()` sin argumentos idéntica a la de
-- antes de revertir: por cada gate, su estado (`pasa`) o, si cae, el SQLSTATE y el texto ÍNTEGRO de su primer error (sin
-- truncar), con igualdad exacta. Garantiza eso y solo eso: no acredita PASS de los gates que ya caían. La foto barre los
-- `private.assert_*()` SIN los `*_mutantes` (F4.2, 09/10/2026, como la migración y el bloque 2.7): varios aplican, sin guarda
-- propia, DDL de permisos sobre tablas calientes y en la base real tomarían candados ACCESS EXCLUSIVE; se siguen ensayando en
-- el laboratorio (`armar-ensayo.mjs --trinquetes`).
--
-- QUÉ CONSERVA: firma, dueño, `security definer`, `STABLE`, `search_path` vacío y ACL (`create or replace` no los toca).
-- `sellado_en` del sello queda en `now()` (comportamiento de la plantilla del repo, `20260908020020`): el timestamp
-- anterior del sello NO vuelve; sí vuelve su VALOR (`sello`), que es lo que compara el vigía.
--
-- NO DESHACE DATOS: la migración no escribía datos; la métrica se calcula al leer. Tras revertir, la cita realizada antes de
-- su hora vuelve a contar solo en el numerador hasta que llegue su hora: es el defecto que la migración cerraba. Se aplica
-- por el mismo ciclo que la migración.
begin;
set local search_path = '';
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('private.analitica_leads_citas_exenciones'),
  pg_catalog.hashtext('migracion'));
lock table private.analitica_leads_citas_exenciones in share row exclusive mode;
lock table private.analitica_lc_sello in share row exclusive mode;
lock table private.analitica_leads_citas_tope in share row exclusive mode;

do $preflight$
declare
  v_objeto constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_prosrc text;
  v_def text;
  v_fila jsonb;
  v_foto text := '';
  v text;
  r record;
begin
  if to_regprocedure(v_objeto) is null then
    raise exception 'REVERSA realizacion_cuenta_anticipada: falta %; nada que revertir', v_objeto;
  end if;
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_prosrc, v_def
    from pg_proc p where p.oid = v_objeto::regprocedure;
  if v_prosrc is distinct from 'ca6fe61e76bcb8bf2d213acb1b7fc030' then
    raise exception 'REVERSA realizacion_cuenta_anticipada: el cuerpo de private.metricas_reuniones_implementacion no es el que dejó la migración (no está aplicada o cambió después; md5(prosrc) %): revisar antes de revertir', v_prosrc;
  end if;
  if v_def is distinct from 'ce852e3740f60a57938e2baf2c0b736d' then
    raise exception 'REVERSA realizacion_cuenta_anticipada: private.metricas_reuniones_implementacion no tiene exactamente la definición que dejó la migración (un atributo cambió después sin tocar el cuerpo, p. ej. un SET lock_timeout; md5 %): la reversa falla cerrada; revisar a mano antes de revertir', v_def;
  end if;
  select to_jsonb(e) into v_fila from private.analitica_leads_citas_exenciones e where e.objeto = v_objeto;
  if v_fila is null or v_fila ->> 'huella' is distinct from 'd54d4f8773cf1106dadbcb0d793575e2' then
    raise exception 'REVERSA realizacion_cuenta_anticipada: la exención analítica de private.metricas_reuniones_implementacion no lleva la huella que dejó la migración (d54d4f87…): revisar antes de revertir';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id)
       is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSA realizacion_cuenta_anticipada: el sello de la lista de exenciones no coincide con la lista: revisar antes de revertir';
  end if;
  perform set_config('crm.realizacion_rev_ficha_previa',
    (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_objeto::regprocedure),
    true);
  perform set_config('crm.realizacion_rev_exencion_previa', (v_fila - 'huella')::text, true);
  perform set_config('crm.realizacion_rev_otras_exenciones',
    coalesce((select jsonb_agg(to_jsonb(e) order by e.objeto) from private.analitica_leads_citas_exenciones e where e.objeto <> v_objeto)::text, '[]'), true);
  perform set_config('crm.realizacion_rev_tope_previo',
    coalesce((select to_jsonb(t)::text from private.analitica_leads_citas_tope t where t.id), '-'), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('crm.realizacion_rev_trinquetes_previos', v_foto, true);
end
$preflight$;

CREATE OR REPLACE FUNCTION private.metricas_reuniones_implementacion(p_desde date, p_hasta date)
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
  v_ahora timestamptz := now();
  v_payload jsonb;
  v_autorizado boolean;
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

  with cierres_del_nucleo as materialized (
    -- F2.5: los cierres que el NUCLEO reconoce (sin anulados), de la
    -- tabla-base. La ventana llega hasta `ahora` porque una reunion del rango
    -- puede acabar en cierre despues; ese cierre sigue siendo suyo.
    select distinct e.lead_id, min(e.fecha_numerador) as cerrado_en
    from private.conversion_episodios(
      v_ini, greatest(v_fin, v_ahora), null::date, true, '{}'::uuid[],
      private.peso_referido_conversion(date_trunc('month', p_hasta)::date)
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
    group by e.lead_id
  ),
  base as materialized (
    select t.*, ce.modalidad as modalidad,
      coalesce(l.origen, 'sin_origen') as origen,
      l.perfil_id as cliente_id, l.contrato_id, l.convertido_en,
      case when l.moneda = 'USD' then c.capital_usd_nucleo else c.capital_pen_nucleo end as capital,
      l.moneda, c.contrato_creado_en_nucleo as contrato_creado_en,
      coalesce(p.nombre_completo, 'Sin responsable') as responsable_nombre,
      e.rol_crm, e.supervisor_id,
      coalesce(ps.nombre_completo, 'Sin equipo') as supervisor_nombre,
      ce.debio_ocurrir as metrica_debio_ocurrir,
      ce.realizada as metrica_realizada,
      ce.no_show as metrica_no_show,
      ce.cancelada_asesor as metrica_cancelada_asesor,
      ce.cancelada_sistema as metrica_cancelada_sistema,
      ce.reprogramada as metrica_reprogramada,
      ce.pendiente_cierre as metrica_pendiente_cierre,
      ce.programada_futura as metrica_programada_futura
    from private.citas_episodios(v_ini, v_fin, v_ahora) ce
    join crm.tareas t on t.id = ce.tarea_id
    left join crm.leads l on l.id = t.lead_id
    left join lateral (
      -- F4.i: el capital VIVO del lead, del NUCLEO (misma regla que el panel
      -- de Conversiones): contratos del perfil + cooperativas del lead. El
      -- enlace leads.contrato_id jamas se rello (0/466) y por eso esta
      -- pantalla mostro capital 0 SIEMPRE.
      select sum(k.monto) filter (where k.moneda='PEN') as capital_pen_nucleo,
             sum(k.monto) filter (where k.moneda='USD') as capital_usd_nucleo,
             min(k.fecha) as contrato_creado_en_nucleo
      from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) k
      where k.medida = 'stock'
        and ((k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
          or (k.tipo = 'cooperativa' and k.lead_id = l.id))
    ) c on true
    left join public.perfiles p on p.id = t.vendedor_id
    left join crm.equipo e on e.perfil_id = t.vendedor_id
    left join public.perfiles ps on ps.id = e.supervisor_id
  ),
  ultima_realizada as materialized (
    select distinct on (lead_id)
      lead_id, modalidad, origen, vendedor_id, responsable_nombre,
      supervisor_id, supervisor_nombre, cliente_id, contrato_id, convertido_en,
      capital, moneda, contrato_creado_en, vence_en,
      -- ANTES: `cliente_id is not null and convertido_en >= vence_en` (la
      -- ficha del lead) y la columna de contrato enlazado, que nadie rellena
      -- — por eso «terminan en contrato» valia 0 SIEMPRE.
      -- AHORA: el cierre del LEDGER, sin anulados, ocurrido despues de la
      -- reunion. Es la misma verdad que HOY, Ranking, Conversiones y
      -- Distribucion. Las dos banderas miden ya lo mismo: en este CRM el
      -- cierre ES el hecho; el enlace al contrato no existe (se rotula en F3).
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_cliente,
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_contrato,
      -- Explica los cierres que existen en el horizonte consultado pero
      -- preceden la hora prevista de la última cita. No cambia la atribución.
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en < base.vence_en)
        as metrica_cierre_previo
    from base
    where metrica_realizada and lead_id is not null
    order by lead_id, vence_en desc, id desc
  ),
  resumen as (
    select count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_cancelada_sistema)::int as canceladas_sistema,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras
    from base
  ),
  modalidad_base as (
    select modalidad,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base group by modalidad
  ),
  modalidad_conversion as (
    select modalidad,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada group by modalidad
  ),
  origen_base as (
    select origen,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas
    from base group by origen
  ),
  origen_conversion as (
    select origen,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo
    from ultima_realizada group by origen
  ),
  responsables as (
    select vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_asesor
          and cancelada_por_id is distinct from vendedor_id
      )::int as canceladas_ajenas_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base
    group by vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre
  ),
  resultados as (
    select coalesce(resultado_reunion, 'sin_clasificar') as resultado,
      count(*)::int as cantidad
    from base where metrica_realizada
    group by coalesce(resultado_reunion, 'sin_clasificar')
  ),
  conversion_global as (
    select count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada
  )
  select jsonb_build_object(
    'version', 1, 'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta-p_desde)+1, 'zona', 'America/Lima'
    ),
    'resumen', jsonb_build_object(
      'pactadas', r.pactadas, 'debieron_ocurrir', r.debieron_ocurrir,
      'divisor_realizacion', r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas,
      'divisor_asistencia', r.realizadas+r.no_show,
      'canceladas_sistema_vencidas', r.canceladas_sistema_vencidas,
      'reprogramadas_vencidas', r.reprogramadas_vencidas,
      'realizadas', r.realizadas, 'no_concretadas', r.no_show+r.canceladas,
      'no_show', r.no_show, 'canceladas', r.canceladas,
      'canceladas_sistema', r.canceladas_sistema,
      'reprogramadas', r.reprogramadas,
      'pendientes_cierre', r.pendientes_cierre,
      'programadas_futuras', r.programadas_futuras,
      'pct_realizacion', case
        when r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas > 0
        then round(
          100.0*r.realizadas
          /(r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when r.realizadas+r.no_show > 0
        then round(100.0*r.realizadas/(r.realizadas+r.no_show),1) end
    ),
    'conversion', jsonb_build_object(
      'leads_reunidos', cg.leads_reunidos, 'clientes', cg.clientes,
      'leads_con_cierre_previo', cg.leads_con_cierre_previo,
      'contratos', cg.contratos,
      'conversion_cliente_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.clientes/cg.leads_reunidos,1) end,
      'conversion_contrato_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.contratos/cg.leads_reunidos,1) end,
      'capital_pen', cg.capital_pen, 'capital_usd', cg.capital_usd
    ),
    'modalidades', coalesce((select jsonb_agg(jsonb_build_object(
      'modalidad', mb.modalidad, 'pactadas', mb.pactadas,
      'debieron_ocurrir', mb.debieron_ocurrir, 'realizadas', mb.realizadas,
      'no_concretadas', mb.no_show+mb.canceladas, 'no_show', mb.no_show,
      'canceladas', mb.canceladas, 'reprogramadas', mb.reprogramadas,
      'divisor_realizacion',
        mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas,
      'canceladas_sistema_vencidas', mb.canceladas_sistema_vencidas,
      'reprogramadas_vencidas', mb.reprogramadas_vencidas,
      'pendientes_cierre', mb.pendientes_cierre,
      'pct_realizacion', case
        when mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas > 0
        then round(
          100.0*mb.realizadas
          /(mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when mb.realizadas+mb.no_show > 0 then round(100.0*mb.realizadas/(mb.realizadas+mb.no_show),1) end,
      'leads_reunidos', coalesce(mc.leads_reunidos,0),
      'leads_con_cierre_previo', coalesce(mc.leads_con_cierre_previo,0),
      'clientes', coalesce(mc.clientes,0), 'contratos', coalesce(mc.contratos,0),
      'conversion_cliente_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.clientes/mc.leads_reunidos,1) end,
      'conversion_contrato_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.contratos/mc.leads_reunidos,1) end,
      'capital_pen', coalesce(mc.capital_pen,0), 'capital_usd', coalesce(mc.capital_usd,0)
    ) order by case mb.modalidad when 'presencial' then 1 when 'virtual' then 2 else 3 end)
      from modalidad_base mb left join modalidad_conversion mc using (modalidad)), '[]'::jsonb),
    'origenes', coalesce((select jsonb_agg(jsonb_build_object(
      'origen', ob.origen, 'pactadas', ob.pactadas, 'realizadas', ob.realizadas,
      'no_show', ob.no_show, 'canceladas', ob.canceladas,
      'pct_realizacion', case
        when ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas > 0
        then round(
          100.0*ob.realizadas
          /(ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas),
          1
        )
      end,
      'leads_reunidos', coalesce(oc.leads_reunidos,0),
      'leads_con_cierre_previo', coalesce(oc.leads_con_cierre_previo,0),
      'clientes', coalesce(oc.clientes,0), 'contratos', coalesce(oc.contratos,0),
      'conversion_contrato_pct', case when coalesce(oc.leads_reunidos,0)>0 then round(100.0*oc.contratos/oc.leads_reunidos,1) end
    ) order by ob.realizadas desc, ob.pactadas desc, ob.origen)
      from origen_base ob left join origen_conversion oc using (origen)), '[]'::jsonb),
    'responsables', coalesce((select jsonb_agg(jsonb_build_object(
      'responsable_id', rr.vendedor_id, 'nombre', rr.responsable_nombre,
      'rol', rr.rol_crm, 'supervisor_id', rr.supervisor_id,
      'supervisor_nombre', rr.supervisor_nombre,
      'pactadas', rr.pactadas, 'realizadas', rr.realizadas,
      'debieron_ocurrir', rr.debieron_ocurrir,
      'divisor_realizacion', rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
        -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas,
      'canceladas_sistema_vencidas', rr.canceladas_sistema_vencidas,
      'canceladas_ajenas_vencidas', rr.canceladas_ajenas_vencidas,
      'reprogramadas_vencidas', rr.reprogramadas_vencidas,
      'programadas_futuras', rr.programadas_futuras,
      'no_show', rr.no_show, 'canceladas', rr.canceladas,
      'reprogramadas', rr.reprogramadas,
      'pendientes_cierre', rr.pendientes_cierre,
      'pct_realizacion', case
        when rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
          -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas > 0
        then round(
          100.0*rr.realizadas
          /(rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
            -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas),
          1
        )
      end
    ) order by rr.realizadas desc, rr.pactadas desc, rr.responsable_nombre) from responsables rr), '[]'::jsonb),
    'resultados', coalesce((select jsonb_agg(jsonb_build_object(
      'resultado', resultado, 'cantidad', cantidad
    ) order by cantidad desc, resultado) from resultados), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join conversion_global cg;

  return v_payload;
end;
$function$;

comment on function private.metricas_reuniones_implementacion(date, date) is
  'Pantalla Reuniones (F2.5): «terminan en cliente/contrato» ya NO miran crm.leads.contrato_id (columna que nadie rellena) ni la ficha del lead con sus anulados: cuentan cierres del LEDGER posteriores a la reunion, sin anular, leidos de private.conversion_episodios. Misma verdad que HOY/Ranking/Conversiones/Distribucion (H16).';

do $resello$
declare
  v_objeto constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_huella text;
  v_n integer;
begin
  select md5(regexp_replace(regexp_replace(
             lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
             '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) into v_huella
    from pg_proc p where p.oid = v_objeto::regprocedure;
  if v_huella is distinct from '4b28cc419c1b0d84fdbe43afdd5a0909' then
    raise exception 'REVERSA realizacion_cuenta_anticipada: la huella normalizada del cuerpo restaurado (%) no es la original (4b28cc41…)', v_huella;
  end if;
  update private.analitica_leads_citas_exenciones
     set huella = v_huella
   where objeto = v_objeto and huella = 'd54d4f8773cf1106dadbcb0d793575e2';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'REVERSA realizacion_cuenta_anticipada: se esperaba restaurar una exención y fueron %', v_n;
  end if;
  update private.analitica_lc_sello
     set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
   where id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'REVERSA realizacion_cuenta_anticipada: se esperaba actualizar un sello y fueron %', v_n;
  end if;
end
$resello$;

do $postflight$
declare
  v_objeto constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_prosrc text;
  v_def text;
  v_src text;
  v_foto text := '';
  v text;
  r record;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), p.prosrc into v_prosrc, v_def, v_src
    from pg_proc p where p.oid = v_objeto::regprocedure;
  if v_prosrc is distinct from '6880150bfda80eddda014068aeb9c7da'
     or v_def is distinct from 'cec7ee9ec1c31ddd8fa17f1d42e88fc1' then
    raise exception 'REVERSA realizacion_cuenta_anticipada: private.metricas_reuniones_implementacion no quedó como estaba antes de la migración (md5(prosrc) %, definición %)', v_prosrc, v_def;
  end if;
  if position('(ce.debio_ocurrir or ce.realizada) as metrica_debio_ocurrir' in v_src) > 0
     or position(E'\n      ce.debio_ocurrir as metrica_debio_ocurrir' in v_src) = 0 then
    raise exception 'REVERSA realizacion_cuenta_anticipada: el cambio sigue en private.metricas_reuniones_implementacion';
  end if;
  if (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_objeto::regprocedure)
     is distinct from current_setting('crm.realizacion_rev_ficha_previa', true) then
    raise exception 'REVERSA realizacion_cuenta_anticipada: cambió el dueño, la ACL o un atributo de private.metricas_reuniones_implementacion';
  end if;
  if (select to_jsonb(e) - 'huella' from private.analitica_leads_citas_exenciones e where e.objeto = v_objeto)
       is distinct from current_setting('crm.realizacion_rev_exencion_previa', true)::jsonb
     or (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = v_objeto)
       is distinct from '4b28cc419c1b0d84fdbe43afdd5a0909' then
    raise exception 'REVERSA realizacion_cuenta_anticipada: la exención no quedó con su huella original (4b28cc41…) o se alteró su declaración';
  end if;
  if coalesce((select jsonb_agg(to_jsonb(e) order by e.objeto) from private.analitica_leads_citas_exenciones e where e.objeto <> v_objeto)::text, '[]')
       is distinct from current_setting('crm.realizacion_rev_otras_exenciones', true)
     or coalesce((select to_jsonb(t)::text from private.analitica_leads_citas_tope t where t.id), '-')
       is distinct from current_setting('crm.realizacion_rev_tope_previo', true) then
    raise exception 'REVERSA realizacion_cuenta_anticipada: se alteró otra exención o el tope';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id)
       is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSA realizacion_cuenta_anticipada: el sello no coincide con la lista restaurada';
  end if;
  if not exists (select 1 from private.contadores_crudos_leads_citas() c
                  where c.objeto = v_objeto and c.declarada and c.huella_ok) then
    raise exception 'REVERSA realizacion_cuenta_anticipada: el censo analítico no reconoce la exención restaurada';
  end if;
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  -- Foto íntegra (estado o SQLSTATE + texto completo del primer error): igualdad exacta con la de antes de revertir.
  if v_foto is distinct from current_setting('crm.realizacion_rev_trinquetes_previos', true) then
    raise exception E'REVERSA realizacion_cuenta_anticipada: algún private.assert_*() da otro resultado que antes de revertir.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('crm.realizacion_rev_trinquetes_previos', true), v_foto;
  end if;
  raise notice 'REVERSA realizacion_cuenta_anticipada: cuerpo % · definición % · exención 4b28cc41… · trinquetes con estado y texto íntegro del primer error idénticos', v_prosrc, v_def;
end
$postflight$;

commit;
