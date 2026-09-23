-- Gestión Diaria F4.4. Candidato: avisos persistentes, sin activar cortes.
-- El ledger anterior conserva su contrato; las entregas del popup NO son
-- reconocimientos ni evaluaciones de desempeño. Solo acreditan su presentación.
begin;
do $preflight$ begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
  if to_regclass('crm.gestion_diaria_entregas') is not null then
    raise exception 'F4.4 ya instalada; no reinstalar';
  end if;
end $preflight$;

-- El cálculo de llamadas conserva la RLS de authenticated incluso cuando
-- lo invoca una escritura DEFINER. El rol no inicia sesión ni se concede a
-- ningún actor API; solo posee el lector sellado de esta entrega.
create role crm_gestion_diaria_lector nologin inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant authenticated to crm_gestion_diaria_lector;
grant crm_gestion_diaria_lector to postgres;
-- auth.usage y auth.uid se heredan de authenticated. En hosted, postgres no
-- tiene GRANT OPTION sobre auth; no requiere ni debe modificar ese esquema.
grant usage on schema crm, private to crm_gestion_diaria_lector;

create table crm.gestion_diaria_control_avisos (
  version integer primary key check (version > 0),
  habilitados boolean not null,
  motivo text not null check (length(btrim(motivo)) between 3 and 500),
  creado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default clock_timestamp(),
  check ((version = 1 and creado_por is null) or (version > 1 and creado_por is not null))
);
alter table crm.gestion_diaria_control_avisos enable row level security;
revoke all on crm.gestion_diaria_control_avisos from public, anon, authenticated, service_role;
create index gestion_diaria_control_autor_idx on crm.gestion_diaria_control_avisos(creado_por);
create trigger trg_inmutable before update or delete on crm.gestion_diaria_control_avisos
  for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_audit after insert on crm.gestion_diaria_control_avisos
  for each row execute function private.log_audit_crm();
insert into crm.gestion_diaria_control_avisos(version, habilitados, motivo)
values (1, true, 'Canal disponible; la política histórica conserva los cortes apagados');
grant select on crm.gestion_diaria_control_avisos to crm_gestion_diaria_lector;
create policy lectura_interna on crm.gestion_diaria_control_avisos
  for select to crm_gestion_diaria_lector using (
    private.puede_acceder_crm() and private.rol_crm(auth.uid()) = 'supervisor');

create table crm.gestion_diaria_entregas (
  id uuid primary key default gen_random_uuid(),
  perfil_id uuid not null references public.perfiles(id),
  alerta_id text not null,
  entrega integer not null check (entrega in (0, 1)),
  solicitud_id uuid not null,
  creado_en timestamptz not null default clock_timestamp(),
  unique (perfil_id, alerta_id, entrega),
  unique (perfil_id, solicitud_id)
);
alter table crm.gestion_diaria_entregas enable row level security;
revoke all on crm.gestion_diaria_entregas from public, anon, authenticated, service_role;
grant select on crm.gestion_diaria_entregas to crm_gestion_diaria_lector;
create policy lectura_interna on crm.gestion_diaria_entregas
  for select to crm_gestion_diaria_lector using (
    perfil_id = auth.uid() and private.puede_acceder_crm() and private.rol_crm(auth.uid()) = 'supervisor');
create trigger trg_inmutable before update or delete on crm.gestion_diaria_entregas
  for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_audit after insert on crm.gestion_diaria_entregas
  for each row execute function private.log_audit_crm();

alter table crm.alertas_reconocimientos add column solicitud_corte_id uuid;
create unique index alertas_corte_solicitud_idx on crm.alertas_reconocimientos(perfil_id, solicitud_corte_id)
  where solicitud_corte_id is not null;
-- Última defensa ante concurrencia, incluso en INSERT directo autorizado.
create unique index alertas_corte_aplazamiento_unico_idx on crm.alertas_reconocimientos(perfil_id, alerta_id)
  where accion = 'posponer' and starts_with(alerta_id, 'grupo:corte_');
alter table crm.alertas_reconocimientos drop constraint alertas_reconocimientos_alerta_id_check;
alter table crm.alertas_reconocimientos add constraint alertas_reconocimientos_alerta_id_check check (
  alerta_id collate "C" ~ '^grupo:(por_repartir|tarea_vencida|lead_sin_responder|sin_proxima_accion):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or alerta_id collate "C" ~ '^grupo:corte_(manana|tarde):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9]{4}-[0-9]{2}-[0-9]{2}$'
);

-- Privada, sin EXECUTE API. La única entrada pública usa reloj de servidor.
-- DEFINER con rol puente SIN BYPASSRLS para leer entregas/controles sin abrir
-- tablas a la API. Las llamadas y leads se leen con la RLS de authenticated.
create function private.gestion_diaria_avisos(p_ahora timestamptz) returns jsonb
language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_dia date := (p_ahora at time zone 'America/Lima')::date;
  v_equipo jsonb;
  v_ids uuid[];
  v_cortes jsonb;
  v_control crm.gestion_diaria_control_avisos;
  v_corte record;
  v_id text;
  v_miembros jsonb;
  v_ultimo crm.alertas_reconocimientos;
  v_pospuesto boolean;
  v_entrega integer;
  v_puede_avisar boolean;
  v_estado text;
  v_alertas jsonb := '[]';
begin
  if v_uid is null or not private.puede_acceder_crm()
    or private.rol_crm(v_uid) is distinct from 'supervisor' then
    raise exception 'Solo el supervisor autorizado consulta sus avisos' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(e)), '[]'), coalesce(array_agg(e.perfil_id), '{}'::uuid[])
    into v_equipo, v_ids from crm.equipo_visible_fn() e
    where e.activo and e.rol_crm = 'vendedor'
      and e.perfil_id in (select private.vendedor_ids_visibles(v_uid));
  v_cortes := private.gestion_diaria_cortes(v_dia, v_ids, p_ahora);
  select * into strict v_control from crm.gestion_diaria_control_avisos order by version desc limit 1;
  for v_corte in select * from (values
    ('corte_manana', 'primer_corte', 'primer_corte_en'),
    ('corte_tarde', 'segundo_corte', 'segundo_corte_en')) c(tipo, clave, hora) loop
    select coalesce(jsonb_agg(jsonb_build_object(
      'analista_id', f->>'analista_id', 'nombre', e->>'nombre_completo',
      'llamadas', f->v_corte.clave->'llamadas', 'objetivo', f->v_corte.clave->'objetivo',
      'llamadas_recuperacion', f->v_corte.clave->'llamadas_recuperacion'
    ) order by e->>'nombre_completo', f->>'analista_id'), '[]'),
      coalesce(bool_or((f->v_corte.clave->>'puede_avisar')::boolean), false)
      into v_miembros, v_puede_avisar
      from jsonb_array_elements(v_cortes->'equipo') f
      join jsonb_array_elements(v_equipo) e on e->>'perfil_id' = f->>'analista_id'
      where (f->v_corte.clave->>'aviso_pendiente')::boolean;
    if jsonb_array_length(v_miembros) = 0 then continue; end if;
    v_id := 'grupo:' || v_corte.tipo || ':' || v_uid || ':' || to_char(v_dia, 'YYYY-MM-DD');
    select * into v_ultimo from crm.alertas_reconocimientos
      where perfil_id = v_uid and alerta_id = v_id order by secuencia desc limit 1;
    select exists(select 1 from crm.alertas_reconocimientos
      where perfil_id = v_uid and alerta_id = v_id and accion = 'posponer') into v_pospuesto;
    v_entrega := case when v_pospuesto then 1 else 0 end;
    v_estado := case when v_ultimo.accion = 'reconocer' then 'reconocido'
      when v_ultimo.accion = 'posponer' and v_ultimo.hasta > p_ahora then 'pospuesto' else 'pendiente' end;
    v_alertas := v_alertas || jsonb_build_array(jsonb_build_object(
      'id', v_id, 'tipo', v_corte.tipo, 'corte_en', v_cortes->v_corte.hora,
      'fin_jornada', v_cortes->'fin_jornada', 'miembros', v_miembros,
      'estado', v_estado, 'reconocido_en', case when v_estado = 'reconocido' then v_ultimo.creado_en end,
      'pospuesto_hasta', case when v_ultimo.accion = 'posponer' then v_ultimo.hasta end,
      'puede_posponer', v_control.habilitados and v_puede_avisar and not v_pospuesto and v_estado <> 'reconocido',
      'puede_presentar', v_control.habilitados and v_puede_avisar and v_estado = 'pendiente'
        and not exists(select 1 from crm.gestion_diaria_entregas d
          where d.perfil_id = v_uid and d.alerta_id = v_id and d.entrega = v_entrega),
      'entrega', v_entrega
    ));
  end loop;
  return jsonb_build_object('version', 1, 'supervisor_id', v_uid, 'dia', v_dia,
    'generado_en', p_ahora, 'control_version', v_control.version,
    'avisos_habilitados', v_control.habilitados, 'estado_cortes', v_cortes->'estado', 'alertas', v_alertas);
end $function$;
revoke all on function private.gestion_diaria_avisos(timestamptz) from public, anon, authenticated, service_role;
grant create on schema private to crm_gestion_diaria_lector;
alter function private.gestion_diaria_avisos(timestamptz) owner to crm_gestion_diaria_lector;
revoke create on schema private from crm_gestion_diaria_lector;
grant execute on function private.gestion_diaria_avisos(timestamptz) to postgres;

create function crm.gestion_diaria_avisos_fn() returns jsonb
language sql volatile security definer set search_path = '' as $function$
  select private.gestion_diaria_avisos(clock_timestamp());
$function$;
revoke all on function crm.gestion_diaria_avisos_fn() from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_avisos_fn() to authenticated;

create function private.sellar_reconocimiento_corte(p_fila crm.alertas_reconocimientos)
returns crm.alertas_reconocimientos
language plpgsql volatile security definer set search_path = '' as $function$
declare v_ahora timestamptz; v_aviso jsonb; v_fila crm.alertas_reconocimientos := p_fila;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'supervisor' then
    raise exception 'Supervisor no autorizado' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(194204, hashtext(auth.uid()::text));
  v_ahora := clock_timestamp();
  if v_fila.alerta_id collate "C" !~ ('^grupo:corte_(manana|tarde):' || auth.uid()::text
      || ':' || to_char(v_ahora at time zone 'America/Lima', 'YYYY-MM-DD') || '$') then
    raise exception 'El corte no pertenece a tu jornada y campana' using errcode = '42501';
  end if;
  select a into v_aviso from jsonb_array_elements(private.gestion_diaria_avisos(v_ahora)->'alertas') a
    where a->>'id' = v_fila.alerta_id;
  if v_aviso is null then
    raise exception 'El corte ya no tiene pendientes; actualiza el equipo' using errcode = '22023';
  end if;
  if v_fila.accion is null or v_fila.accion not in ('reconocer', 'posponer') then
    raise exception 'Acción de corte inválida' using errcode = '22023';
  end if;
  if v_fila.accion = 'posponer' and not (v_aviso->>'puede_posponer')::boolean then
    raise exception 'Este aviso ya se pospuso o está fuera de la jornada habilitada' using errcode = '22023';
  end if;
  v_fila.perfil_id := auth.uid();
  v_fila.creado_en := v_ahora;
  v_fila.hasta := case when v_fila.accion = 'posponer' then v_ahora + interval '1 hour' end;
  v_fila.severidad := 'atencion';
  select array_agg(m->>'analista_id' order by m->>'analista_id') into v_fila.miembros
    from jsonb_array_elements(v_aviso->'miembros') m;
  return v_fila;
end $function$;
revoke all on function private.sellar_reconocimiento_corte(crm.alertas_reconocimientos)
  from public, anon, authenticated, service_role;

-- Extensión puntual del trigger publicado: la rama legacy queda íntegra.
do $extender$
declare v_def text; v_ancla text := '  -- Nadie reconoce alertas ajenas: el uuid del alerta_id ES el del actor.';
begin
  v_def := pg_get_functiondef('crm.alertas_reconocimientos_sellar()'::regprocedure);
  if (select md5(prosrc) from pg_proc where oid='crm.alertas_reconocimientos_sellar()'::regprocedure) <> '06556f83322e2a50efe4d2aac2ce26f9'
    or strpos(v_def, v_ancla) = 0 or strpos(v_def, 'sellar_reconocimiento_corte') > 0 then
    raise exception 'El trigger de reconocimientos cambió; revisar antes de extender';
  end if;
  execute replace(v_def, v_ancla, $nuevo$  if starts_with(new.alerta_id, 'grupo:corte_') then
    return private.sellar_reconocimiento_corte(new);
  end if;
  if new.solicitud_corte_id is not null then
    raise exception 'La clave de solicitud pertenece solo a los cortes' using errcode = '22023';
  end if;
$nuevo$ || v_ancla);
end $extender$;

create function crm.gestion_diaria_reconocer_corte(p_alerta_id text, p_accion text, p_solicitud_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_previo crm.alertas_reconocimientos;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'supervisor' then
    raise exception 'Supervisor no autorizado' using errcode = '42501';
  end if;
  if p_solicitud_id is null or p_alerta_id is null or p_accion is null
    or p_accion not in ('reconocer', 'posponer') then
    raise exception 'Solicitud de reconocimiento inválida' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(194204, hashtext(auth.uid()::text));
  select * into v_previo from crm.alertas_reconocimientos
    where perfil_id = auth.uid() and solicitud_corte_id = p_solicitud_id;
  if found then
    if v_previo.alerta_id <> p_alerta_id or v_previo.accion <> p_accion then
      raise exception 'La solicitud ya corresponde a otra acción' using errcode = '22023';
    end if;
  else
    if not starts_with(p_alerta_id, 'grupo:corte_') then
      raise exception 'Esta puerta solo reconoce cortes' using errcode = '22023';
    end if;
    insert into crm.alertas_reconocimientos(perfil_id, alerta_id, accion, miembros, severidad, solicitud_corte_id)
      values(auth.uid(), p_alerta_id, p_accion, array['servidor'], 'atencion', p_solicitud_id);
  end if;
  return private.gestion_diaria_avisos(clock_timestamp());
end $function$;
revoke all on function crm.gestion_diaria_reconocer_corte(text,text,uuid) from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_reconocer_corte(text,text,uuid) to authenticated;

create function crm.gestion_diaria_presentar_corte(p_alerta_id text, p_solicitud_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_aviso jsonb; v_anterior crm.gestion_diaria_entregas;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'supervisor' then
    raise exception 'Supervisor no autorizado' using errcode = '42501';
  end if;
  if p_solicitud_id is null or p_alerta_id is null then
    raise exception 'Solicitud de presentación inválida' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(194204, hashtext(auth.uid()::text));
  select a into v_aviso from jsonb_array_elements(private.gestion_diaria_avisos(clock_timestamp())->'alertas') a
    where a->>'id' = p_alerta_id;
  select * into v_anterior from crm.gestion_diaria_entregas
    where perfil_id = auth.uid() and solicitud_id = p_solicitud_id;
  if found and v_anterior.alerta_id <> p_alerta_id then
    raise exception 'La solicitud ya corresponde a otro aviso' using errcode = '22023';
  end if;
  -- Aun un reintento válido se revalida: no presenta un problema ya resuelto,
  -- reconocido, pospuesto, apagado ni pasado el cierre de la jornada.
  if v_aviso is null or v_aviso->>'estado' <> 'pendiente'
    or (not coalesce((v_aviso->>'puede_presentar')::boolean, false) and v_anterior.id is null) then
    return jsonb_build_object('version', 1, 'solicitud_id', p_solicitud_id, 'aviso', null);
  end if;
  if not exists(select 1 from crm.gestion_diaria_control_avisos where version = (
      select max(version) from crm.gestion_diaria_control_avisos) and habilitados)
    or clock_timestamp() >= (v_aviso->>'fin_jornada')::timestamptz
    or (v_anterior.id is not null and v_anterior.entrega <> (v_aviso->>'entrega')::integer) then
    return jsonb_build_object('version', 1, 'solicitud_id', p_solicitud_id, 'aviso', null);
  end if;
  if v_anterior.id is null then
    insert into crm.gestion_diaria_entregas(perfil_id, alerta_id, entrega, solicitud_id)
      values(auth.uid(), p_alerta_id, (v_aviso->>'entrega')::integer, p_solicitud_id);
  end if;
  return jsonb_build_object('version', 1, 'solicitud_id', p_solicitud_id, 'aviso', v_aviso);
end $function$;
revoke all on function crm.gestion_diaria_presentar_corte(text,uuid) from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_presentar_corte(text,uuid) to authenticated;

comment on table crm.gestion_diaria_entregas is
  'F4: entrega única del popup por supervisor, jornada/corte y reaviso; cerrar no reconoce ni resuelve. Sin escrituras API directas.';
comment on table crm.gestion_diaria_control_avisos is
  'F4: canal de avisos con control de emergencia versionado. No activa cortes ni reescribe políticas históricas.';

-- El gate detecta deriva de código, RLS, índices, triggers y privilegios.
create function private.assert_gestion_diaria_avisos() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare f record; v_tabla record; v_rol text; actual text;
begin
  if not exists(select 1 from pg_roles where rolname='crm_gestion_diaria_lector'
    and not rolcanlogin and rolinherit and not rolsuper and not rolcreatedb
    and not rolcreaterole and not rolreplication and not rolbypassrls and rolconfig is null)
    or not pg_has_role('crm_gestion_diaria_lector','authenticated','MEMBER')
    or has_schema_privilege('crm_gestion_diaria_lector','private','CREATE')
    or exists(select 1 from pg_auth_members where member='crm_gestion_diaria_lector'::regrole
      and roleid<>'authenticated'::regrole)
    or exists(select 1 from pg_auth_members where roleid='crm_gestion_diaria_lector'::regrole
      and member<>'postgres'::regrole) then
    raise exception 'F4.4: rol lector o membresías alteradas';
  end if;
  for f in select * from (values
    ('private.gestion_diaria_avisos(timestamptz)','7009218260658cfbf6ed096715d2a8d5','crm_gestion_diaria_lector',false),
    ('crm.gestion_diaria_avisos_fn()','e43dc496abf8f1d6fefd081c82af3dab','postgres',true),
    ('private.sellar_reconocimiento_corte(crm.alertas_reconocimientos)','0625cb9b9ef267d91d56d8bfac58dd5d','postgres',false),
    ('crm.gestion_diaria_reconocer_corte(text,text,uuid)','25d0eacd86a252fca11ab9a84eeb98fc','postgres',true),
    ('crm.gestion_diaria_presentar_corte(text,uuid)','4779126c16a1008b695b9d1a3574a8ea','postgres',true)
  ) firmas(firma,huella,propietario,api) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(f.firma)
      and md5(p.prosrc)=f.huella and p.proowner=to_regrole(f.propietario)
      and p.prosecdef and p.provolatile='v' and p.proconfig=array['search_path=""']
      and has_function_privilege('authenticated',p.oid,'EXECUTE')=f.api
      and not has_function_privilege('anon',p.oid,'EXECUTE')
      and not has_function_privilege('service_role',p.oid,'EXECUTE')) then
      raise exception 'F4.4: función, propietario o permisos alterados en %',f.firma;
    end if;
  end loop;
  if not exists(select 1 from pg_proc where oid='crm.alertas_reconocimientos_sellar()'::regprocedure
    and md5(prosrc)='960f97629e9e6113d3a77ea949ebae82' and prosecdef
    and proowner='postgres'::regrole and proconfig=array['search_path=""']) then
    raise exception 'F4.4: cambió el sello de reconocimientos';
  end if;
  for v_tabla in select * from (values
    ('crm.gestion_diaria_control_avisos','2ee456e6fb3f08aa531a6f87b5aaf542'),
    ('crm.gestion_diaria_entregas','9c6232150a9788f59bd25083e62b4ce5')
  ) tablas(nombre,huella) loop
    select md5(jsonb_build_object(
  'columnas',(select jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,
    a.attidentity,a.attgenerated,pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
    from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
    where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
  'restricciones',(select jsonb_agg(jsonb_build_array(k.conname,pg_get_constraintdef(k.oid),k.convalidated) order by k.conname)
    from pg_constraint k where k.conrelid=c.oid),
  'indices',(select jsonb_agg(jsonb_build_array(pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisready) order by pg_get_indexdef(i.indexrelid))
    from pg_index i where i.indrelid=c.oid),
  'politicas',(select jsonb_agg(jsonb_build_array(p.polname,p.polcmd,p.polpermissive,
    (select array_agg(r::regrole::text order by r::regrole::text) from unnest(p.polroles) r),
    pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname) from pg_policy p where p.polrelid=c.oid),
  'triggers',(select jsonb_agg(jsonb_build_array(pg_get_triggerdef(t.oid),t.tgenabled) order by t.tgname)
    from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal)
  )::text) into actual from pg_class c where c.oid=to_regclass(v_tabla.nombre)
      and c.relrowsecurity and c.relowner='postgres'::regrole;
    if actual is distinct from v_tabla.huella then
      raise exception 'F4.4: estructura, restricciones, índices, RLS o triggers alterados en %',v_tabla.nombre;
    end if;
    foreach v_rol in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(v_rol,v_tabla.nombre,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or has_any_column_privilege(v_rol,v_tabla.nombre,'SELECT,INSERT,UPDATE,REFERENCES') then
        raise exception 'F4.4: concesión API inesperada en %',v_tabla.nombre;
      end if;
    end loop;
    if not has_table_privilege('crm_gestion_diaria_lector',v_tabla.nombre,'SELECT')
      or has_table_privilege('crm_gestion_diaria_lector',v_tabla.nombre,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception 'F4.4: permisos de lector interno alterados';
    end if;
  end loop;
  if not exists(select 1 from pg_index where indexrelid=to_regclass('crm.alertas_corte_solicitud_idx')
    and indisunique and indisvalid and indisready and indrelid='crm.alertas_reconocimientos'::regclass
    and pg_get_indexdef(indexrelid,1,true)='perfil_id' and pg_get_indexdef(indexrelid,2,true)='solicitud_corte_id'
    and indnkeyatts=2 and pg_get_expr(indpred,indrelid)='(solicitud_corte_id IS NOT NULL)')
    or not exists(select 1 from pg_index where indexrelid=to_regclass('crm.alertas_corte_aplazamiento_unico_idx')
      and indisunique and indisvalid and indisready and indrelid='crm.alertas_reconocimientos'::regclass
      and pg_get_indexdef(indexrelid,1,true)='perfil_id' and pg_get_indexdef(indexrelid,2,true)='alerta_id'
      and indnkeyatts=2
      and pg_get_expr(indpred,indrelid)='((accion = ''posponer''::text) AND starts_with(alerta_id, ''grupo:corte_''::text))') then
    raise exception 'F4.4: índices de idempotencia o aplazamiento alterados';
  end if;
  return 'OK: avisos persistentes sellados, RLS del lector y entregas únicas';
end $function$;
revoke all on function private.assert_gestion_diaria_avisos() from public,anon,authenticated,service_role;

create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = '' as $function$
begin
  return 'OK: Gestion Diaria [' || private.assert_gestion_diaria_registro()
    || '] [' || private.assert_gestion_diaria_resultado()
    || '] [' || private.assert_gestion_diaria_analista()
    || '] [' || private.assert_gestion_diaria_equipo()
    || '] [' || private.assert_gestion_diaria_cortes()
    || '] [' || private.assert_gestion_diaria_avisos() || ']';
end $function$;

do $postflight$ begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;
