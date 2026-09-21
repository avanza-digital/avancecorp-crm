-- Testigo del servidor para el «Depósito %» de Citas (Miguel, 21/09/2026).
--
-- Problema: Citas calcula en el navegador (components/citas/avance.ts) el
-- «Depósito %» del mes a partir de los hechos que sirve
-- private.citas_gerencia_consulta: 8 reglas configurables y 9 filtros, y al
-- final divide clientes vinculados entre entrevistas. Los hechos ya vienen del
-- nucleo (cierres de private.conversion_cierres), pero NADIE contrasta la
-- aritmetica: era la unica pantalla con contabilidad propia sin testigo.
--
-- Que hace: una funcion NUEVA e INDEPENDIENTE, private.citas_testigo_mes,
-- calcula con sus propias consultas —no con los arrays que arma la funcion
-- grande— los mismos numeros del TOTAL del mes SIN filtros y con la
-- configuracion vigente (private.control_citas_vigente): entrevistas,
-- personas entrevistadas, clientes del periodo, clientes vinculados a una
-- entrevista previa, base y porcentaje. El envoltorio expuesto
-- crm.citas_gerencia_consulta_fn le anade la clave `testigo` al payload.
-- El front, cuando no tiene ningun filtro puesto, compara su total con el
-- testigo y, si no coincide, ensena «Cifras en revision» en vez del numero.
--
-- Es la misma idea que la sonda M = R = D del gate de conversion: dos caminos
-- distintos (SQL aqui, TypeScript alla) que deben decir lo mismo. No es
-- tautologico porque no reutiliza ni una CTE de la funcion grande.
--
-- La funcion de 17 KB private.citas_gerencia_consulta NO SE TOCA (huella
-- c651d60710ec3f45f428fe3b68617210, reconstruida en local con los dos parches
-- en sitio de 20260914044939 y 20260915170018 y verificada contra produccion).
--
-- Orden de publicacion: clave NUEVA en la respuesta => el front que la admite
-- como opcional puede ir antes o a la vez; sin front nuevo, la clave se ignora.
--
-- TRINQUETE DE ANALITICA (auditor-rls, P1): el testigo es un contador crudo a
-- proposito —lee crm.leads/crm.tareas y cuenta— y ademas consume
-- private.conversion_cierres, asi que private.assert_analitica_leads_citas()
-- exige que este DECLARADO. Se declara aqui con su huella y su razon, y se
-- resella. Lo que NO se hace es poner el assert en el preflight: el trinquete
-- YA ESTA EN ROJO en produccion (comprobado el 21/09) por
-- `crm.contrato_eliminar_auditado(uuid,uuid)`, sin declarar desde la migracion
-- del 05/09; bloquear esta migracion con la deuda de otra solo pararia el
-- trabajo. Al final se comprueba lo unico que esta migracion puede prometer:
-- que EL TESTIGO queda declarado y que el sello coincide.
-- Censo al 21/09: 35 contadores, tope 30, 36 exenciones. El tope solo puede
-- bajar (trigger `trg_analitica_lc_tope_solo_baja`), asi que el exceso es deuda
-- previa que hay que decidir aparte; queda anotado en el ledger.
--
-- Plan: «Una sola definicion de conversion», fase F2 (vault, 21/09/2026).
-- Reversa: reinstalar el envoltorio de 20260909003243 (select
-- private.citas_gerencia_consulta(p_desde,p_hasta)) y drop function
-- private.citas_testigo_mes(date,date).
-- Requiere aprobacion expresa antes de instalar en produccion.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;
-- El trinquete se declara en esta transaccion: se toma su exclusion antes.
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

do $preflight$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = 'crm.citas_gerencia_consulta_fn(date,date)'::regprocedure)
     is distinct from '944fda17ec7bb1b8b1ae96e2b6aa1c89' then
    raise exception 'PREFLIGHT F2: el envoltorio crm.citas_gerencia_consulta_fn no es el auditado (944fda17)';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure)
     is distinct from 'c651d60710ec3f45f428fe3b68617210' then
    raise exception 'PREFLIGHT F2: private.citas_gerencia_consulta no es la version auditada (c651d607): revisar la formula del testigo antes de instalar';
  end if;
  if to_regprocedure('private.citas_testigo_mes(date,date)') is not null then
    raise exception 'PREFLIGHT F2: private.citas_testigo_mes ya existe; no reinstalar sin revisar';
  end if;
end;
$preflight$;

create or replace function private.citas_testigo_mes(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_ahora timestamptz := now();
  v_ini timestamptz;
  v_fin timestamptz;
  v_corte timestamptz;
  v_limite timestamptz;
  v_control jsonb;
  v_cfg jsonb;
  v_mes_res text;
  v_ana_res text;
  v_base text;
  v_act text;
  v_listas boolean;
  v_entrevistas integer;
  v_personas integer;
  v_clientes_periodo integer;
  v_clientes integer;
  v_base_n integer;
begin
  -- Misma puerta que la funcion grande: solo gerencia.
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null
     or p_desde <> date_trunc('month', p_desde)::date
     or p_hasta <> (date_trunc('month', p_desde) + interval '1 month - 1 day')::date then
    raise exception 'Seleccione un mes válido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  -- periodoAvance(...).corte del front: min(ahora, ultimo instante del mes).
  v_corte := least(v_ahora, v_fin - interval '1 millisecond');

  v_control := private.control_citas_vigente(p_desde);
  v_cfg := v_control -> 'configuracion';
  v_mes_res := v_cfg ->> 'mes_resultado';
  v_ana_res := v_cfg ->> 'analista_resultado';
  v_base := v_cfg ->> 'base_depositos';
  v_act := v_cfg ->> 'actividad_manuales';
  -- reglasListas del front, calcado campo a campo.
  v_listas := coalesce((v_control ->> 'version')::int, 0) > 0
    and v_control ->> 'mes_inicio' is not null
    and v_cfg ->> 'mes_inicio' is not null
    and v_mes_res is not null and v_ana_res is not null and v_base is not null
    and v_cfg ->> 'base_avance' is not null
    and v_cfg ->> 'conteo_entrevistas' is not null
    and v_act is not null;
  -- limiteResultado del front.
  v_limite := case when v_mes_res = 'asignacion' then v_ahora else v_corte end;

  with identidad as (
    -- La misma identidad canonica que usa la poblacion: persona > perfil > lead.
    select l.id as lead_id, coalesce(l.alta_manual, false) as alta_manual, l.creado_por,
      coalesce(
        case when l.inversionista_id is not null
          then 'persona:' || private.inversionista_canonica(l.inversionista_id)::text end,
        -- `order by 1 limit 1` (patron de 20260915170018): el indice unico de
        -- crm.inversionistas es PARCIAL (excluye 'fusionado'), asi que sin tope
        -- la subconsulta podria devolver dos filas y tumbar con 21000 TODA la
        -- pantalla de Citas, no solo el testigo. Hoy no hay ningun perfil con
        -- dos canonicas (medido en produccion el 21/09); la superficie se
        -- cierra igual.
        (select distinct 'persona:' || private.inversionista_canonica(i.id)::text
           from crm.inversionistas i where i.perfil_id = l.perfil_id
           order by 1 limit 1),
        'perfil:' || l.perfil_id::text,
        'lead:' || l.id::text) as persona,
      primera.analista_id as analista_origen,
      primera.asignado_en as primera_asignacion
    from crm.leads l
    left join lateral (
      select la.analista_id, la.asignado_en from crm.lead_asignaciones la
      where la.lead_id = l.id and la.asignado_en <= v_ahora
      order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id limit 1) primera on true
    where l.activo
  ), entrevistas as (
    -- Una entrevista realizada es una reunion completada con su actividad
    -- reunion_realizada; la fecha que cuenta es la del registro de asistencia.
    select t.lead_id, t.vendedor_id as analista_evento, a.creado_en as asistio_en,
      i.persona, i.alta_manual, i.creado_por, i.analista_origen, i.primera_asignacion
    from crm.tareas t
    join crm.actividades a on a.id = t.resultado_actividad_id and a.lead_id = t.lead_id
      and a.tipo = 'reunion_realizada' and a.creado_en <= v_ahora
    join identidad i on i.lead_id = t.lead_id
    where t.tipo = 'reunion' and t.activo and t.estado = 'completada' and t.creado_en <= v_ahora
  ), visitas as (
    select e.*, case when v_ana_res = 'asignacion' then e.analista_origen else e.analista_evento end as duenio
    from entrevistas e
    where e.asistio_en <= v_limite
      and case when v_mes_res = 'asignacion'
            then e.primera_asignacion is not null and e.primera_asignacion >= v_ini and e.primera_asignacion < v_fin
            else e.asistio_en >= v_ini and e.asistio_en < v_fin end
  ), visitas_ambito as (
    -- ambito(owner) del total: hay dueno; actividad(): regla de manuales.
    select * from visitas v
    where v.duenio is not null
      and (v_act = 'incluir' or not v.alta_manual or v.creado_por is distinct from v.duenio)
  ), nucleo as (
    select c.lead_id, c.analista_id, c.tipo
    from private.conversion_cierres('-infinity'::timestamptz, v_ahora + interval '1 microsecond',
      p_desde, true, '{}'::uuid[], 1, null::uuid[]) c
    where not c.anulado
  ), cierres as (
    select l.id as lead_id, l.convertido_en, n.analista_id as analista_evento,
      i.persona, i.alta_manual, i.creado_por, i.analista_origen, i.primera_asignacion
    from crm.leads l
    join public.perfiles pc on pc.id = l.perfil_id and pc.rol = 'cliente'
    join identidad i on i.lead_id = l.id
    left join (select distinct on (lead_id) lead_id, analista_id from nucleo
               order by lead_id, (tipo = 'cierre') desc) n on n.lead_id = l.id
    where l.activo and l.etapa = 'convertido' and l.convertido_en is not null
      and l.convertido_en <= v_ahora and not private.cierre_anulado(l.id)
  ), clientes_mes as (
    select c.*, case when v_ana_res = 'asignacion' then c.analista_origen else c.analista_evento end as duenio
    from cierres c
    where c.convertido_en <= v_limite
      and case when v_mes_res = 'asignacion'
            then c.primera_asignacion is not null and c.primera_asignacion >= v_ini and c.primera_asignacion < v_fin
            else c.convertido_en >= v_ini and c.convertido_en < v_fin end
  ), clientes_ambito as (
    select * from clientes_mes c
    where c.duenio is not null
      and (v_act = 'incluir' or not c.alta_manual or c.creado_por is distinct from c.duenio)
  ), vinculados as (
    -- Cliente vinculado: tuvo una entrevista del periodo ANTES de convertirse.
    select distinct c.persona from clientes_ambito c
    where exists (select 1 from visitas_ambito v where v.persona = c.persona and v.asistio_en <= c.convertido_en)
  )
  select
    (select count(*) from visitas_ambito),
    (select count(distinct persona) from visitas_ambito),
    (select count(distinct persona) from clientes_ambito),
    (select count(*) from vinculados)
  into v_entrevistas, v_personas, v_clientes_periodo, v_clientes;

  v_base_n := case when v_base = 'entrevistas' then v_entrevistas else v_personas end;

  return jsonb_build_object(
    'version', 1,
    'calculado_en', v_ahora,
    'reglas_listas', v_listas,
    'configuracion', jsonb_build_object(
      'mes_resultado', v_mes_res, 'analista_resultado', v_ana_res,
      'base_depositos', v_base, 'actividad_manuales', v_act),
    'entrevistas', v_entrevistas,
    'personas_entrevistadas', v_personas,
    'clientes_periodo', v_clientes_periodo,
    'clientes_vinculados', v_clientes,
    'base_conversion', v_base_n,
    'conversion_pct', case when v_listas and v_base_n > 0
      then round(100.0 * v_clientes / v_base_n, 2) end
  );
end;
$function$;

comment on function private.citas_testigo_mes(date, date) is
  'Testigo independiente del Deposito % de Citas: total del mes sin filtros con la configuracion vigente (entrevistas, personas entrevistadas, clientes del periodo, clientes vinculados, base y porcentaje). No reutiliza las CTE de citas_gerencia_consulta; el front lo compara con su propio total y ensena Cifras en revision si no cuadra. Solo gerencia.';

revoke all on function private.citas_testigo_mes(date, date)
  from public, anon, authenticated, service_role;
grant execute on function private.citas_testigo_mes(date, date) to authenticated;

create or replace function crm.citas_gerencia_consulta_fn(p_desde date, p_hasta date)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select private.citas_gerencia_consulta(p_desde, p_hasta)
      || jsonb_build_object('testigo', private.citas_testigo_mes(p_desde, p_hasta));
$function$;

comment on function crm.citas_gerencia_consulta_fn(date, date) is
  'Puerta de Citas para gerencia: el payload de private.citas_gerencia_consulta mas la clave testigo (private.citas_testigo_mes), el calculo independiente del Deposito % del mes sin filtros.';

-- Declaracion en el trinquete: contador crudo a proposito, con su razon.
insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella, razon)
select 'private.citas_testigo_mes(date,date)', 'funcion',
  pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
    pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
  'Testigo independiente del Deposito % de Citas: cuenta entrevistas, personas entrevistadas, clientes del periodo y clientes vinculados del mes SIN filtros, con la configuracion vigente, para contrastar la aritmetica que hoy hace el navegador. Es un contador crudo A PROPOSITO: si reutilizara las CTE de citas_gerencia_consulta seria tautologico y no probaria nada. Los cierres si vienen del nucleo (private.conversion_cierres). Solo gerencia; devuelve conteos agregados, sin identificadores ni PII; no calcula capital, ticket ni metas.'
from pg_catalog.pg_proc p
where p.oid = 'private.citas_testigo_mes(date,date)'::regprocedure;

update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  v_src text;
  v_secdef boolean;
  v_vol "char";
  v_config text[];
  v_owner text;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
  where p.oid = 'crm.citas_gerencia_consulta_fn(date,date)'::regprocedure;
  if pg_catalog.strpos(v_src, 'private.citas_testigo_mes(p_desde, p_hasta)') = 0
     or pg_catalog.strpos(v_src, 'private.citas_gerencia_consulta(p_desde, p_hasta)') = 0 then
    raise exception 'POSTFLIGHT F2: el envoltorio no compone consulta + testigo';
  end if;
  select p.prosecdef, p.provolatile, p.proconfig, r.rolname
    into v_secdef, v_vol, v_config, v_owner
  from pg_catalog.pg_proc p join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'private.citas_testigo_mes(date,date)'::regprocedure;
  if v_owner is distinct from 'postgres' or not v_secdef or v_vol is distinct from 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT F2: owner/secdef/stable/search_path del testigo inesperados';
  end if;
  if not pg_catalog.has_function_privilege('authenticated', 'private.citas_testigo_mes(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'private.citas_testigo_mes(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'private.citas_testigo_mes(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.citas_gerencia_consulta_fn(date,date)', 'EXECUTE') then
    raise exception 'POSTFLIGHT F2: privilegios efectivos inesperados';
  end if;
  -- La funcion grande sigue intacta.
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = 'private.citas_gerencia_consulta(date,date)'::regprocedure)
     is distinct from 'c651d60710ec3f45f428fe3b68617210' then
    raise exception 'POSTFLIGHT F2: private.citas_gerencia_consulta cambio durante la instalacion';
  end if;
  -- El testigo queda DECLARADO con la huella de su cuerpo instalado y el sello
  -- del trinquete coincide. No se afirma que el trinquete entero este verde:
  -- arrastra la deuda de crm.contrato_eliminar_auditado, que no es de aqui.
  if not exists (
    select 1 from private.analitica_leads_citas_exenciones e
    join pg_catalog.pg_proc p on p.oid = 'private.citas_testigo_mes(date,date)'::regprocedure
    where e.objeto = 'private.citas_testigo_mes(date,date)'
      and e.huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
        pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
  ) then
    raise exception 'POSTFLIGHT F2: el testigo no quedo declarado con la huella de su cuerpo';
  end if;
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT F2: el sello del trinquete no coincide con las exenciones';
  end if;
end;
$postflight$;

commit;
