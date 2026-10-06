-- Banco REDUCIDO y sintético para probar 20261001145242_crm_llamadas_celular_datos.sql (F2-b) sin
-- red ni credenciales. Lo monta supabase/scripts/test-llamadas-celular-local.mjs sobre un
-- PostgreSQL 16/17 desechable. Molde: supabase/tests/sla-nucleo/base.sql.
--
-- COPIAS REALES (cuerpo literal de la migración que se cita; si esa función cambia en producción,
-- esta copia se actualiza):
--   private.enmascarar_claves, private.log_audit_sin_secretos, private.tablas_sin_rastro y sus
--   listas (20260829235000) · private.log_audit_crm (20260829233000) · private.normalizar_telefono
--   (20260709000001) · private.canonizar_contacto (20260826182000) · private.sla_gestion_permitida
--   (20260907025220) · private.rol_crm y private.es_lector_global (20260828210351) ·
--   private.vendedor_ids_visibles (20260803164348, con su defensa: solo para quien llama) ·
--   private.idem_hash (20260903205000) · CHECK actividades_resultado_llamada_forma (20260920005000).
-- DOBLES DECLARADOS: auth.uid (lee request.jwt.claim.sub), public.log_audit_change y private.llamada_registrar_v4
-- (el núcleo sellado de la encuesta v4, que la v5 de F4-a compone; ver su comentario abajo).
-- COLUMNAS REDUCIDAS: public.perfiles, public.audit_log, crm.equipo, crm.leads, crm.actividades.
--
-- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create schema crm;
create schema private;
create schema extensions;
create extension btree_gist with schema extensions;
create extension pgcrypto with schema extensions;
grant usage on schema auth, crm, private to anon, authenticated, service_role;

-- ── identidad (doble) ──────────────────────────────────────────────────────────────────────
create function auth.uid() returns uuid language sql stable as $$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

-- ── tablas reducidas ───────────────────────────────────────────────────────────────────────
create table public.perfiles (
  id uuid primary key,
  nombre_completo text,
  telefono text,
  rol text not null default 'vendedor',
  activo boolean not null default true
);
create table public.audit_log (
  id bigint generated always as identity primary key,
  tabla text not null,
  operacion text not null,
  fila_id uuid,
  usuario_id uuid references public.perfiles(id),
  data_antes jsonb,
  data_despues jsonb,
  ts timestamptz not null default now()
);
create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id) on delete cascade,
  rol_crm text not null check (rol_crm in ('vendedor', 'supervisor', 'gerencia', 'coordinador')),
  supervisor_id uuid references crm.equipo(perfil_id) on delete set null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create table crm.leads (
  id uuid primary key default gen_random_uuid(),
  nombre_completo text not null,
  telefono text not null,
  telefono_alternativo text,
  etapa text not null default 'nuevo'
    check (etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada', 'convertido', 'descartado')),
  activo boolean not null default true,
  no_contactar boolean not null default false,
  vetada_en_banco boolean not null default false,
  vendedor_id uuid references crm.equipo(perfil_id) on delete set null,
  asignado_supervisor_id uuid references crm.equipo(perfil_id) on delete set null,
  -- Descarte (20260723120000 y 20260724203052): lo leen los candidatos «reutilizables» de la quinta.
  motivo_descarte text,
  descartado_en timestamptz,
  descartado_por uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
-- Copia real reducida de crm.enfriamiento_politica (20260801212050, con 'base_cargada' de 20261004160034): la espera
-- de un descartado antes de ser reutilizable. Sin auditoría en el banco (declarada exenta abajo).
-- Doble DECLARADO del veto por persona (la matriz completa usa la función real de identidad F2.b).
create function private.persona_vetada(p_lead uuid) returns boolean language sql stable set search_path = '' as $$
  select coalesce((select vetada_en_banco from crm.leads where id = p_lead), false)
$$;
revoke all on function private.persona_vetada(uuid) from public, anon, authenticated, service_role;
create table crm.enfriamiento_politica (
  motivo text primary key,
  dias integer not null check (dias >= 0)
);
insert into crm.enfriamiento_politica (motivo, dias) values
  ('sin_interes', 30), ('sin_fondos', 90), ('competencia', 180), ('no_responde', 15), ('otro', 20),
  ('pide_credito', 0), ('datos_invalidos', 0), ('base_cargada', 30);
create table crm.actividades (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id) on delete cascade,
  tipo text not null check (tipo in (
    'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
    'whatsapp_recibido', 'reunion_realizada', 'nota', 'cambio_etapa',
    'reasignacion', 'conversion')),
  detalle text,
  metadata jsonb not null default '{}'::jsonb,
  creado_por uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default now()
);
-- Copia real (20260920005000): la forma del resultado de llamada.
alter table crm.actividades add constraint actividades_resultado_llamada_forma check (
  coalesce(metadata->>'evento', '') <> 'resultado_llamada'
  or (
    metadata->>'resultado' in (
      'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
      'numero_errado', 'no_es_la_persona', 'pide_otro_producto')
    and (metadata->>'submotivo' is null or metadata->>'submotivo' in (
      'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir',
      'prestamo', 'credito', 'otro'))
  )
);

-- ── auditoría (copias reales) ──────────────────────────────────────────────────────────────
create table private.auditoria_exenciones (
  tabla        text        primary key,
  razon        text        not null,
  declarada_en timestamptz not null default pg_catalog.now()
);
create table private.auditoria_condicionada (
  tabla        text        primary key,
  razon        text        not null,
  declarada_en timestamptz not null default pg_catalog.now()
);
insert into private.auditoria_exenciones (tabla, razon) values
  ('crm.enfriamiento_politica', 'Banco reducido: copia sin su auditoría real; solo la leen los candidatos de la quinta.');

create function private.enmascarar_claves(p_fila jsonb, p_claves text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_fila is null then null else (
    select pg_catalog.jsonb_object_agg(
      k,
      case
        when k = any(p_claves) and pg_catalog.jsonb_typeof(v) = 'null' then v
        -- Sin huella: un md5 determinista, aunque truncado, permite confirmar
        -- candidatos y correlacionar dos eventos del mismo secreto.
        when k = any(p_claves) then '"***"'::jsonb
        else v
      end
    )
    from pg_catalog.jsonb_each(p_fila) as e(k, v)
  ) end;
$$;

create function private.log_audit_sin_secretos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secretos text[];
  v_fila uuid;
  v_actor uuid;
begin
  if tg_nargs = 0 then
    raise exception 'log_audit_sin_secretos exige las columnas a enmascarar como argumentos del trigger (tabla %.%)',
      tg_table_schema, tg_table_name;
  end if;
  v_secretos := tg_argv::text[];

  -- Ruido fuera: el portal reescribe la suscripción entera en cada carga del
  -- panel; si lo único que cambia es el reloj, no hay nada que auditar.
  if tg_op = 'UPDATE'
     and (pg_catalog.to_jsonb(old) - 'actualizado_en')
       = (pg_catalog.to_jsonb(new) - 'actualizado_en') then
    return new;
  end if;

  begin
    v_fila := coalesce(
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
    );
  exception when invalid_text_representation then
    v_fila := null;
  end;

  select p.id into v_actor
  from public.perfiles p where p.id = (select auth.uid());

  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    v_actor,
    case when tg_op in ('UPDATE','DELETE')
      then private.enmascarar_claves(pg_catalog.to_jsonb(old), v_secretos) end,
    case when tg_op in ('INSERT','UPDATE')
      then private.enmascarar_claves(pg_catalog.to_jsonb(new), v_secretos) end
  );

  return coalesce(new, old);
end;
$$;

create function private.log_audit_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila uuid;
  v_actor uuid;
begin
  begin
    v_fila := coalesce(
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
    );
  exception when invalid_text_representation then
    v_fila := null;
  end;

  select p.id into v_actor
  from public.perfiles p where p.id = (select auth.uid());

  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    v_actor,
    case when tg_op in ('UPDATE','DELETE') then pg_catalog.to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then pg_catalog.to_jsonb(new) end
  );

  return coalesce(new, old);
end;
$$;

-- Doble: solo existe porque tablas_sin_rastro() la nombra por OID.
create function public.log_audit_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  return coalesce(new, old);
end;
$$;

create function private.tablas_sin_rastro()
returns table (tabla text)
language sql
stable
security invoker
set search_path = ''
as $$
  select n.nspname || '.' || c.relname
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  -- Universo completo: tablas normales y particionadas (padres E hijas: el
  -- trigger del padre se CLONA en cada hija), foráneas y materializadas.
  -- Permanentes y UNLOGGED (una tabla sin WAL sigue guardando datos de negocio).
  where c.relkind in ('r', 'p', 'f', 'm')
    and c.relpersistence in ('p', 'u')
    and n.nspname in ('crm', 'public')
    and not exists (
      select 1 from private.auditoria_exenciones e
      where e.tabla = n.nspname || '.' || c.relname)
    and coalesce((
      select pg_catalog.bit_or(t.tgtype)
      from pg_catalog.pg_trigger t
      join pg_catalog.pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = c.oid
        and not t.tgisinternal
        -- Activo DE VERDAD: 'D' es apagado y 'R' solo dispara en réplica.
        and t.tgenabled in ('O', 'A')
        and (t.tgtype & 1) = 1     -- FOR EACH ROW
        and (t.tgtype & 2) = 0     -- AFTER, no BEFORE
        and (t.tgtype & 64) = 0    -- no INSTEAD OF
        -- Sin `UPDATE OF` parcial: dispara por estar la columna en el SET, no
        -- por cambiar, y deja fuera las columnas que no lista.
        and t.tgattr = ''::pg_catalog.int2vector
        -- Un `WHEN` puede anularlo entero: solo cuenta si está declarado.
        and (t.tgqual is null or exists (
              select 1 from private.auditoria_condicionada cc
              where cc.tabla = n.nspname || '.' || c.relname))
        -- Por OID, no por nombre: una función señuelo llamada igual en otro
        -- esquema pasaba la comprobación anterior.
        and t.tgfoid in ('private.log_audit_crm()'::regprocedure,
                         'public.log_audit_change()'::regprocedure,
                         'private.log_audit_sin_secretos()'::regprocedure)
        -- Y el auditor tiene que seguir siendo lo que dice ser: DEFINER con
        -- search_path fijo (no se exige vacío: log_audit_change vive con
        -- 'public, pg_temp' desde siempre y audita bien).
        and p.prosecdef
        and p.proconfig is not null
    ), 0) & 28 <> 28               -- 4 INSERT | 8 DELETE | 16 UPDATE
  order by 1;
$$;

-- ── teléfono (copias reales) ───────────────────────────────────────────────────────────────
create function private.normalizar_telefono(p text)
returns text
language sql immutable
as $$
  select case
    when p is null or btrim(p) = '' then p
    when length(regexp_replace(p, '[^0-9]', '', 'g')) = 9
      then '+51' || regexp_replace(p, '[^0-9]', '', 'g')
    when regexp_replace(p, '[^0-9]', '', 'g') ~ '^51[0-9]{9}$'
      then '+' || regexp_replace(p, '[^0-9]', '', 'g')
    else '+' || regexp_replace(p, '[^0-9]', '', 'g')
  end;
$$;

create function private.canonizar_contacto(p text)
returns table (e164 text, clase text, movil boolean)
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_bruto text := pg_catalog.btrim(coalesce(p, ''));
  v_digitos text;
  v_internacional boolean;
  v_sin_salida text;
  v_nacional text;
  v_declara_peru boolean;
  v_n text;
  v_sin_cero text;
begin
  if v_bruto = '' then return; end if;
  if pg_catalog.strpos(v_bruto, '@') > 0 then return; end if;

  v_digitos := pg_catalog.regexp_replace(v_bruto, '[^0-9]', '', 'g');
  if v_digitos = '' then return; end if;

  v_internacional := pg_catalog.left(v_bruto, 1) = '+'
                     or pg_catalog.left(v_digitos, 2) = '00';
  v_sin_salida := pg_catalog.regexp_replace(v_digitos, '^00', '');

  v_nacional := case when pg_catalog.left(v_sin_salida, 2) = '51'
                     then pg_catalog.substr(v_sin_salida, 3)
                     else v_sin_salida end;
  v_declara_peru := pg_catalog.left(v_sin_salida, 2) = '51'
                    and pg_catalog.length(v_nacional) >= 8;

  if v_declara_peru or not v_internacional then
    v_n := case when v_declara_peru then v_nacional else v_sin_salida end;

    if v_n ~ '^9[0-9]{8}$' then
      return query select '+51' || v_n, 'celular_pe'::text, true;
      return;
    end if;

    v_sin_cero := case when pg_catalog.left(v_n, 1) = '0'
                       then pg_catalog.substr(v_n, 2) else v_n end;
    if (v_declara_peru or pg_catalog.left(v_n, 1) = '0')
       and v_sin_cero ~ '^[1-8][0-9]{7}$' then
      return query select '+51' || v_sin_cero, 'fijo_pe'::text, false;
      return;
    end if;

    if v_declara_peru or not v_internacional then return; end if;
  end if;

  if pg_catalog.length(v_sin_salida) between 8 and 15
     and v_sin_salida ~ '^[1-9][0-9]*$' then
    return query select '+' || v_sin_salida, 'internacional'::text, true;
  end if;
  return;
end;
$function$;

-- ── idempotencia (copia real) ──────────────────────────────────────────────────────────────
create function private.idem_hash(p_payload jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_payload::text, 'utf8')), 'hex')
$$;

-- ── ámbito (copias reales) ─────────────────────────────────────────────────────────────────
create function private.rol_crm(p_perfil_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo is true and p.activo is true
    and e.rol_crm in (
      'vendedor','supervisor','gerencia','coordinador','directorio'
    )
    and (
      (p.rol = 'directorio' and e.rol_crm = 'directorio')
      or (p.rol is distinct from 'directorio' and e.rol_crm <> 'directorio')
    )
    and (p.rol is distinct from 'superadmin' or e.rol_crm = 'gerencia');
$function$;

create function private.es_lector_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  with actor as materialized (
    select (select auth.uid()) as uid
  )
  select coalesce(private.rol_crm(a.uid) = 'directorio', false)
    or exists (
      select 1
      from public.perfiles p
      where p.id = a.uid
        and p.activo is true
        and p.rol = 'directorio'
        and not exists (
          select 1 from crm.equipo e where e.perfil_id = p.id
        )
    )
  from actor a;
$function$;

create function private.vendedor_ids_visibles(p_perfil_id uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol text;
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return; -- defensa en profundidad: no enumerar equipos ajenos
  end if;

  v_rol := private.rol_crm(p_perfil_id);

  if v_rol is null then
    return;
  elsif v_rol = 'gerencia' then
    return query select e.perfil_id from crm.equipo e; -- incluye históricos
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select e.perfil_id
        from crm.equipo e
        where e.perfil_id = p_perfil_id
        union -- corta ciclos accidentales A↔B
        select e.perfil_id
        from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select s.perfil_id from subarbol s;
  elsif v_rol = 'vendedor' then
    return next p_perfil_id;
  else
    return; -- coordinador/rol futuro: deny-by-default
  end if;
end;
$$;
create function private.sla_gestion_permitida(p_actor uuid,p_lead uuid) returns boolean
language sql stable security invoker set search_path='' as $function$
  select p_actor is not null and exists (
    select 1 from crm.leads l
    where l.id=p_lead and l.activo
      and private.rol_crm(p_actor) in ('vendedor','supervisor','gerencia')
      and (private.rol_crm(p_actor)='gerencia' or l.vendedor_id=p_actor
        or (private.rol_crm(p_actor)='supervisor'
          and (l.vendedor_id in (select private.vendedor_ids_visibles(p_actor))
            or (l.vendedor_id is null and l.asignado_supervisor_id in
              (select private.vendedor_ids_visibles(p_actor))))))
  );
$function$;

-- ── encuesta v4 (DOBLE) ─────────────────────────────────────────────────────────────────────
-- private.llamada_registrar_v4 real (20260921153654) compone el motor SLA entero (registrar_actividad_v2, recibos,
-- tareas, descarte), que este banco no tiene. El doble conserva solo lo que la v5 de F4-a necesita: el ámbito
-- (42501), el lead cerrado (22023), el candado del lead FOR UPDATE, la actividad con id = operación y su metadata
-- de resultado, el replay por operación (23505 si cambia el resultado) y la forma de la respuesta. La composición
-- real la prueba el gate test-rls.mjs con el esquema de producción.
create function private.llamada_registrar_v4(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text,
  p_submotivo text, p_detalle text, p_siguiente jsonb, p_tarea_id uuid, p_descartar boolean, p_no_insista boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meta jsonb;
begin
  if private.sla_gestion_permitida(p_actor, p_lead_id) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
  end if;
  perform 1 from crm.leads l where l.id = p_lead_id for update;
  select a.metadata into v_meta from crm.actividades a where a.id = p_operacion_id;
  if found then
    if v_meta ->> 'resultado' is distinct from p_resultado then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'comando', 'registrar_llamada',
      'actividad_id', p_operacion_id, 'resultado', p_resultado, 'replay', true);
  end if;
  if (select l.etapa from crm.leads l where l.id = p_lead_id) in ('convertido', 'descartado') then
    raise exception 'El lead esta cerrado' using errcode = '22023';
  end if;
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id,
          case when p_resultado = 'no_contesto' then 'llamada_no_contestada' else 'llamada_realizada' end, p_detalle,
          pg_catalog.jsonb_build_object('evento', 'resultado_llamada', 'resultado', p_resultado), p_actor);
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'comando', 'registrar_llamada',
    'actividad_id', p_operacion_id, 'resultado', p_resultado, 'replay', false);
end;
$$;
revoke all on function private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)
  from public, anon, authenticated, service_role;

-- ── siembra sintética (sin datos reales) ───────────────────────────────────────────────────
-- Equipo: sup1 (b1) con a1 y a2; sup2 (b2) con a3; a9 dado de baja; g1 gerencia.
insert into public.perfiles (id, nombre_completo, rol, activo) values
  ('00000000-0000-0000-0000-0000000000a1', 'Analista Uno', 'analista', true),
  ('00000000-0000-0000-0000-0000000000a2', 'Analista Dos', 'analista', true),
  ('00000000-0000-0000-0000-0000000000a3', 'Analista Tres', 'analista', true),
  ('00000000-0000-0000-0000-0000000000a9', 'Analista de Baja', 'analista', true),
  ('00000000-0000-0000-0000-0000000000b1', 'Supervisor Uno', 'comercial', true),
  ('00000000-0000-0000-0000-0000000000b2', 'Supervisor Dos', 'comercial', true),
  ('00000000-0000-0000-0000-0000000000f1', 'Gerencia Uno', 'admin', true);
insert into crm.equipo (perfil_id, rol_crm, creado_en) values
  ('00000000-0000-0000-0000-0000000000b1', 'supervisor', now() - interval '5 days'),
  ('00000000-0000-0000-0000-0000000000b2', 'supervisor', now() - interval '5 days'),
  ('00000000-0000-0000-0000-0000000000f1', 'gerencia', now() - interval '5 days');
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_en) values
  ('00000000-0000-0000-0000-0000000000a1', 'vendedor', '00000000-0000-0000-0000-0000000000b1', true, now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000000a2', 'vendedor', '00000000-0000-0000-0000-0000000000b1', true, now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000000a3', 'vendedor', '00000000-0000-0000-0000-0000000000b2', true, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000a9', 'vendedor', '00000000-0000-0000-0000-0000000000b1', false, now() - interval '4 days');
-- Leads: c1 y c2 son los dos más antiguos (los usa el oráculo de F2-b).
insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, etapa, no_contactar, vendedor_id, creado_en) values
  ('00000000-0000-0000-0000-0000000000c1', 'Lead Sintético Uno', '+51900000001', null, 'nuevo', false, '00000000-0000-0000-0000-0000000000a1', now() - interval '9 days'),
  ('00000000-0000-0000-0000-0000000000c2', 'Lead Sintético Dos', '+51900000002', null, 'nuevo', false, '00000000-0000-0000-0000-0000000000a1', now() - interval '8 days'),
  ('00000000-0000-0000-0000-0000000000c3', 'Lead de Analista Dos', '+51900000003', null, 'contactado', false, '00000000-0000-0000-0000-0000000000a2', now() - interval '7 days'),
  ('00000000-0000-0000-0000-0000000000c4', 'Lead No Contactar', '+51900000004', null, 'contactado', true, '00000000-0000-0000-0000-0000000000a1', now() - interval '6 days'),
  ('00000000-0000-0000-0000-0000000000c5', 'Lead Convertido', '+51900000005', null, 'convertido', false, '00000000-0000-0000-0000-0000000000a1', now() - interval '5 days'),
  ('00000000-0000-0000-0000-0000000000c6', 'Lead Ambiguo A', '+51900000006', null, 'nuevo', false, '00000000-0000-0000-0000-0000000000a1', now() - interval '4 days'),
  ('00000000-0000-0000-0000-0000000000c7', 'Lead Ambiguo B', '+51900000007', '+51900000006', 'nuevo', false, '00000000-0000-0000-0000-0000000000a2', now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000000c8', 'Lead de Otro Equipo', '+51900000008', null, 'nuevo', false, '00000000-0000-0000-0000-0000000000a3', now() - interval '2 days');
