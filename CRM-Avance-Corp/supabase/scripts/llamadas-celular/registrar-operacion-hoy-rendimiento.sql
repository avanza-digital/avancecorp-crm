begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtext('crm_llamadas_celular_registro'));
do $chk$
declare
  v_f record;
  v_p record;
  v_sql constant text := $mig$-- F4-e: contactabilidad materializada por lead. Conserva contrato, firma, propietario, ACL y atributos.
-- Corrige EXPLAIN de 20.000 eventos/100 días: ~2.9 s → ~15–22 ms, sin índices nuevos.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
do $pre$
begin
  if coalesce((select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid=pg_catalog.to_regprocedure('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)')), '') <> '648a8c7341599f6e28e2e3edd94ebe52'
     or coalesce((select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid=pg_catalog.to_regprocedure('crm.llamadas_celular_operacion_hoy_fn(uuid)')), '') <> '952abdd141001309f08ab56e8a828698' then
    raise exception 'F4E_RENDIMIENTO: catálogo distinto del esperado';
  end if;
end $pre$;
create temp table f4e_catalogo_previo on commit drop as
select oid,pg_catalog.to_jsonb(p)-'prosrc' as atributos from pg_catalog.pg_proc p
where p.oid in ('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)'::regprocedure,
               'crm.llamadas_celular_operacion_hoy_fn(uuid)'::regprocedure);
create or replace function private.llamadas_celular_operacion_hoy(p_actor uuid, p_supervisor_id uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_rol     text := private.rol_crm(p_actor);
  -- Hoy en Lima: el mismo molde que private.llamadas_celular_resueltas_hoy.
  v_desde   timestamptz := pg_catalog.date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima';
  -- Retención de lo que no tiene enlace (D5): lo que la purga conserva es lo que se muestra.
  v_dias    integer := coalesce((select pol.dias_retencion_sin_resolver from crm.llamadas_celular_politica pol where pol.singleton), 30);
  v_roster  jsonb;
  v_salud   jsonb;
  v_alcance text;
begin
  -- El actor es siempre quien está autenticado (defensa en profundidad: el roster del pulso y vendedor_ids_visibles
  -- lo exigen por su cuenta; aquí no se confía en que el único llamador sea la puerta).
  if p_actor is null or p_actor is distinct from (select auth.uid()) then
    raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
  end if;
  if v_rol = 'gerencia' then
    -- Rol efectivo (equipo y perfil activos), el mismo que usa el roster: un supervisor dado de baja a medias no cuenta.
    if p_supervisor_id is not null and private.rol_crm(p_supervisor_id) is distinct from 'supervisor' then
      raise exception using errcode = '22023', message = 'No es un supervisor activo';
    end if;
    -- Las claves de equipo son las de «Actividad del día»: el roster del pulso (vendedores activos visibles con su
    -- supervisor activo más cercano). El roster exige gerencia por sí mismo (gestion_diaria_pulso_autorizar).
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'analista_id', r.analista_id, 'nombre', r.nombre_completo, 'supervisor_id', r.supervisor_id)), '[]'::jsonb)
      into v_roster
    from private.gestion_diaria_pulso_roster() r
    where p_supervisor_id is null or r.supervisor_id = p_supervisor_id;
    v_alcance := case when p_supervisor_id is null then 'operacion' else 'equipo' end;
  elsif v_rol = 'supervisor' then
    -- Un supervisor solo pregunta por su equipo; otro id recibe el 42501 de la familia (no se revela si existe).
    if p_supervisor_id is not null and p_supervisor_id <> p_actor then
      raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
    end if;
    -- Su subárbol (vendedor_ids_visibles, que exige que el actor sea quien pregunta), solo vendedores con rol efectivo
    -- (equipo y perfil activos, como el roster de gerencia), todos bajo un único equipo con su id.
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'analista_id', e.perfil_id, 'nombre', p.nombre_completo, 'supervisor_id', p_actor)), '[]'::jsonb)
      into v_roster
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where private.rol_crm(e.perfil_id) = 'vendedor'
      and e.perfil_id in (select private.vendedor_ids_visibles(p_actor));
    v_alcance := 'equipo';
  else
    raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
  end if;

  -- Salud de los celulares vigentes que el actor puede ver (undécima): estado del latido, sin horas exactas.
  v_salud := private.celulares_salud_listar(p_actor);

  return (
    with roster as (
      select r.analista_id, r.nombre, r.supervisor_id
      from pg_catalog.jsonb_to_recordset(v_roster) as r(analista_id uuid, nombre text, supervisor_id uuid)
    ), salientes as (
      -- Base común: SALIENTES de los analistas del ámbito (las entrantes están bloqueadas; las personales y a no-leads
      -- no existen en la tabla). Una sola pasada acotada por recepción: una llamada de hoy no pudo recibirse antes de
      -- ayer y lo que no tiene enlace no sobrevive a la retención. Momento de la llamada (D2): ocurrio_en, salvo que
      -- falte o vaya más de 5 min por delante del servidor (reloj corrido); entonces, recibido_en.
      select e.id, e.analista_id, e.atencion, e.identificacion, e.lead_id, e.recibido_en,
             case when e.ocurrio_en is null or e.ocurrio_en > e.recibido_en + interval '5 minutes'
                  then e.recibido_en else e.ocurrio_en end as momento
      from crm.llamadas_celular_eventos e
      where e.analista_id in (select r.analista_id from roster r)
        and e.direccion = 'saliente'
        and e.recibido_en >= least(v_desde - interval '1 day', p_ahora - pg_catalog.make_interval(days => v_dias))
    ), leads_estado as materialized (
      -- Evaluar la contactabilidad una vez por lead del ámbito, no una vez por cada llamada histórica.
      select l.id, l.activo,
             (l.etapa not in ('convertido', 'descartado') and not l.no_contactar and not private.persona_vetada(l.id)) as abierto
      from crm.leads l
      where l.activo and l.id in (
        select s.lead_id from salientes s
        union
        select e.lead_id from crm.llamadas_celular_enlaces en
        join crm.actividades a on a.id = en.actividad_id and a.metadata ? 'deshecho_en'
        join crm.llamadas_celular_eventos e on e.id = en.evento_id
        where e.direccion = 'saliente' and e.analista_id in (select r.analista_id from roster r)
      )
    ), hoy as (
      -- Cohorte 5.1: identificadas, lead activo (A4), por el momento de la llamada. «Abierto y contactable» con la
      -- atención CRUDA (no la efectiva, que depende de quién mira: D4).
      select s.analista_id, s.atencion,
             l.abierto,
             coalesce(a.metadata ? 'deshecho_en', false) as deshecha
      from salientes s
      join leads_estado l on l.id = s.lead_id and l.activo
      left join crm.llamadas_celular_enlaces en on en.evento_id = s.id
      left join crm.actividades a on a.id = en.actividad_id
      where s.identificacion = 'identificado'
        and s.recibido_en >= v_desde - interval '1 day'
        and s.momento >= v_desde and s.momento < v_desde + interval '1 day'
    ), hoy_cubetas as (
      -- Seis cubetas disjuntas que suman el total; el estado se deriva de (atención, enlace, deshecho, lead), en ese orden.
      select h.analista_id, h.atencion,
             case h.atencion
               when 'registrado' then case when h.deshecha and h.abierto then 'deshechas_sin_corregir'
                                           when h.deshecha then 'cerradas_despues'
                                           else 'con_resultado' end
               when 'requiere_resultado' then case when h.abierto then 'sin_resultado' else 'cerradas_despues' end
               when 'descartado_con_motivo' then 'descartadas'
               when 'por_revisar' then 'por_revisar'
             end as cubeta
      from hoy h
    ), llamadas_hoy as (
      select c.analista_id,
             count(*)::integer as total,
             (count(*) filter (where c.cubeta = 'con_resultado'))::integer as con_resultado,
             (count(*) filter (where c.cubeta = 'deshechas_sin_corregir'))::integer as deshechas_sin_corregir,
             (count(*) filter (where c.cubeta = 'sin_resultado'))::integer as sin_resultado,
             (count(*) filter (where c.cubeta = 'cerradas_despues'))::integer as cerradas_despues,
             (count(*) filter (where c.cubeta = 'descartadas'))::integer as descartadas,
             (count(*) filter (where c.cubeta = 'por_revisar'))::integer as por_revisar,
             (count(*) filter (where c.atencion = 'requiere_devolucion'))::integer as requiere_devolucion
      from hoy_cubetas c
      group by c.analista_id
    ), resultados_hoy as (
      -- Cohorte 5.2: enlaces vigentes (actividad no deshecha) cuya ACTIVIDAD nació hoy (A2), atribuidos a quien marcó.
      -- Un enlace nunca es anterior a su actividad, así que actualizado_en >= hoy acota por índice sin perder ninguno.
      select e.analista_id,
             count(*)::integer as total,
             (count(*) filter (where en.via = 'al_colgar'))::integer as al_colgar,
             (count(*) filter (where en.via = 'pestana'))::integer as desde_pestana,
             (count(*) filter (where en.via = 'manual'))::integer as a_mano
      from crm.llamadas_celular_enlaces en
      join crm.actividades a on a.id = en.actividad_id
      join crm.llamadas_celular_eventos e on e.id = en.evento_id
      join crm.leads l on l.id = e.lead_id and l.activo
      where en.actualizado_en >= v_desde
        and a.creado_en >= v_desde and a.creado_en < v_desde + interval '1 day'
        and not (a.metadata ? 'deshecho_en')
        and e.direccion = 'saliente'
        and e.analista_id in (select r.analista_id from roster r)
      group by e.analista_id
    ), pendientes as (
      -- 5.3: foto de ahora dentro de la retención. Sin resultado = atención cruda, sin enlace, lead abierto y contactable.
      -- Por revisar = ambiguas, de la bolsa y reutilizables (con o sin lead; si lo hay, activo).
      select s.analista_id,
             (count(*) filter (where p.pendiente))::integer as total,
             (count(*) filter (where p.pendiente and s.momento >= v_desde))::integer as de_hoy,
             (count(*) filter (where p.pendiente and s.momento < v_desde))::integer as anteriores,
             min(s.momento) filter (where p.pendiente) as mas_antigua,
             (count(*) filter (where s.atencion = 'por_revisar'))::integer as por_revisar
      from salientes s
      left join leads_estado l on l.id = s.lead_id
      cross join lateral (
        select s.atencion = 'requiere_resultado' and l.activo
               and l.abierto
               and not exists (select 1 from crm.llamadas_celular_enlaces en where en.evento_id = s.id) as pendiente
      ) p
      where s.recibido_en >= p_ahora - pg_catalog.make_interval(days => v_dias)
        and s.atencion in ('requiere_resultado', 'por_revisar')
        and (s.lead_id is null or l.activo)
      group by s.analista_id
    ), deshechas as (
      -- Deshechas sin corregir, de cualquier fecha (la purga no retira lo enlazado): desde los enlaces hacia la actividad.
      select e.analista_id, count(*)::integer as n
      from crm.llamadas_celular_enlaces en
      join crm.actividades a on a.id = en.actividad_id and a.metadata ? 'deshecho_en'
      join crm.llamadas_celular_eventos e on e.id = en.evento_id
      join leads_estado l on l.id = e.lead_id and l.activo
      where e.direccion = 'saliente'
        and e.analista_id in (select r.analista_id from roster r)
        and l.abierto
      group by e.analista_id
    ), salud as (
      -- Solo lo que el contrato publica de cada celular: ni asignación, ni nombre, ni desde cuándo.
      select (c ->> 'analista_id')::uuid as analista_id, c ->> 'etiqueta' as etiqueta, c ->> 'estado_latido' as estado_latido,
             pg_catalog.jsonb_build_object(
               'etiqueta', c -> 'etiqueta', 'estado_latido', c -> 'estado_latido', 'horas_sin_latido', c -> 'horas_sin_latido',
               'reloj_desfasado', c -> 'reloj_desfasado', 'eventos_en_cola', c -> 'eventos_en_cola',
               'version_macro', c -> 'version_macro') as celular
      from pg_catalog.jsonb_array_elements(v_salud) c
    ), celulares as (
      select s.analista_id,
             pg_catalog.jsonb_agg(s.celular order by s.etiqueta) as lista,
             count(*)::integer as vigentes,
             (count(*) filter (where s.estado_latido <> 'al_dia'))::integer as sin_latido,
             bool_or(s.estado_latido = 'al_dia') as alguno_al_dia
      from salud s
      group by s.analista_id
    ), por_analista as (
      select r.analista_id, r.nombre, r.supervisor_id,
             coalesce(lh.total, 0) as lh_total, coalesce(lh.con_resultado, 0) as lh_con_resultado,
             coalesce(lh.deshechas_sin_corregir, 0) as lh_deshechas, coalesce(lh.sin_resultado, 0) as lh_sin_resultado,
             coalesce(lh.cerradas_despues, 0) as lh_cerradas, coalesce(lh.descartadas, 0) as lh_descartadas,
             coalesce(lh.por_revisar, 0) as lh_por_revisar, coalesce(lh.requiere_devolucion, 0) as lh_devolucion,
             coalesce(rh.total, 0) as rh_total, coalesce(rh.al_colgar, 0) as rh_al_colgar,
             coalesce(rh.desde_pestana, 0) as rh_pestana, coalesce(rh.a_mano, 0) as rh_manual,
             coalesce(pe.total, 0) as pe_total, coalesce(pe.de_hoy, 0) as pe_de_hoy, coalesce(pe.anteriores, 0) as pe_anteriores,
             pe.mas_antigua as pe_mas_antigua, coalesce(pe.por_revisar, 0) as pe_por_revisar,
             coalesce(d.n, 0) as de_n,
             coalesce(c.vigentes, 0) as cel_vigentes, coalesce(c.sin_latido, 0) as cel_sin_latido,
             coalesce(c.lista, '[]'::jsonb) as celulares,
             -- D1: «sin dato» = 0 llamadas Y ningún celular vigente al día. Un celular al día con 0 llamadas muestra 0.
             (coalesce(lh.total, 0) = 0 and not coalesce(c.alguno_al_dia, false)) as sin_dato
      from roster r
      left join llamadas_hoy lh on lh.analista_id = r.analista_id
      left join resultados_hoy rh on rh.analista_id = r.analista_id
      left join pendientes pe on pe.analista_id = r.analista_id
      left join deshechas d on d.analista_id = r.analista_id
      left join celulares c on c.analista_id = r.analista_id
    ), niveles as (
      -- Las mismas cifras en tres niveles (g = 0 analista, 2 equipo, 3 operación): los equipos y los totales son SUMAS
      -- de sus analistas; ningún porcentaje viaja en el jsonb (la pantalla los calcula de cada par de la misma cohorte).
      select grouping(pa.analista_id, pa.supervisor_id) as g,
             pa.analista_id, pa.supervisor_id,
             count(*)::integer as analistas,
             (count(*) filter (where pa.sin_dato))::integer as analistas_sin_dato,
             coalesce(sum(pa.cel_vigentes), 0)::integer as celulares_vigentes,
             coalesce(sum(pa.cel_sin_latido), 0)::integer as celulares_sin_latido,
             pg_catalog.jsonb_build_object(
               'llamadas_hoy', pg_catalog.jsonb_build_object(
                 'total', coalesce(sum(pa.lh_total), 0)::integer,
                 'con_resultado', coalesce(sum(pa.lh_con_resultado), 0)::integer,
                 'deshechas_sin_corregir', coalesce(sum(pa.lh_deshechas), 0)::integer,
                 'sin_resultado', coalesce(sum(pa.lh_sin_resultado), 0)::integer,
                 'cerradas_despues', coalesce(sum(pa.lh_cerradas), 0)::integer,
                 'descartadas', coalesce(sum(pa.lh_descartadas), 0)::integer,
                 'por_revisar', coalesce(sum(pa.lh_por_revisar), 0)::integer,
                 'requiere_devolucion', coalesce(sum(pa.lh_devolucion), 0)::integer),
               'resultados_hoy', pg_catalog.jsonb_build_object(
                 'total', coalesce(sum(pa.rh_total), 0)::integer,
                 'al_colgar', coalesce(sum(pa.rh_al_colgar), 0)::integer,
                 'desde_pestana', coalesce(sum(pa.rh_pestana), 0)::integer,
                 'a_mano', coalesce(sum(pa.rh_manual), 0)::integer),
               'pendientes', pg_catalog.jsonb_build_object(
                 'total', coalesce(sum(pa.pe_total), 0)::integer,
                 'de_hoy', coalesce(sum(pa.pe_de_hoy), 0)::integer,
                 'anteriores', coalesce(sum(pa.pe_anteriores), 0)::integer,
                 'mas_antigua_dias', case when min(pa.pe_mas_antigua) is null then null
                                          else pg_catalog.floor(extract(epoch from p_ahora - min(pa.pe_mas_antigua)) / 86400)::integer end,
                 'deshechas_sin_corregir', coalesce(sum(pa.de_n), 0)::integer),
               'por_revisar', coalesce(sum(pa.pe_por_revisar), 0)::integer) as cifras
      from por_analista pa
      group by grouping sets ((pa.analista_id, pa.supervisor_id), (pa.supervisor_id), ())
    )
    select pg_catalog.jsonb_build_object(
      'dia', (v_desde at time zone 'America/Lima')::date,
      'generado_en', p_ahora,
      'alcance', v_alcance,
      'rotulos', pg_catalog.jsonb_build_object(
        'llamadas_hoy', 'Llamadas de hoy (por la hora de la llamada)',
        'resultados_hoy', 'Resultados registrados hoy (de llamadas de cualquier día)',
        'pendientes', pg_catalog.format('Sin resultado ahora (hasta %s días)', v_dias)),
      'totales', (
        select n.cifras || pg_catalog.jsonb_build_object(
                 'celulares_vigentes', n.celulares_vigentes, 'celulares_sin_latido', n.celulares_sin_latido,
                 'analistas_sin_dato', n.analistas_sin_dato)
        from niveles n where n.g = 3),
      'equipos', (
        select coalesce(pg_catalog.jsonb_agg(
                 pg_catalog.jsonb_build_object(
                   'supervisor_id', n.supervisor_id, 'supervisor_nombre', coalesce(p.nombre_completo, 'Sin supervisor'),
                   'analistas', n.analistas, 'celulares_vigentes', n.celulares_vigentes,
                   'celulares_sin_latido', n.celulares_sin_latido, 'analistas_sin_dato', n.analistas_sin_dato) || n.cifras
                 order by p.nombre_completo nulls last, n.supervisor_id), '[]'::jsonb)
        from niveles n
        left join public.perfiles p on p.id = n.supervisor_id
        where n.g = 2),
      'analistas', (
        select coalesce(pg_catalog.jsonb_agg(
                 pg_catalog.jsonb_build_object(
                   'analista_id', pa.analista_id, 'nombre', pa.nombre, 'supervisor_id', pa.supervisor_id,
                   'sin_dato', pa.sin_dato, 'celulares', pa.celulares) || n.cifras
                 order by pa.nombre, pa.analista_id), '[]'::jsonb)
        from por_analista pa
        join niveles n on n.g = 0 and n.analista_id = pa.analista_id),
      -- A7: el celular del supervisor, fuera de analistas[] y sin sumar al equipo. Gerencia: nulo.
      'su_celular', case when v_rol = 'supervisor'
                         then (select coalesce(pg_catalog.jsonb_agg(s.celular order by s.etiqueta), '[]'::jsonb)
                               from salud s where s.analista_id = p_actor)
                         else null end)
  );
end;
$function$;
do $post$
begin
  if exists (select 1 from f4e_catalogo_previo b left join pg_catalog.pg_proc p on p.oid=b.oid
             where (pg_catalog.to_jsonb(p)-'prosrc') is distinct from b.atributos)
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid='private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)'::regprocedure) <> '0047b3a6edfe8dead60526e5575b72d9' then
    raise exception 'F4E_RENDIMIENTO: cuerpo o atributos inesperados';
  end if;
end $post$;
notify pgrst, 'reload schema';
commit;
$mig$;
begin
  if (
    to_regprocedure('crm.llamadas_celular_operacion_hoy_fn(uuid)') is not null
    and to_regprocedure('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261013145935 no está aplicada (o no con su forma); aplícala primero';
  end if;
  -- Huellas del cuerpo de las funciones del archivo aprobado (LF), no del texto que se inserta en el ledger.
  -- pg_proc.prosrc conserva el cuerpo literalmente. La configuración y ACL se verifican por separado.
  for v_f in select * from (values
    ('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)', '0047b3a6edfe8dead60526e5575b72d9', false, 0,
     array['p_actor','p_supervisor_id','p_ahora']::text[], null::text),
    ('crm.llamadas_celular_operacion_hoy_fn(uuid)', '952abdd141001309f08ab56e8a828698', true, 1,
     array['p_supervisor_id']::text[], 'authenticated')
  ) as f(firma, huella, definer, defaults, argumentos, rol)
  loop
    select p.* into strict v_p from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure;
    if pg_catalog.md5(v_p.prosrc) is distinct from v_f.huella
       or v_p.prolang <> (select oid from pg_catalog.pg_language where lanname = 'plpgsql')
       or v_p.prorettype <> 'jsonb'::regtype or v_p.proretset or v_p.proisstrict
       or v_p.prosecdef is distinct from v_f.definer or v_p.provolatile <> 's'
       or v_p.pronargdefaults <> v_f.defaults or v_p.proargnames is distinct from v_f.argumentos
       or v_p.proconfig is distinct from array['search_path=""']::text[]
       or (v_f.defaults = 1 and pg_catalog.pg_get_expr(v_p.proargdefaults, 0) is distinct from 'NULL::uuid') then
      raise exception 'REGISTRO: definición alterada de %', v_f.firma;
    end if;
    if v_p.proacl is null or exists (
      select 1 from pg_catalog.aclexplode(v_p.proacl) a
      where a.privilege_type = 'EXECUTE' and a.grantee <> v_p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid or a.is_grantable)
    ) or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'REGISTRO: permisos alterados de %', v_f.firma;
    end if;
  end loop;
  if exists(select 1 from supabase_migrations.schema_migrations where version='20261013145935'
            and (name is distinct from 'crm_llamadas_celular_operacion_hoy_rendimiento' or statements is distinct from array[v_sql])) then
    raise exception 'REGISTRO: versión de rendimiento con contenido distinto';
  end if;
  insert into supabase_migrations.schema_migrations(version,name,statements)
  values ('20261013145935','crm_llamadas_celular_operacion_hoy_rendimiento',array[v_sql]) on conflict(version) do nothing;
end $chk$;
commit;
select exists(select 1 from supabase_migrations.schema_migrations where version='20261013145935'
              and md5(statements[1])='31eb4cbde86a020e34b2fba6df1d9057') as veredicto_registro_20261013145935;
