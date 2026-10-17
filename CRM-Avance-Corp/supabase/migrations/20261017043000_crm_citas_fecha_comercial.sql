-- Citas: mes de venta por fecha comercial; registro intacto para auditoría.
-- Extensión aditiva: clientes anteriores conservan todos sus campos y testigo.
-- No modifica ventas, acreditaciones, capital ni sellos de meses monetarios.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
set local search_path=pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello in share row exclusive mode;
-- El censo global ya tiene incidencias ajenas a Citas (evidencia 17/10/2026).
-- Guardar su estado entero: esta migración no puede ocultar ni añadir ninguna.
create temporary table citas_comercial_censo_antes on commit drop as
  select * from private.contadores_crudos_leads_citas();
create temporary table citas_comercial_atributos_antes on commit drop as
  select oid,proowner,proacl,prosecdef,provolatile,proconfig from pg_proc
  where oid in ('private.citas_gerencia_consulta(date,date)'::regprocedure,
    'private.citas_testigo_mes(date,date)'::regprocedure,
    to_regprocedure('private.citas_gerencia_consulta_corte(date,date,uuid)'));
do $preflight$
begin
  if (select md5(prosrc) from pg_proc where oid='private.citas_gerencia_consulta(date,date)'::regprocedure)
    is distinct from '3dc1c5481ca9dc1a6c45dfab969a6a0b'
    or (select md5(prosrc) from pg_proc where oid='private.citas_testigo_mes(date,date)'::regprocedure)
    is distinct from '9df82d2d322795b7875d627da84d69d3' then
    raise exception 'PREFLIGHT fecha comercial: cambiaron lector/testigo; conciliar antes de publicar';
  end if;
  if (select md5(prosrc) from pg_proc where oid='private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'::regprocedure)
    is distinct from '84a681ce6d06a192eb2c0a461a71fa94' then
    raise exception 'PREFLIGHT fecha comercial: cambió el contrato del núcleo de cierres';
  end if;
  if (select sello from private.analitica_lc_sello where id)
    is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'Citas fecha comercial: sello de exenciones inconsistente';
  end if;
  if (select count(*) from private.analitica_leads_citas_exenciones e join pg_proc p
    on p.oid=to_regprocedure(e.objeto)
    where e.objeto in ('private.citas_gerencia_consulta(date,date)','private.citas_testigo_mes(date,date)')
      and e.huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))) <> 2 then
    raise exception 'Citas fecha comercial: declaraciones previas de lector/testigo inconsistentes';
  end if;
end;
$preflight$;

-- Incluir el lector de valoración si ya existe: se conserva todo su capital.
do $lectores$
declare v_oid regprocedure; v_def text; v_buscar text[]; v_nuevo text[]; i integer;
begin
  foreach v_oid in array array[
    'private.citas_gerencia_consulta(date,date)'::regprocedure,
    to_regprocedure('private.citas_gerencia_consulta_corte(date,date,uuid)')
  ] loop
    if v_oid is null then continue; end if;
    v_def := pg_get_functiondef(v_oid);
    v_buscar := array[
$p0$  -- Un evento por lead, con cliente vinculado y conversión vigente al corte.$p0$,
$p1$  select coalesce(jsonb_agg(jsonb_build_object(
    'lead_id',l.id,'perfil_id',l.perfil_id,'convertido_en',l.convertido_en$p1$,
$p2$'convertido_en',l.convertido_en,'analista_id',c.analista_id,$p2$,
$p3$'disponibilidad_depositos','conversion_cliente','citas_clientes',v_clientes,$p3$,
$p4$select c.lead_id,c.analista_id,c.fecha_numerador from private.conversion_cierres($p4$,
$p5$array(select (p->>'lead_id')::uuid from jsonb_array_elements(v_poblacion) p)) c
    where not c.anulado$p5$
    ];
    v_nuevo := array[
$p0$  -- La fecha comercial se agrega sin alterar el evento de registro anterior.
  -- Una fuente ambigua no produce una fecha arbitraria. El contrato de gestión
  -- rechaza además leads repetidos; no se disimulan acreditaciones duplicadas.
  -- Un evento por lead, con cliente vinculado y conversión vigente al corte.$p0$,
$p1$  with comerciales as materialized (
    select c.lead_id, min((c.fecha_numerador at time zone 'America/Lima')::date) as fecha
    from private.conversion_cierres('-infinity'::timestamptz,v_ahora+interval '1 microsecond',
      p_desde,true,'{}'::uuid[],1,
      array(select (c->>'lead_id')::uuid from jsonb_array_elements(v_filas) c)) c
    where c.tipo='cierre' and not c.anulado
    group by c.lead_id having count(*)=1
      and bool_or(v_rol='gerencia' or c.analista_id=any(v_visibles))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'lead_id',l.id,'perfil_id',l.perfil_id,'convertido_en',l.convertido_en,
    'fecha_comercial',(select c.fecha from comerciales c where c.lead_id=l.id)$p1$,
$p2$'convertido_en',l.convertido_en,'analista_id',c.analista_id,
    'fecha_comercial',c.fecha_comercial,$p2$,
$p3$'disponibilidad_depositos','conversion_cliente','criterio_depositos','fecha_comercial','citas_clientes',v_clientes,$p3$,
$p4$select c.lead_id,c.analista_id,c.fecha_numerador,
      case when c.tipo='cierre' and c.hechos_comerciales=1
        then (c.fecha_numerador at time zone 'America/Lima')::date end as fecha_comercial
    from (
      -- La unicidad es global; recortar por equipo no vuelve inequívoca una venta.
      select c.*,count(*) filter(where c.tipo='cierre' and not c.anulado)
        over(partition by c.lead_id) as hechos_comerciales
      from private.conversion_cierres($p4$,
$p5$array(select (p->>'lead_id')::uuid from jsonb_array_elements(v_poblacion) p)) c
    ) c
    where not c.anulado$p5$
    ];
    for i in 1..array_length(v_buscar,1) loop
      if (length(v_def)-length(replace(v_def,v_buscar[i],'')))/length(v_buscar[i]) <> 1 then
        raise exception 'PREFLIGHT fecha comercial: lector %, ancla % no reconocida',v_oid,i;
      end if;
      v_def := replace(v_def,v_buscar[i],v_nuevo[i]);
    end loop;
    execute v_def;
  end loop;
end;
$lectores$;

CREATE OR REPLACE FUNCTION private.citas_testigo_mes(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_comercial jsonb;
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
    select c.lead_id, c.analista_id, c.tipo, (c.fecha_numerador at time zone 'America/Lima')::date as fecha_comercial
    from private.conversion_cierres('-infinity'::timestamptz, v_ahora + interval '1 microsecond',
      p_desde, true, '{}'::uuid[], 1, null::uuid[]) c
    where not c.anulado and c.tipo = 'cierre'
  ), cierres as (
    select l.id as lead_id, l.convertido_en, n.fecha_comercial, n.analista_id as analista_evento,
      i.persona, i.alta_manual, i.creado_por, i.analista_origen, i.primera_asignacion
    from crm.leads l
    join public.perfiles pc on pc.id = l.perfil_id and pc.rol = 'cliente'
    join identidad i on i.lead_id = l.id
    join nucleo n on n.lead_id = l.id
      and not exists (select 1 from nucleo otro where otro.lead_id = n.lead_id group by otro.lead_id having count(*) > 1)
    where l.activo and l.etapa = 'convertido' and l.convertido_en is not null
      and l.convertido_en <= v_ahora and not private.cierre_anulado(l.id)
  ), clientes_mes as (
    select c.*, case when v_ana_res = 'asignacion' then c.analista_origen else c.analista_evento end as duenio
    from cierres c
    where c.fecha_comercial between p_desde and p_hasta
      and c.fecha_comercial <= (v_ahora at time zone 'America/Lima')::date
  ), clientes_ambito as (
    select * from clientes_mes c
    where c.duenio is not null
      and (v_act = 'incluir' or not c.alta_manual or c.creado_por is distinct from c.duenio)
  ), vinculados as (
    -- Precisión comercial: día local; una entrevista del mismo día es compatible.
    -- La carga tardía nunca prueba una entrevista anterior a la venta.
    select distinct c.persona from clientes_ambito c
    where exists (select 1 from visitas_ambito v where v.persona = c.persona and (v.asistio_en at time zone 'America/Lima')::date <= c.fecha_comercial)
  )
  select
    (select count(*) from visitas_ambito),
    (select count(distinct persona) from visitas_ambito),
    (select count(distinct persona) from clientes_ambito),
    (select count(*) from vinculados)
  into v_entrevistas, v_personas, v_clientes_periodo, v_clientes;

  v_base_n := case when v_base = 'entrevistas' then v_entrevistas else v_personas end;
  v_comercial := jsonb_build_object(
    'version', 1, 'calculado_en', v_ahora, 'reglas_listas', v_listas,
    'configuracion', jsonb_build_object('mes_resultado', v_mes_res, 'analista_resultado', v_ana_res,
      'base_depositos', v_base, 'actividad_manuales', v_act),
    'entrevistas', v_entrevistas, 'personas_entrevistadas', v_personas,
    'clientes_periodo', v_clientes_periodo, 'clientes_vinculados', v_clientes,
    'base_conversion', v_base_n,
    'conversion_pct', case when v_listas and v_base_n > 0 then round(100.0 * v_clientes / v_base_n, 2) end);

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
    'comercial', v_comercial,
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

update private.analitica_leads_citas_exenciones e
set huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
    razon=e.razon || ' Citas: extensión aditiva de fecha comercial canónica; registro y testigo heredados intactos, comprobación comercial independiente.'
from pg_proc p
where p.oid in ('private.citas_gerencia_consulta(date,date)'::regprocedure,
  'private.citas_testigo_mes(date,date)'::regprocedure,
  to_regprocedure('private.citas_gerencia_consulta_corte(date,date,uuid)'))
  and e.objeto=p.oid::regprocedure::text;
update private.analitica_lc_sello
set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
do $postflight$
begin
  if (select sello from private.analitica_lc_sello where id)
    is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'Citas fecha comercial: sello de exenciones inconsistente';
  end if;
  if exists((select * from citas_comercial_censo_antes except all select * from private.contadores_crudos_leads_citas())
    union all (select * from private.contadores_crudos_leads_citas() except all select * from citas_comercial_censo_antes)) then
    raise exception 'POSTFLIGHT fecha comercial: cambió el censo analítico fuera de su estado previo';
  end if;
  if exists(select 1 from citas_comercial_atributos_antes a join pg_proc p on p.oid=a.oid
    where (a.proowner,a.proacl,a.prosecdef,a.provolatile,a.proconfig)
      is distinct from (p.proowner,p.proacl,p.prosecdef,p.provolatile,p.proconfig)) then
    raise exception 'POSTFLIGHT fecha comercial: cambiaron atributos o permisos';
  end if;
  if has_function_privilege('anon' ,'crm.citas_gerencia_consulta_fn(date,date)','EXECUTE') then
    raise exception 'POSTFLIGHT fecha comercial: anon no puede ejecutar Citas';
  end if;
end;
$postflight$;
commit;
