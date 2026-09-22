-- Gestión Diaria F4, etapa 3. Candidato: no instala ni activa por sí solo.
-- Política inicial histórica OFF; sin pop-up, aplazamiento ni puerta de escritura.
begin;

do $preflight$
begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
  if to_regclass('crm.politica_gestion_diaria') is not null then
    raise exception 'F4.3 ya existe; no reinstalar sobre una política publicada';
  end if;
end;
$preflight$;

create table crm.politica_gestion_diaria (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique check (version > 0),
  version_anterior_id uuid references crm.politica_gestion_diaria(id),
  vigente_desde timestamptz not null,
  creado_en timestamptz not null default statement_timestamp(),
  creado_por uuid default auth.uid() references public.perfiles(id),
  motivo text not null check (length(btrim(motivo)) between 3 and 500),
  cortes_activos boolean not null default false,
  corte_1_hora time not null default '11:30',
  corte_1_minimo integer not null default 3 check (corte_1_minimo between 1 and 500),
  corte_2_hora time not null default '16:00',
  corte_2_incremento_pct numeric not null default 150 check (corte_2_incremento_pct between 0 and 1000),
  corte_2_piso integer not null default 8 check (corte_2_piso between 1 and 500),
  corte_2_techo integer not null default 30 check (corte_2_techo between corte_2_piso and 500),
  sabado_minimo integer not null default 3 check (sabado_minimo between 1 and 500),
  bien_min_pct numeric not null default 45 check (bien_min_pct > 0 and bien_min_pct <= 100),
  atencion_min_pct numeric not null default 25 check (atencion_min_pct >= 0 and atencion_min_pct < bien_min_pct),
  minimo_llamadas_utiles integer not null default 5 check (minimo_llamadas_utiles between 1 and 500),
  tasa_baja_diferencia_pp numeric check (tasa_baja_diferencia_pp between 0 and 100),
  check (corte_1_hora > time '09:00' and corte_1_hora < time '13:00'
    and corte_2_hora > corte_1_hora and corte_2_hora < time '18:00'),
  check ((version = 1 and version_anterior_id is null and creado_por is null and vigente_desde = '-infinity'::timestamptz and not cortes_activos)
    or (version > 1 and version_anterior_id is not null and creado_por is not null and isfinite(vigente_desde)
      and vigente_desde = ((vigente_desde at time zone 'America/Lima')::date::timestamp at time zone 'America/Lima')))
);
alter table crm.politica_gestion_diaria enable row level security;
revoke all on table crm.politica_gestion_diaria from public, anon, authenticated, service_role;
-- Parámetros públicos al CRM; motivo y atribución sólo para el futuro editor
-- gerencial autorizado. No SELECT de tabla ni columnas administrativas.
grant select (id, version, version_anterior_id, vigente_desde, cortes_activos,
  corte_1_hora, corte_1_minimo, corte_2_hora, corte_2_incremento_pct,
  corte_2_piso, corte_2_techo, sabado_minimo, bien_min_pct, atencion_min_pct,
  minimo_llamadas_utiles, tasa_baja_diferencia_pp)
  on crm.politica_gestion_diaria to authenticated;
create policy politica_gestion_diaria_select on crm.politica_gestion_diaria
  for select to authenticated using (
    (select private.puede_acceder_crm()) and (
      (select private.es_lector_global()) or (select private.rol_crm((select auth.uid()))) is not null));
create index politica_gestion_diaria_vigencia_idx on crm.politica_gestion_diaria(vigente_desde desc, version desc);

create trigger trg_config_inmutable before update or delete on crm.politica_gestion_diaria
  for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_audit_politica_gestion_diaria after insert on crm.politica_gestion_diaria
  for each row execute function private.log_audit_crm();

insert into crm.politica_gestion_diaria(version, vigente_desde, motivo, creado_por)
values (1, '-infinity', 'Umbrales históricos; cortes desactivados hasta completar F4', null);

-- Incluso una escritura administrativa posterior debe conservar la cadena y
-- comenzar una jornada FUTURA. La puerta gerencial con expected_version es etapa 5.
create function private.trg_politica_gestion_diaria_insertar() returns trigger
language plpgsql security invoker set search_path = ''
as $function$
declare v_ultima crm.politica_gestion_diaria;
begin
  -- Serializar publicaciones; la lectura siguiente debe ver la última versión.
  perform pg_advisory_xact_lock(194203, 43);
  select * into strict v_ultima from crm.politica_gestion_diaria order by version desc limit 1;
  if new.version is distinct from v_ultima.version + 1 or new.version_anterior_id is distinct from v_ultima.id then
    raise exception 'La política cambió; vuelve a cargar su última versión' using errcode = '40001';
  end if;
  if new.vigente_desde < v_ultima.vigente_desde then
    raise exception 'No adelantes la última revisión programada; corrige esa jornada o una posterior' using errcode = '22023';
  end if;
  if new.vigente_desde < (((statement_timestamp() at time zone 'America/Lima')::date + 1)::timestamp at time zone 'America/Lima') then
    raise exception 'La vigencia debe comenzar en una jornada futura de Lima' using errcode = '22023';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_politica_gestion_diaria_insertar() from public, anon, authenticated, service_role;
create trigger trg_validar_politica_gestion_diaria before insert on crm.politica_gestion_diaria
  for each row execute function private.trg_politica_gestion_diaria_insertar();

create function private.politica_gestion_diaria_vigente(p_instante timestamptz)
returns table(id uuid, version integer, version_anterior_id uuid, vigente_desde timestamptz,
  cortes_activos boolean, corte_1_hora time, corte_1_minimo integer, corte_2_hora time,
  corte_2_incremento_pct numeric, corte_2_piso integer, corte_2_techo integer,
  sabado_minimo integer, bien_min_pct numeric, atencion_min_pct numeric,
  minimo_llamadas_utiles integer, tasa_baja_diferencia_pp numeric)
language plpgsql stable security invoker set search_path = ''
as $function$
begin
  if p_instante is null or not isfinite(p_instante) then
    raise exception 'Instante de política inválido' using errcode = '22023';
  end if;
  return query select p.id, p.version, p.version_anterior_id, p.vigente_desde,
    p.cortes_activos, p.corte_1_hora, p.corte_1_minimo, p.corte_2_hora,
    p.corte_2_incremento_pct, p.corte_2_piso, p.corte_2_techo, p.sabado_minimo,
    p.bien_min_pct, p.atencion_min_pct, p.minimo_llamadas_utiles, p.tasa_baja_diferencia_pp
    from crm.politica_gestion_diaria p where p.vigente_desde <= p_instante
    order by p.vigente_desde desc, p.version desc limit 1;
  if not found then
    raise exception 'No hay política de Gestión Diaria accesible' using errcode = '42501';
  end if;
end;
$function$;
revoke all on function private.politica_gestion_diaria_vigente(timestamptz) from public, anon, authenticated, service_role;
grant execute on function private.politica_gestion_diaria_vigente(timestamptz) to authenticated;

create function private.gestion_diaria_umbrales(p_instante timestamptz) returns jsonb
language sql stable security invoker set search_path = ''
as $function$
  select jsonb_build_object('version', 1, 'politica_version', p.version,
    'bien_min_pct', p.bien_min_pct, 'atencion_min_pct', p.atencion_min_pct,
    'minimo_llamadas_utiles', p.minimo_llamadas_utiles)
  from private.politica_gestion_diaria_vigente(p_instante) p;
$function$;
revoke all on function private.gestion_diaria_umbrales(timestamptz) from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_umbrales(timestamptz) to authenticated;

create or replace function private.gestion_diaria_umbrales() returns jsonb
language sql stable security invoker set search_path = ''
as $function$
  select private.gestion_diaria_umbrales(
    (statement_timestamp() at time zone 'America/Lima')::date::timestamp at time zone 'America/Lima');
$function$;

-- Composición del contador CANÓNICO; sin contar actividades por una segunda vía.
-- Sólo el núcleo autorizado pasa el roster. El helper vuelve a filtrar identidades
-- y usa RLS. p_ahora no se expone por PostgREST ni permite escribir resultados.
create function private.gestion_diaria_cortes(p_dia date, p_analistas uuid[], p_ahora timestamptz) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_ini timestamptz;
  v_p record;
  v_dow integer;
  v_inicio timestamptz;
  v_fin timestamptz;
  v_corte1 timestamptz;
  v_corte2 timestamptz;
  v_limite_recuperacion timestamptz;
  v_minimo integer;
  v_ids uuid[];
  v_filas jsonb;
  v_puede_avisar boolean;
begin
  if v_uid is null or not private.puede_acceder_crm()
    or not (coalesce(private.rol_crm(v_uid) in ('supervisor', 'gerencia'), false) or private.es_lector_global()) then
    raise exception 'No autorizado para consultar cortes' using errcode = '42501';
  end if;
  if p_dia is null or not isfinite(p_dia) or p_ahora is null or not isfinite(p_ahora)
    or p_dia > (p_ahora at time zone 'America/Lima')::date
    or (p_ahora at time zone 'America/Lima')::date - p_dia > 365 then
    raise exception 'Día de corte inválido' using errcode = '22023';
  end if;
  v_ini := p_dia::timestamp at time zone 'America/Lima';
  select * into strict v_p from private.politica_gestion_diaria_vigente(v_ini);
  v_dow := extract(isodow from p_dia);
  if not v_p.cortes_activos or v_dow = 7 then
    return jsonb_build_object('version', 1, 'politica_version', v_p.version,
      'estado', case when not v_p.cortes_activos then 'desactivados' else 'no_laborable' end,
      'cartera_referencia', 'consulta_actual', 'inicio_jornada', null, 'fin_jornada', null,
      'primer_corte_en', null, 'segundo_corte_en', null, 'equipo', '[]'::jsonb);
  end if;
  select coalesce(array_agg(e.perfil_id), '{}'::uuid[]) into v_ids
    from crm.equipo_visible_fn() e
    where e.activo and e.rol_crm = 'vendedor' and e.perfil_id = any(p_analistas);
  v_inicio := (p_dia + time '09:00') at time zone 'America/Lima';
  v_fin := (p_dia + case when v_dow = 6 then time '13:00' else time '18:00' end) at time zone 'America/Lima';
  v_corte1 := (p_dia + v_p.corte_1_hora) at time zone 'America/Lima';
  v_corte2 := case when v_dow < 6 then (p_dia + v_p.corte_2_hora) at time zone 'America/Lima' end;
  v_limite_recuperacion := coalesce(v_corte2, v_fin);
  v_minimo := case when v_dow = 6 then v_p.sabado_minimo else v_p.corte_1_minimo end;
  v_puede_avisar := p_dia = (p_ahora at time zone 'America/Lima')::date
    and p_ahora >= v_inicio and p_ahora < v_fin;

  with roster as (
    select unnest(v_ids) as analista_id
  ), primero as materialized (
    select ll.* from private.gestion_diaria_llamadas(v_ini, v_corte1,
      case when p_ahora >= v_corte1 then v_ids else '{}'::uuid[] end) ll
  ), segundo as materialized (
    select ll.* from private.gestion_diaria_llamadas(v_ini, coalesce(v_corte2, v_ini),
      case when p_ahora >= v_corte2 then v_ids else '{}'::uuid[] end) ll
  ), recuperacion as materialized (
    select ll.* from private.gestion_diaria_llamadas(v_ini, least(p_ahora, v_limite_recuperacion),
      case when p_ahora >= v_corte1 then v_ids else '{}'::uuid[] end) ll
  ), base as (
    select r.analista_id,
      exists(select 1 from crm.leads l where l.vendedor_id = r.analista_id and l.activo
        and l.etapa not in ('convertido', 'descartado')) as cartera_abierta,
      a.llamadas as base_1130, b.llamadas as al_segundo, c.llamadas as para_recuperacion,
      case when a.llamadas is not null then least(v_p.corte_2_techo,
        greatest(v_p.corte_2_piso, ceil(a.llamadas::numeric * (1 + v_p.corte_2_incremento_pct / 100))))::integer end as objetivo_segundo
    from roster r left join primero a on a.vendedor_id = r.analista_id
      left join segundo b on b.vendedor_id = r.analista_id
      left join recuperacion c on c.vendedor_id = r.analista_id
  ), estados as (
    select b.*,
      case when not cartera_abierta then 'sin_cartera'
        when p_ahora < v_corte1 then 'pendiente'
        when base_1130 >= v_minimo then 'cumplido'
        when para_recuperacion >= v_minimo then 'recuperado' else 'incumplido' end as estado1,
      case when not cartera_abierta then 'sin_cartera'
        when p_ahora < v_corte2 then 'pendiente'
        when al_segundo >= objetivo_segundo then 'cumplido' else 'incumplido' end as estado2
    from base b
  )
  select coalesce(jsonb_agg(jsonb_build_object('analista_id', e.analista_id,
    'cartera_abierta', e.cartera_abierta,
    'primer_corte', jsonb_build_object('estado', e.estado1, 'llamadas', e.base_1130,
      'objetivo', v_minimo, 'base', e.base_1130, 'llamadas_recuperacion', e.para_recuperacion,
      'aviso_pendiente', e.estado1 = 'incumplido', 'puede_avisar', e.estado1 = 'incumplido' and v_puede_avisar),
    'segundo_corte', case when v_corte2 is not null then jsonb_build_object(
      'estado', e.estado2, 'llamadas', e.al_segundo, 'objetivo', e.objetivo_segundo,
      'base', e.base_1130, 'llamadas_recuperacion', null,
      'aviso_pendiente', e.estado2 = 'incumplido', 'puede_avisar', e.estado2 = 'incumplido' and v_puede_avisar) end
    ) order by e.analista_id), '[]'::jsonb) into v_filas from estados e;
  return jsonb_build_object('version', 1, 'politica_version', v_p.version, 'estado', 'activo',
    'cartera_referencia', 'consulta_actual', 'inicio_jornada', v_inicio, 'fin_jornada', v_fin,
    'primer_corte_en', v_corte1, 'segundo_corte_en', v_corte2, 'equipo', v_filas);
end;
$function$;
revoke all on function private.gestion_diaria_cortes(date, uuid[], timestamptz) from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_cortes(date, uuid[], timestamptz) to authenticated;

-- Cambios mínimos sobre cuerpos previamente sellados. Si deriva cualquier
-- ancla, abortar; no reemplazar definiciones completas de migraciones antiguas.
do $integrar$
declare v_def text; v_antes text; v_despues text; v_firma text; v_sello record;
begin
  foreach v_firma in array array[
    'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',
    'private.gestion_diaria_equipo_core(date,uuid)'] loop
    v_def := pg_get_functiondef(v_firma::regprocedure);
    v_antes := 'private.gestion_diaria_umbrales()';
    v_despues := case when v_firma like '%analista_core%' then 'private.gestion_diaria_umbrales(p_ini)'
      else 'private.gestion_diaria_umbrales(v_ini)' end;
    if (length(v_def) - length(replace(v_def, v_antes, ''))) / length(v_antes) <> 1 then
      raise exception 'F4.3: ancla de umbrales cambió en %', v_firma;
    end if;
    v_def := replace(v_def, v_antes, v_despues);
    if v_firma like '%equipo_core%' then
      v_antes := '''equipo'', v_equipo, ''resumen'', v_resumen);';
      v_despues := '''equipo'', v_equipo, ''resumen'', v_resumen, ''cortes'', private.gestion_diaria_cortes(v_dia, v_ids, v_ahora));';
      if (length(v_def) - length(replace(v_def, v_antes, ''))) / length(v_antes) <> 1 then
        raise exception 'F4.3: ancla de respuesta de equipo cambió';
      end if;
      v_def := replace(v_def, v_antes, v_despues);
    end if;
    execute v_def;
  end loop;

  -- Reseñar sólo las tres huellas afectadas. El resto del gate se conserva.
  for v_sello in select * from (values
    ('private.assert_gestion_diaria_analista()', 'b08d96d051c210e24b1fb74484670b93', '4dd5313e606b57485cd105b125f412b7'),
    ('private.assert_gestion_diaria_analista()', '6ab633af9f5356f3fa11cf309ff4b25c', '151860fa342b98d4f2ce9ed7054e390b'),
    ('private.assert_gestion_diaria_equipo()', '70d6b23ee4d9f1f397ccfbae8f1dee5a', '17b39a376af0f940f029937a6fa98186')
  ) as sellos(firma, anterior, nuevo) loop
    v_def := pg_get_functiondef(v_sello.firma::regprocedure);
    if (length(v_def) - length(replace(v_def, v_sello.anterior, ''))) / length(v_sello.anterior) <> 1 then
      raise exception 'F4.3: ancla de huella cambió en %', v_sello.firma;
    end if;
    execute replace(v_def, v_sello.anterior, v_sello.nuevo);
  end loop;
end;
$integrar$;

create function private.assert_gestion_diaria_cortes() returns text
language plpgsql stable security definer set search_path = ''
as $function$
declare v_firma text; v_src text; v_hash text;
begin
  if not exists (select 1 from pg_class c where c.oid = 'crm.politica_gestion_diaria'::regclass
    and c.relrowsecurity and c.relowner = 'postgres'::regrole)
    or has_table_privilege('authenticated', 'crm.politica_gestion_diaria', 'SELECT')
    or exists (select 1 from pg_attribute a where a.attrelid = 'crm.politica_gestion_diaria'::regclass
      and a.attnum > 0 and not a.attisdropped and has_column_privilege('authenticated', a.attrelid, a.attnum, 'SELECT')
        is distinct from (a.attname = any(array['id','version','version_anterior_id','vigente_desde','cortes_activos',
          'corte_1_hora','corte_1_minimo','corte_2_hora','corte_2_incremento_pct','corte_2_piso',
          'corte_2_techo','sabado_minimo','bien_min_pct','atencion_min_pct','minimo_llamadas_utiles','tasa_baja_diferencia_pp'])))
    or has_table_privilege('authenticated', 'crm.politica_gestion_diaria', 'INSERT,UPDATE,DELETE,TRUNCATE')
    or has_any_column_privilege('authenticated', 'crm.politica_gestion_diaria', 'INSERT,UPDATE,REFERENCES')
    or has_table_privilege('anon', 'crm.politica_gestion_diaria', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or has_any_column_privilege('anon', 'crm.politica_gestion_diaria', 'SELECT,INSERT,UPDATE,REFERENCES')
    or has_table_privilege('service_role', 'crm.politica_gestion_diaria', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or has_any_column_privilege('service_role', 'crm.politica_gestion_diaria', 'SELECT,INSERT,UPDATE,REFERENCES') then
    raise exception 'F4.3: permisos o RLS de política alterados';
  end if;
  if not exists (select 1 from crm.politica_gestion_diaria where version = 1
      and vigente_desde = '-infinity'::timestamptz and not cortes_activos
      and bien_min_pct = 45 and atencion_min_pct = 25 and minimo_llamadas_utiles = 5
      and tasa_baja_diferencia_pp is null) then
    raise exception 'F4.3: cambió la política histórica';
  end if;
  for v_firma, v_hash in select * from (values
    ('private.politica_gestion_diaria_vigente(timestamptz)', '1a49136776ac123a4fef8b680414ac75'),
    ('private.gestion_diaria_umbrales(timestamptz)', 'a08ee5147e62c99be9502f5d2476efd9'),
    ('private.gestion_diaria_cortes(date,uuid[],timestamptz)', '9dac719158c8934ea1954bc5077a660c')
  ) as firmas(firma, huella) loop
    select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE');
    if not found or md5(v_src) <> v_hash then
      raise exception 'F4.3: cuerpo o permisos alterados en %', v_firma;
    end if;
  end loop;
  if not exists (select 1 from pg_policy p where p.polrelid = 'crm.politica_gestion_diaria'::regclass
    and p.polname = 'politica_gestion_diaria_select' and p.polcmd = 'r'
    and p.polroles = array['authenticated'::regrole::oid]
    and p.polpermissive and md5(pg_get_expr(p.polqual, p.polrelid)) = '9cb3f24c6b5d274b6c91bc36b182af8c')
    or exists(select 1 from pg_policy p where p.polrelid = 'crm.politica_gestion_diaria'::regclass
      and p.polname <> 'politica_gestion_diaria_select') then
    raise exception 'F4.3: política RLS inesperada';
  end if;
  if not exists (select 1 from pg_proc p
    where p.oid = 'private.trg_politica_gestion_diaria_insertar()'::regprocedure
    and not p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole
    and p.proconfig = array['search_path=""'] and md5(p.prosrc) = 'f7025422613ea84abd9ec3cac3ab140e'
    and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not has_function_privilege('anon', p.oid, 'EXECUTE')
    and not has_function_privilege('service_role', p.oid, 'EXECUTE')) then
    raise exception 'F4.3: cambió la guarda de publicación futura';
  end if;
  if exists (select 1 from (values
      ('trg_config_inmutable', 'private.trg_config_versionada_inmutable()'),
      ('trg_audit_politica_gestion_diaria', 'private.log_audit_crm()'),
      ('trg_validar_politica_gestion_diaria', 'private.trg_politica_gestion_diaria_insertar()')
    ) as esperados(nombre, firma) where not exists (
      select 1 from pg_trigger t where t.tgrelid = 'crm.politica_gestion_diaria'::regclass
      and t.tgname = esperados.nombre and t.tgfoid = to_regprocedure(esperados.firma) and t.tgenabled = 'O')) then
    raise exception 'F4.3: falta protección de historial o auditoría';
  end if;
  return 'OK: cortes Lima, política versionada OFF, RLS sin escrituras API';
end;
$function$;
revoke all on function private.assert_gestion_diaria_cortes() from public, anon, authenticated, service_role;

create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = ''
as $function$
begin
  return 'OK: Gestion Diaria [' || private.assert_gestion_diaria_registro()
    || '] [' || private.assert_gestion_diaria_resultado()
    || '] [' || private.assert_gestion_diaria_analista()
    || '] [' || private.assert_gestion_diaria_equipo()
    || '] [' || private.assert_gestion_diaria_cortes() || ']';
end;
$function$;

comment on table crm.politica_gestion_diaria is
  'F4: política inmutable al inicio del día Lima; v1 histórica OFF. Sin escritura API hasta etapa 5.';
comment on function crm.gestion_diaria_equipo_fn(date, uuid) is
  'Gestión Diaria F4: foto autorizada y cortes aditivos; cartera y jerarquía actuales, política al inicio del día. Sin reconocimiento ni escrituras.';

do $postflight$
begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
