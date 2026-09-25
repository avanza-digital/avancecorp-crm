-- Propuesta de reversa F5: ensayar primero; NO aplicada en producción.
-- Restaurar antes el frontend verificado sin F5. Ejecutar por migración nueva
-- y aprobación exacta; jamás borrar historial ni modificar la migración original.
begin;
select private.assert_gestion_diaria_pulso();
CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[])
 RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with vendedores as (
    select distinct v.id from unnest(p_vendedor_ids) as v(id)
  ),
  ll as (
    select a.creado_por as vendedor_id, a.id, a.lead_id, a.tipo, a.creado_en,
           coalesce(a.metadata->>'resultado', 'sin_resultado') as resultado,
           (coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona')) as util,
           extract(hour from (a.creado_en at time zone 'America/Lima'))::integer as hora
    from crm.actividades a
    where a.creado_por in (select v.id from vendedores v)
      and a.tipo in ('llamada_realizada', 'llamada_no_contestada')
      and a.creado_en >= p_ini
      and a.creado_en <  p_fin
  ),
  agg as (
    select l.vendedor_id,
           cardinality(array_agg(l.id)) as llamadas,
           -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
           -- 100 % aunque una fila histórica llevara un resultado incoherente
           -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
           coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
           coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
           cardinality(array_agg(distinct l.lead_id)) as leads_tocados,
           min(l.creado_en) as primera_llamada_en,
           max(l.creado_en) as ultima_llamada_en
    from ll l
    group by l.vendedor_id
  ),
  por_resultado as (
    select r.vendedor_id, jsonb_object_agg(r.resultado, r.n) as por_resultado
    from (
      select l.vendedor_id, l.resultado, cardinality(array_agg(l.id)) as n
      from ll l
      group by l.vendedor_id, l.resultado
    ) r
    group by r.vendedor_id
  ),
  por_hora as (
    select h.vendedor_id,
           jsonb_agg(jsonb_build_object('hora', h.hora, 'llamadas', h.n, 'contestadas', h.c) order by h.hora) as por_hora
    from (
      select l.vendedor_id, l.hora, cardinality(array_agg(l.id)) as n,
             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as c
      from ll l
      group by l.vendedor_id, l.hora
    ) h
    group by h.vendedor_id
  ),
  citas as (
    -- Cita agendada = tarea de cita CREADA en la ventana por el analista (la
    -- misma definición que metricas_agenda_fn). Las reprogramadas crean otra
    -- tarea y cuentan igual que allí.
    select t.vendedor_id, cardinality(array_agg(t.id)) as citas_agendadas
    from crm.tareas t
    where t.vendedor_id in (select v.id from vendedores v)
      and t.tipo = 'reunion'
      and t.creado_en >= p_ini
      and t.creado_en <  p_fin
    group by t.vendedor_id
  )
  select v.id,
         coalesce(a.llamadas, 0),
         coalesce(a.contestadas, 0),
         coalesce(a.utiles, 0),
         coalesce(a.leads_tocados, 0),
         coalesce(c.citas_agendadas, 0),
         a.primera_llamada_en,
         a.ultima_llamada_en,
         coalesce(r.por_resultado, '{}'::jsonb),
         coalesce(h.por_hora, '[]'::jsonb)
  from vendedores v
  left join agg a on a.vendedor_id = v.id
  left join por_resultado r on r.vendedor_id = v.id
  left join por_hora h on h.vendedor_id = v.id
  left join citas c on c.vendedor_id = v.id
  order by v.id;
$function$;
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_analista()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_firma text;
  v_md5 text;
  v_id oid;
begin
  -- 1. Puerta y núcleos: INVOKER, estables, search_path vacío, owner postgres,
  --    EXECUTE exactamente para authenticated (la cadena corre como el actor).
  foreach v_firma in array array[
    'crm.gestion_diaria_analista_fn(date,uuid)',
    'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',
    'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',
    'private.gestion_diaria_umbrales()'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and not p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 's'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato del dia del analista alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL del dia del analista alterada: %', v_firma;
    end if;
    -- Ningún contador crudo en los cuerpos propios (trinquete del censo analítico).
    if exists (select 1 from pg_proc p where p.oid = v_id
               and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')) then
      raise exception 'Una funcion del dia del analista cuenta a crudo: %', v_firma;
    end if;
  end loop;

  -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).
  for v_firma, v_md5 in select * from (values
    ('crm.gestion_diaria_analista_fn(date,uuid)',                                                          'ba3d0502ae4bf0d010677562d47634a5'),
    ('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',    '4dd5313e606b57485cd105b125f412b7'),
    ('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',                                    '45e6e7a82c54b2f15110b828ba70761d'),
    ('private.gestion_diaria_umbrales()',                                                                   '151860fa342b98d4f2ce9ed7054e390b'),
    -- El roster ES la autorización para mirar el día de otro: si alguien lo
    -- reescribe, este gate se pone en rojo y hay que re-sellar a conciencia
    -- (md5 medido en producción el 20/09/2026).
    ('crm.equipo_visible_fn()',                                                                             '200162f4519586a6c68d8ccf0cf591f7')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'El cuerpo de % cambio: re-sellar el dia del analista de Gestion Diaria (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;

  -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,
  --    search_path vacío, ejecutable por authenticated. (Su cuerpo no se sella
  --    aquí: pertenece al mundo SLA; el front valida el contrato de la página.)
  v_id := to_regprocedure('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)');
  if v_id is null or not exists (
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'crm.cola_accion_v2_fn perdio su forma o su EXECUTE';
  end if;

  -- 4. La perilla del abandono: fila única bajo RLS, legible por el actor.
  -- La perilla, sellada como las policies de F1: huella de la expresión y el
  -- conjunto de permisivas de lectura EXACTO (una permisiva nueva la abriría a
  -- quien no debe). Huella medida en producción el 20/09/2026.
  if to_regclass('crm.politica_abandono') is null
     or not (select relrowsecurity from pg_class where oid = 'crm.politica_abandono'::regclass)
     or not has_column_privilege('authenticated', 'crm.politica_abandono', 'dias_abandono', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.politica_abandono', 'singleton', 'SELECT') then
    raise exception 'crm.politica_abandono perdio su forma (RLS o SELECT de singleton/dias_abandono)';
  end if;
  if (select md5(pg_get_expr(pol.polqual, pol.polrelid)) from pg_policy pol
       where pol.polrelid = 'crm.politica_abandono'::regclass and pol.polname = 'politica_abandono_select')
     is distinct from '97d4f815a6e61ba941d22c4c4d47298d' then
    raise exception 'politica_abandono_select cambio desde la auditoria: re-auditar quien lee la perilla del abandono';
  end if;
  if (select array_agg(pol.polname::text order by pol.polname) from pg_policy pol
       where pol.polrelid = 'crm.politica_abandono'::regclass and pol.polpermissive and pol.polcmd in ('r', '*'))
     is distinct from array['politica_abandono_select']::text[] then
    raise exception 'crm.politica_abandono tiene otras permisivas de lectura: re-auditar quien ve la perilla';
  end if;

  -- 5. La cadena invoker: tareas bajo RLS con su policy de lectura, y las
  --    columnas de leads que los núcleos leen y que llevan ACL propia.
  if not (select relrowsecurity from pg_class where oid = 'crm.tareas'::regclass)
     or not exists (select 1 from pg_policy where polrelid = 'crm.tareas'::regclass and polname = 'tareas_select' and polcmd = 'r')
     or not has_table_privilege('authenticated', 'crm.tareas', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'tenencia_desde', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'sla_global_iniciado_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'descartado_en', 'SELECT')
     or not has_function_privilege('authenticated', 'crm.equipo_visible_fn()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.puede_acceder_crm()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.rol_crm(uuid)', 'EXECUTE') then
    raise exception 'La cadena invoker del dia del analista perdio un permiso (tareas, leads.tenencia_desde/sla_global_iniciado_en/descartado_en, equipo_visible_fn, ayudantes)';
  end if;
  -- tareas_select sellada por huella, por conjunto de permisivas y con la
  -- restrictiva del actor activo: UNA sola fuente, la base de las tareas por
  -- cursor (20260919235100). Constantes copiadas podrían divergir; llamándola no.
  perform private.assert_tareas_pendientes_base();

  return 'OK: dia del analista — puerta y nucleos INVOKER (EXECUTE solo authenticated) con su md5, sin contadores crudos, cola v2 y politica_abandono en su forma, cadena invoker con sus permisos, tareas_select sellada por la base de las tareas por cursor';
end;
$function$;

drop function crm.gestion_diaria_pulso_fn(date) restrict;
drop function crm.gestion_diaria_habitos_fn(date,integer) restrict;
drop function private.assert_gestion_diaria_pulso() restrict;
drop function private.gestion_diaria_habitos_jornada(date,uuid[],timestamptz) restrict;
drop function private.gestion_diaria_pulso_dia(date) restrict;
drop function private.gestion_diaria_pulso_metricas(jsonb,integer) restrict;
drop function private.gestion_diaria_fechas_activas(date,date) restrict;
drop function private.gestion_diaria_pulso_autores(timestamptz,timestamptz) restrict;
drop function private.gestion_diaria_pulso_roster() restrict;
drop function private.gestion_diaria_pulso_autorizar() restrict;
drop function private.gestion_diaria_gestiones_eventos(timestamptz,timestamptz) restrict;
drop function private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[]) restrict;
select private.assert_gestion_diaria_analista();
select private.assert_gestion_diaria_equipo();
select private.assert_gestion_diaria_cortes();
select private.assert_analitica_leads_citas();
notify pgrst,'reload schema';
commit;
