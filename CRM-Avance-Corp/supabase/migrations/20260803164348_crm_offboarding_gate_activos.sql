-- P04 · Offboarding seguro del CRM
--
-- Invariante de actor:
--   * miembro CRM = public.perfiles.activo AND crm.equipo.activo;
--   * lector global = perfil global activo sin ninguna membresía CRM;
--   * apagar CUALQUIERA de los dos flags corta REST/RLS/RPC/ICS del CRM.
--
-- Invariante de destino:
--   un lead nuevo solo puede quedar bajo responsabilidad de un perfil y una
--   membresía CRM activos. Los miembros históricos permanecen visibles como
--   objetos para que Gerencia reasigne su cartera; el gate se aplica al actor.

-- ---------------------------------------------------------------------------
-- 1. Helpers canónicos de actor y destino
-- ---------------------------------------------------------------------------

create or replace function private.rol_crm(p_perfil_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('vendedor', 'supervisor', 'gerencia', 'coordinador');
$$;

comment on function private.rol_crm(uuid) is
  'Rol CRM efectivo: solo existe para una membresía reconocida con ambos flags activos.';

-- El conjunto visible conserva miembros inactivos COMO OBJETOS para historia y
-- reasignación, pero el actor se resuelve exclusivamente mediante rol_crm().
create or replace function private.vendedor_ids_visibles(p_perfil_id uuid)
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

-- Un rol global solo es fallback cuando NO existe membresía CRM. Si hay fila,
-- su rol CRM manda; si además está inactiva, la revocación sigue prevaleciendo.
create or replace function private.es_lector_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo = true
      and p.rol in ('directorio', 'admin', 'superadmin')
  )
  and not exists (
    select 1
    from crm.equipo e
    where e.perfil_id = (select auth.uid())
  );
$$;

create or replace function private.puede_acceder_crm()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.rol_crm((select auth.uid())) is not null
      or private.es_lector_global();
$$;

comment on function private.puede_acceder_crm() is
  'Gate único del actor humano para toda superficie CRM.';

create or replace function private.es_destino_crm_activo(
  p_perfil_id uuid,
  p_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = p_perfil_id
      and e.activo = true
      and p.activo = true
      and e.rol_crm = any (p_roles)
  );
$$;

comment on function private.es_destino_crm_activo(uuid, text[]) is
  'Valida que un destinatario de responsabilidad comercial tenga ambos flags activos y uno de los roles permitidos.';

-- Los helpers usados desde policies necesitan EXECUTE de authenticated, pero
-- no deben heredar el grant implícito a PUBLIC. El helper de destino es solo
-- para triggers SECURITY DEFINER.
revoke all on function private.rol_crm(uuid) from public, anon;
revoke all on function private.vendedor_ids_visibles(uuid) from public, anon;
revoke all on function private.puede_ver_cartera(uuid, uuid) from public, anon;
revoke all on function private.es_lector_global() from public, anon;
revoke all on function private.puede_acceder_crm() from public, anon;
revoke all on function private.es_destino_crm_activo(uuid, text[]) from public, anon, authenticated;

grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.vendedor_ids_visibles(uuid) to authenticated;
grant execute on function private.puede_ver_cartera(uuid, uuid) to authenticated;
grant execute on function private.es_lector_global() to authenticated;
grant execute on function private.puede_acceder_crm() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Gate RLS RESTRICTIVE sobre todas las tablas CRM presentes
-- ---------------------------------------------------------------------------
--
-- RESTRICTIVE compone por AND con las policies de ámbito existentes. No amplía
-- ningún permiso y tampoco cambia el bypass intencional de service_role.
do $$
declare
  v_tabla record;
begin
  for v_tabla in
    select c.relname, c.relrowsecurity
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm'
      and c.relkind in ('r', 'p')
    order by c.relname
  loop
    if not v_tabla.relrowsecurity then
      raise exception 'P04 requiere RLS activo en crm.%', v_tabla.relname;
    end if;

    execute format(
      'drop policy if exists crm_actor_activo_gate on crm.%I',
      v_tabla.relname
    );
    execute format(
      'create policy crm_actor_activo_gate on crm.%I as restrictive for all to authenticated using ((select private.puede_acceder_crm())) with check ((select private.puede_acceder_crm()))',
      v_tabla.relname
    );
  end loop;
end;
$$;

-- Corrige además el lint auth_rls_initplan de P-047 sin cambiar su semántica.
drop policy if exists enfriamiento_insert on crm.enfriamiento_politica;
create policy enfriamiento_insert on crm.enfriamiento_politica
  for insert to authenticated
  with check (private.rol_crm((select auth.uid())) = 'gerencia');

drop policy if exists enfriamiento_update on crm.enfriamiento_politica;
create policy enfriamiento_update on crm.enfriamiento_politica
  for update to authenticated
  using (private.rol_crm((select auth.uid())) = 'gerencia')
  with check (private.rol_crm((select auth.uid())) = 'gerencia');

-- ---------------------------------------------------------------------------
-- 3. RPC SECURITY DEFINER que no heredaban el gate central
-- ---------------------------------------------------------------------------

-- La app no puede distinguir una fila de equipo ausente de una inactiva
-- leyendo la tabla: RLS oculta ambas. Esta RPC resuelve esa diferencia dentro
-- de la frontera y evita que una revocación explícita caiga al fallback global.
create or replace function crm.mi_acceso_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_nombre text;
  v_rol_portal text;
  v_perfil_activo boolean;
  v_tiene_equipo boolean;
  v_rol_crm text;
  v_equipo_activo boolean;
begin
  if v_actor is null then
    raise insufficient_privilege using message = 'Sesion CRM requerida';
  end if;

  select
    p.nombre_completo,
    p.rol,
    p.activo,
    e.perfil_id is not null,
    e.rol_crm,
    e.activo
  into
    v_nombre,
    v_rol_portal,
    v_perfil_activo,
    v_tiene_equipo,
    v_rol_crm,
    v_equipo_activo
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where p.id = v_actor;

  if not found then
    return pg_catalog.jsonb_build_object(
      'estado', 'no_enrolado',
      'perfil_id', v_actor
    );
  end if;

  if v_perfil_activo is not true
     or (
       v_tiene_equipo
       and (
         v_equipo_activo is not true
         or v_rol_crm is null
         or v_rol_crm not in ('vendedor', 'supervisor', 'gerencia', 'coordinador')
       )
     ) then
    return pg_catalog.jsonb_build_object(
      'estado', 'revocado',
      'perfil_id', v_actor
    );
  end if;

  if v_tiene_equipo then
    return pg_catalog.jsonb_build_object(
      'estado', 'miembro',
      'perfil_id', v_actor,
      'rol_crm', v_rol_crm,
      'rol_portal', v_rol_portal,
      'nombre_completo', v_nombre
    );
  end if;

  if v_rol_portal in ('directorio', 'admin', 'superadmin') then
    return pg_catalog.jsonb_build_object(
      'estado', 'global',
      'perfil_id', v_actor,
      'rol_crm', 'directorio',
      'rol_portal', v_rol_portal,
      'nombre_completo', v_nombre
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'estado', 'no_enrolado',
    'perfil_id', v_actor
  );
end;
$$;

comment on function crm.mi_acceso_fn() is
  'Resuelve el acceso propio sin confundir membresía CRM inactiva con ausencia de membresía.';

revoke all on function crm.mi_acceso_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.mi_acceso_fn()
  to authenticated;

-- Objeto as-built de producción, ahora versionado: la rama propia solo se
-- evalúa después del gate canónico; los miembros inactivos siguen apareciendo
-- como objetos cuando el actor autorizado los necesita para reasignar historia.
create or replace function crm.equipo_visible_fn()
returns table (
  perfil_id uuid,
  nombre_completo text,
  rol_crm text,
  supervisor_id uuid,
  activo boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select e.perfil_id, p.nombre_completo, e.rol_crm, e.supervisor_id, e.activo
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where private.puede_acceder_crm()
    and (
      (e.perfil_id = (select auth.uid()) and e.activo = true)
      or e.perfil_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or private.es_lector_global()
    );
$$;

revoke all on function crm.equipo_visible_fn() from public, anon;
grant execute on function crm.equipo_visible_fn() to authenticated;

-- Separa la lógica de negocio P-047 de la frontera de autorización. El cuerpo
-- se copia verbatim de P-047c dentro de private en vez de renombrar la función:
-- así la migración es reejecutable aun si Supabase registra otro timestamp.
create or replace function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text;
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
begin
  v_tel := private.normalizar_telefono(p_telefono);

  if v_tel is null or length(v_tel) = 0 then
    return jsonb_build_object('estado', 'error', 'detalle', 'telefono_invalido');
  end if;

  -- a) no_contactar: terminal, sin datos adicionales
  if exists (
    select 1 from crm.leads l
    where l.no_contactar = true
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  ) then
    return jsonb_build_object('estado', 'no_contactar');
  end if;

  -- b) ya es cliente del portal (perfiles.telefono no está normalizado: normalizar ambos lados)
  select per.id, asesor.nombre_completo as asesor_nombre
    into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  -- c) lead vivo: tomado (con dueño) o en_bolsa (sin dueño)
  select l.tenencia_desde, l.vendedor_id, l.asignado_supervisor_id,
         coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
    into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.activo = true
    and l.etapa not in ('convertido','descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return jsonb_build_object('estado', 'en_bolsa');
    end if;
    return jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde
    );
  end if;

  -- d) enfriamiento: último descarte aún dentro del plazo de su motivo
  select l.motivo_descarte, l.descartado_en,
         pd.nombre_completo as descartado_por_nombre
    into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en + make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > now() then
      return jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;
  end if;

  -- e) libre
  return jsonb_build_object('estado', 'libre');
end;
$$;

revoke all on function private.verificar_disponibilidad_lead_impl(text, text)
  from public, anon, authenticated;

create or replace function crm.verificar_disponibilidad_lead(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol text := private.rol_crm((select auth.uid()));
begin
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using
      errcode = '42501',
      message = 'Acceso CRM revocado';
  end if;

  return private.verificar_disponibilidad_lead_impl(p_telefono, p_dni);
end;
$$;

comment on function crm.verificar_disponibilidad_lead(text, text) is
  'P-047 con gate P04. Estados y reglas de negocio intactos; ejecutable solo por vendedor, supervisor o gerencia plenamente activos.';

revoke all on function crm.verificar_disponibilidad_lead(text, text)
  from public, anon;
grant execute on function crm.verificar_disponibilidad_lead(text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Destinatarios: ningún lead nuevo para una cuenta parcialmente inactiva
-- ---------------------------------------------------------------------------

create or replace function private.trg_leads_guard_tenencia()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog'
as $$
declare
  v_rol_actor text;
  v_entra_terminal boolean;
begin
  if new.vendedor_id is not null and new.asignado_supervisor_id is not null then
    raise exception 'Un lead no puede tener analista y bandeja al mismo tiempo';
  end if;

  -- Solo un miembro plenamente activo puede recibir responsabilidad nueva.
  if new.vendedor_id is not null
     and (
       tg_op = 'INSERT'
       or new.vendedor_id is distinct from old.vendedor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.vendedor_id,
       array['vendedor', 'supervisor']::text[]
     ) then
    raise exception 'El analista destino no existe, no esta activo o no puede recibir leads';
  end if;

  -- Una bandeja pertenece exclusivamente a un supervisor plenamente activo.
  if new.asignado_supervisor_id is not null
     and (
       tg_op = 'INSERT'
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.asignado_supervisor_id,
       array['supervisor']::text[]
     ) then
    raise exception 'La bandeja destino no pertenece a un supervisor activo';
  end if;

  -- Un usuario CRM no gerencial no puede liberar un lead a la cola global.
  if new.vendedor_id is null
     and new.asignado_supervisor_id is null
     and (
       tg_op = 'INSERT'
       or old.vendedor_id is not null
       or old.asignado_supervisor_id is not null
     )
     and auth.uid() is not null then
    v_rol_actor := private.rol_crm(auth.uid());
    if v_rol_actor is distinct from 'gerencia' then
      raise exception 'Solo Gerencia puede dejar un lead en la cola global';
    end if;
  end if;

  if tg_op = 'INSERT' then
    new.creado_en := statement_timestamp();
    new.actualizado_en := new.creado_en;
    new.ciclo_actual := 1;
    return new;
  end if;

  new.ciclo_actual := old.ciclo_actual;

  if old.etapa = 'convertido' and new.etapa is distinct from old.etapa then
    raise exception 'Un lead convertido no se puede reabrir';
  end if;

  if old.etapa = 'descartado' and new.etapa is distinct from old.etapa then
    if new.etapa <> 'nuevo' then
      raise exception 'Un lead descartado solo se puede reabrir en etapa nuevo';
    end if;
    new.ciclo_actual := old.ciclo_actual + 1;
  end if;

  v_entra_terminal := old.etapa not in ('convertido', 'descartado')
    and new.etapa in ('convertido', 'descartado');

  if v_entra_terminal
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Asigna al responsable antes de cerrar el lead';
  end if;

  if v_entra_terminal and old.activo = false then
    raise exception 'Reactiva el lead antes de cerrarlo';
  end if;

  if v_entra_terminal and old.activo = true and new.activo = false then
    raise exception 'Cierra o desactiva el lead en operaciones separadas';
  end if;

  if old.etapa <> 'convertido' and new.etapa = 'convertido'
     and old.vendedor_id is null then
    raise exception 'Asigna un analista antes de convertir el lead';
  end if;

  if old.activo = true and new.activo = false
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Reasigna o desactiva el lead en operaciones separadas';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. ICS: invalidación irreversible del token + lectura atómica para la Edge
-- ---------------------------------------------------------------------------

create or replace function private.trg_rotar_agenda_ics_offboarding()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update crm.agenda_ics
  set token = pg_catalog.gen_random_uuid(),
      rotado_en = pg_catalog.clock_timestamp()
  where perfil_id = new.perfil_id;

  return new;
end;
$$;

comment on function private.trg_rotar_agenda_ics_offboarding() is
  'Invalida el bearer token ICS al apagar la membresía CRM; una reactivación no revive el enlace antiguo.';

revoke all on function private.trg_rotar_agenda_ics_offboarding()
  from public, anon, authenticated;

drop trigger if exists trg_equipo_rotar_agenda_ics_offboarding on crm.equipo;
create trigger trg_equipo_rotar_agenda_ics_offboarding
after update of activo on crm.equipo
for each row
when (old.activo is true and new.activo is not true)
execute function private.trg_rotar_agenda_ics_offboarding();

create or replace function crm.agenda_ics_feed_fn(
  p_token uuid,
  p_desde timestamptz
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with miembro as materialized (
    select a.perfil_id
    from crm.agenda_ics a
    join crm.equipo e on e.perfil_id = a.perfil_id and e.activo = true
    join public.perfiles p on p.id = a.perfil_id and p.activo = true
    where a.token = p_token
  ),
  filas as (
    select t.id, t.tipo, t.titulo, t.nota, t.vence_en, t.duracion_min
    from crm.tareas t
    join miembro m on m.perfil_id = t.vendedor_id
    where t.estado = 'pendiente'
      and t.activo = true
      and t.vence_en >= p_desde
    order by t.vence_en
    limit 500
  )
  select pg_catalog.jsonb_build_object(
    'autorizado', exists (select 1 from miembro),
    'tareas', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', f.id,
            'tipo', f.tipo,
            'titulo', f.titulo,
            'nota', f.nota,
            'vence_en', f.vence_en,
            'duracion_min', f.duracion_min
          )
          order by f.vence_en
        )
        from filas f
      ),
      '[]'::jsonb
    )
  );
$$;

comment on function crm.agenda_ics_feed_fn(uuid, timestamptz) is
  'Feed atómico para la Edge ICS: token vigente + perfil activo + membresía CRM activa. Solo service_role.';

revoke all on function crm.agenda_ics_feed_fn(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function crm.agenda_ics_feed_fn(uuid, timestamptz)
  to service_role;
