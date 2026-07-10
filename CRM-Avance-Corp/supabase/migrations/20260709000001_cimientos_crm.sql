-- ============================================================================
-- F0 — CIMIENTOS DEL CRM AVANCE CORP (P-055) · 2026-07-09
-- Esquema `crm` + jerarquía comercial (vendedor → supervisor → gerencia →
-- directorio) + RLS. Patrón adaptado del CRM VITANOVA (single-tenant).
--
-- Endurecida tras revisión adversarial de 3 lentes (seguridad/portal/SQL).
-- Ver docs/recon-f0/ — resumen de fixes al final del archivo.
--
-- REGLAS DE ESTA Y TODA MIGRACIÓN DEL CRM:
--   · NO altera ningún objeto existente de `public` (solo referencia perfiles/
--     contratos por FK e inserta filas en audit_log vía trigger propio).
--   · RLS ON en toda tabla, deny-by-default; sin policy DELETE (soft-delete
--     `activo = false`); log de actividades inmutable.
--   · Escrituras privilegiadas (alta de equipo, conversión lead→cliente) SOLO
--     por RPC/edge SECURITY DEFINER que fija el flag `crm.op_privilegiada`.
--   · Los roles comerciales NUNCA leen public.perfiles crudo (columnas
--     bancarias): solo la vista crm.clientes_basicos.
--
-- PASO MANUAL POST-APLICACIÓN (Dashboard → Settings → API → Exposed schemas):
--   añadir SOLO `crm` (queda: public, crm). `private` JAMÁS se expone.
-- ============================================================================

-- 0. Esquemas ----------------------------------------------------------------
create schema if not exists crm;
create schema if not exists private;

grant usage on schema crm to authenticated;
grant usage on schema private to authenticated;
-- service_role necesita usage + grants para las edge functions de F1+
-- (rolbypassrls NO exime de los ACL de esquema). Fix revisión (lente portal).
grant usage on schema crm to service_role;
grant usage on schema private to service_role;
-- anon NO recibe usage: el CRM exige sesión.

-- 1. crm.equipo — jerarquía comercial ----------------------------------------
-- La membresía del CRM NO toca perfiles.rol: un perfil del portal (normalmente
-- rol 'analista') se enrola aquí con su rol comercial. El directorio NO se
-- enrola: entra por perfiles.rol='directorio' con lectura global (policies
-- dedicadas). Un vendedor puede quedar sin supervisor (reporta a gerencia).
create table crm.equipo (
  perfil_id      uuid primary key references public.perfiles(id) on delete cascade,
  rol_crm        text not null check (rol_crm in ('vendedor','supervisor','gerencia')),
  supervisor_id  uuid references crm.equipo(perfil_id) on delete set null,
  activo         boolean not null default true,
  creado_por     uuid references public.perfiles(id) on delete set null,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint equipo_no_autosupervision
    check (supervisor_id is null or supervisor_id <> perfil_id)
);
comment on table crm.equipo is
  'Jerarquía comercial del CRM: vendedor → supervisor → gerencia. El directorio queda fuera (lectura global por rol del portal).';

create index idx_equipo_supervisor on crm.equipo (supervisor_id) where activo = true;

alter table crm.equipo enable row level security;

-- 2. Helpers de visibilidad (en `private`, NO expuesto por PostgREST) --------
-- Defensa en profundidad: aunque `private` no se expone, los helpers exigen
-- que p_perfil_id sea el propio usuario o un lector global — así, si algún día
-- `private` se expusiera por error, no sirven como oráculo de enumeración.

create or replace function private.rol_crm(p_perfil_id uuid)
returns text
language sql stable security definer
set search_path = crm, public
as $$
  select rol_crm from crm.equipo where perfil_id = p_perfil_id and activo = true;
$$;

-- El conjunto de perfil_id que el usuario puede ver. gerencia = todos los
-- enrolados; supervisor = su subárbol recursivo; vendedor = solo él.
-- IMPORTANTE: la membresía jerárquica NO depende de `activo` (un vendedor
-- desactivado sigue siendo "visto" para que gerencia pueda reasignar su
-- cartera); `activo` solo decide QUIÉN consulta, no quién es visible.
create or replace function private.vendedor_ids_visibles(p_perfil_id uuid)
returns setof uuid
language plpgsql stable security definer
set search_path = crm, public
as $$
declare
  v_rol text;
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return; -- defensa en profundidad: no enumerar equipos ajenos
  end if;

  select rol_crm into v_rol
  from crm.equipo where perfil_id = p_perfil_id and activo = true;

  if v_rol is null then
    return;
  elsif v_rol = 'gerencia' then
    return query select perfil_id from crm.equipo; -- todos (activos o no)
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select perfil_id from crm.equipo where perfil_id = p_perfil_id
        union            -- UNION (no ALL): corta ciclos accidentales A↔B
        select e.perfil_id
        from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select perfil_id from subarbol;
  else -- vendedor
    return next p_perfil_id;
  end if;
end;
$$;

create or replace function private.puede_ver_cartera(p_perfil_id uuid, p_propietario_id uuid)
returns boolean
language sql stable security definer
set search_path = private, crm, public
as $$
  select exists (
    select 1 from private.vendedor_ids_visibles(p_perfil_id) v
    where v = p_propietario_id
  );
$$;

-- Lectura global de solo-lectura: directorio y administración del portal.
create or replace function private.es_lector_global()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid())
      and activo = true
      and rol in ('directorio','admin','superadmin')
  );
$$;

grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.vendedor_ids_visibles(uuid) to authenticated;
grant execute on function private.puede_ver_cartera(uuid, uuid) to authenticated;
grant execute on function private.es_lector_global() to authenticated;

-- 3. Policies de crm.equipo ---------------------------------------------------
create policy equipo_select on crm.equipo
  for select to authenticated
  using (
    perfil_id = (select auth.uid())
    or perfil_id in (select private.vendedor_ids_visibles((select auth.uid())))
    or (select private.es_lector_global())
  );
-- SIN policies de INSERT/UPDATE/DELETE: el alta/edición del equipo va por RPC
-- SECURITY DEFINER gerencia-gated (F1) o por superadmin vía SQL.

-- 4. crm.leads — el lead de inversión (tabla central) -------------------------
create table crm.leads (
  id                     uuid primary key default gen_random_uuid(),
  nombre_completo        text not null,
  telefono               text not null,
  correo                 text,
  dni                    text check (dni is null or dni ~ '^[0-9]{8}$'),
  distrito               text,
  origen                 text not null default 'otro'
    check (origen in ('referido','web','whatsapp','campania','oficina','otro')),
  etapa                  text not null default 'nuevo'
    check (etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado')),
  motivo_descarte        text
    check (motivo_descarte in ('sin_interes','sin_fondos','competencia','no_responde','datos_invalidos','otro')),
  monto_estimado         numeric(12,2) check (monto_estimado is null or monto_estimado >= 0),
  moneda                 text not null default 'PEN' check (moneda in ('PEN','USD')),
  categoria_interes      text check (categoria_interes in ('nuevo','renovacion','upgrade')),
  vendedor_id            uuid references crm.equipo(perfil_id) on delete set null,
  asignado_supervisor_id uuid references crm.equipo(perfil_id) on delete set null,
  perfil_id              uuid references public.perfiles(id) on delete set null,
  contrato_id            uuid references public.contratos(id) on delete set null,
  convertido_en          timestamptz,
  nota                   text,
  activo                 boolean not null default true,
  creado_por             uuid references public.perfiles(id) on delete set null,
  creado_en              timestamptz not null default now(),
  actualizado_en         timestamptz not null default now(),
  constraint descartado_requiere_motivo
    check (etapa <> 'descartado' or motivo_descarte is not null)
  -- NOTA: la exigencia "convertido ⇒ perfil_id no nulo" NO es un CHECK de tabla
  -- (chocaría con ON DELETE SET NULL al borrar un cliente en el portal). Se
  -- valida en la transición, dentro del trigger de conversión. Fix revisión.
);
comment on table crm.leads is
  'Lead de inversión. vendedor_id null = parkeado al supervisor de turno. La conversión (etapa=convertido + perfil_id/contrato_id) SOLO ocurre vía RPC privilegiada.';

-- Dedup vivo: un mismo teléfono/DNI no puede tener dos leads abiertos.
create unique index uq_leads_telefono_vivo on crm.leads (telefono)
  where activo = true and etapa not in ('convertido','descartado');
create unique index uq_leads_dni_vivo on crm.leads (dni)
  where dni is not null and activo = true and etapa not in ('convertido','descartado');

create index idx_leads_vendedor on crm.leads (vendedor_id) where activo = true;
create index idx_leads_etapa on crm.leads (etapa) where activo = true;
create index idx_leads_parkeo on crm.leads (asignado_supervisor_id)
  where vendedor_id is null and activo = true;
create index idx_leads_perfil on crm.leads (perfil_id) where perfil_id is not null;
create index idx_leads_contrato on crm.leads (contrato_id) where contrato_id is not null;

alter table crm.leads enable row level security;

-- 5. crm.actividades — timeline inmutable del lead ----------------------------
create table crm.actividades (
  id         uuid primary key default gen_random_uuid(),
  lead_id    uuid not null references crm.leads(id) on delete cascade,
  tipo       text not null check (tipo in (
    'llamada_realizada','llamada_no_contestada','whatsapp_enviado',
    'whatsapp_recibido','reunion_realizada','nota','cambio_etapa',
    'reasignacion','conversion')),
  detalle    text,
  metadata   jsonb not null default '{}'::jsonb,
  creado_por uuid references public.perfiles(id) on delete set null,
  creado_en  timestamptz not null default now()
);
comment on table crm.actividades is
  'Log inmutable de auditoría comercial: sin UPDATE ni DELETE para clientes API.';

create index idx_actividades_lead on crm.actividades (lead_id, creado_en desc);

alter table crm.actividades enable row level security;

-- 6. Triggers de negocio (funciones en private, SECURITY DEFINER) -------------

-- Touch de actualizado_en + INMUTABILIDAD de columnas de trazabilidad
-- (id, creado_por, creado_en). Espejo de proteger_campos_inmutables del portal.
create or replace function private.leads_before_update()
returns trigger
language plpgsql security definer
set search_path = crm, public
as $$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Columnas inmutables: restaurar siempre desde OLD.
  new.id := old.id;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.actualizado_en := now();

  -- Conversión y enlace al portal: SOLO desde una RPC privilegiada
  -- (que fija crm.op_privilegiada='on'). Un cliente API no puede convertir
  -- ni enlazar perfil_id/contrato_id a mano.
  if not v_priv then
    if new.etapa = 'convertido' and old.etapa <> 'convertido' then
      raise exception 'La conversión a cliente solo se hace vía la operación de conversión';
    end if;
    new.perfil_id := old.perfil_id;
    new.contrato_id := old.contrato_id;
    new.convertido_en := old.convertido_en;
  end if;

  -- Invariante de negocio en la transición (no como CHECK de tabla):
  if new.etapa = 'convertido' and new.perfil_id is null then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$$;

create trigger trg_leads_before_update before update on crm.leads
  for each row execute function private.leads_before_update();

-- INSERT: bloquear que un lead nazca ya "convertido" o pre-enlazado sin la RPC.
create or replace function private.leads_before_insert()
returns trigger
language plpgsql security definer
set search_path = crm, public
as $$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if not v_priv then
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada') then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$$;

create trigger trg_leads_before_insert before insert on crm.leads
  for each row execute function private.leads_before_insert();

create or replace function private.set_actualizado_en_crm()
returns trigger
language plpgsql security definer
set search_path = crm
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

create trigger trg_equipo_touch before update on crm.equipo
  for each row execute function private.set_actualizado_en_crm();

-- Normalización de teléfono Perú a E.164 (+51 + 9 dígitos).
create or replace function private.normalizar_telefono(p text)
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

create or replace function private.trg_leads_normalizar_telefono()
returns trigger
language plpgsql security definer
set search_path = private
as $$
begin
  new.telefono := private.normalizar_telefono(new.telefono);
  return new;
end;
$$;

create trigger trg_leads_normalizar_tel
  before insert or update of telefono on crm.leads
  for each row execute function private.trg_leads_normalizar_telefono();

-- Cambio de etapa → actividad en el timeline + sello de conversión.
create or replace function private.trg_leads_cambio_etapa()
returns trigger
language plpgsql security definer
set search_path = crm, private, public
as $$
begin
  if new.etapa is distinct from old.etapa then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (
      new.id, 'cambio_etapa', old.etapa || ' → ' || new.etapa,
      jsonb_build_object('etapa_anterior', old.etapa, 'etapa_nueva', new.etapa),
      coalesce((select auth.uid()), new.creado_por)
    );
    if new.etapa = 'convertido' and new.convertido_en is null then
      new.convertido_en := now();
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_leads_cambio_etapa before update on crm.leads
  for each row execute function private.trg_leads_cambio_etapa();

-- Un vendedor no puede reasignar leads (ni auto-asignarse los parkeados).
create or replace function private.trg_leads_bloquear_reasignacion()
returns trigger
language plpgsql security definer
set search_path = private, crm
as $$
begin
  if new.vendedor_id is distinct from old.vendedor_id
     and private.rol_crm((select auth.uid())) = 'vendedor' then
    raise exception 'Un vendedor no puede reasignar leads';
  end if;
  return new;
end;
$$;

create trigger trg_leads_bloquear_reasignacion before update on crm.leads
  for each row execute function private.trg_leads_bloquear_reasignacion();

-- Auditoría → public.audit_log (INSERTA filas; no modifica nada de public).
create or replace function private.log_audit_crm()
returns trigger
language plpgsql security definer
set search_path = public, crm
as $$
declare
  v_fila uuid;
begin
  v_fila := coalesce(
    (to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
    (to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
  );
  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    (select auth.uid()),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

create trigger trg_audit_equipo after insert or update or delete on crm.equipo
  for each row execute function private.log_audit_crm();
create trigger trg_audit_leads after insert or update or delete on crm.leads
  for each row execute function private.log_audit_crm();
create trigger trg_audit_actividades after insert on crm.actividades
  for each row execute function private.log_audit_crm();

-- 7. Policies de crm.leads -----------------------------------------------------
-- Helper local para "gerencia consulta" (evita repetir la subconsulta).
create policy leads_select on crm.leads
  for select to authenticated
  using (
    (activo = true and (
      vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (vendedor_id is null
          and asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
      or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    ))
    or (select private.es_lector_global())  -- directorio/admin: lectura total
  );

create policy leads_insert on crm.leads
  for insert to authenticated
  with check (
    activo = true
    and creado_por = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) is not null
    and (
      vendedor_id = (select auth.uid())
      or ((select private.rol_crm((select auth.uid()))) in ('supervisor','gerencia')
          and (vendedor_id is null
               or vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))))
    )
    -- el supervisor de destino del parkeo debe estar en mi ámbito
    and (asignado_supervisor_id is null
         or asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
  );

create policy leads_update on crm.leads
  for update to authenticated
  using (
    activo = true
    and (
      vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (vendedor_id is null
          and asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
      or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    )
  )
  with check (
    (vendedor_id is null
     or vendedor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    and (asignado_supervisor_id is null
         or asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    -- el soft-delete (activo=false) es privilegio de supervisor/gerencia
    and (activo = true or (select private.rol_crm((select auth.uid()))) in ('supervisor','gerencia'))
  );
-- SIN policy DELETE. directorio/admin NO aparecen en insert/update → solo-lectura.
-- NOTA: gerencia SIEMPRE pasa el USING (rama 'gerencia'), así que puede reasignar
-- leads de un vendedor desactivado (vendedor_id ya no visible pero rama gerencia sí).

-- 8. Policies de crm.actividades ------------------------------------------------
create policy actividades_select on crm.actividades
  for select to authenticated
  using (
    exists (
      select 1 from crm.leads l
      where l.id = actividades.lead_id
        and (
          (l.activo = true and (
            l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
            or (l.vendedor_id is null
                and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
            or (select private.rol_crm((select auth.uid()))) = 'gerencia'
          ))
          or (select private.es_lector_global())
        )
    )
  );

create policy actividades_insert on crm.actividades
  for insert to authenticated
  with check (
    creado_por = (select auth.uid())
    -- cambio_etapa/reasignacion/conversion los emiten SOLO triggers/RPCs
    and tipo not in ('cambio_etapa','reasignacion','conversion')
    and exists (
      select 1 from crm.leads l
      where l.id = actividades.lead_id
        and l.activo = true
        and (
          l.vendedor_id = (select auth.uid())
          or ((select private.rol_crm((select auth.uid()))) in ('supervisor','gerencia')
              and (l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
                   or (l.vendedor_id is null
                       and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))))
        )
    )
  );
-- SIN UPDATE ni DELETE: log inmutable.

-- 9. Vista de clientes SIN columnas bancarias ----------------------------------
-- SECURITY INVOKER: las policies existentes de public.perfiles deciden qué
-- filas ve cada quien. El CRM nunca expone banco/numero_cuenta/cci ni espejos USD.
create view crm.clientes_basicos
with (security_invoker = true) as
select id, nombres, apellidos, nombre_completo, dni, correo, telefono,
       asesor_perfil_id, activo, creado_en
from public.perfiles
where rol = 'cliente';

grant select on crm.clientes_basicos to authenticated;

-- Chequeo de duplicado en captación: ¿este DNI ya es cliente del portal?
-- GATE INTERNO: solo staff del CRM o lector global — NUNCA un cliente del portal
-- (si no, sería un oráculo de enumeración de la cartera). Fix revisión (crítico).
create or replace function crm.existe_cliente_por_dni(p_dni text)
returns boolean
language plpgsql stable security definer
set search_path = private, public
as $$
begin
  if private.rol_crm((select auth.uid())) is null and not private.es_lector_global() then
    raise exception 'No autorizado';
  end if;
  return exists (
    select 1 from public.perfiles
    where dni = p_dni and rol = 'cliente' and activo = true
  );
end;
$$;

-- 10. Grants de tabla + hardening ----------------------------------------------
grant select                 on crm.equipo       to authenticated;
grant select, insert, update on crm.leads        to authenticated;
grant select, insert         on crm.actividades  to authenticated;
-- (sin DELETE en ninguna; anon sin nada)

-- service_role para edge functions de F1+ (alta de equipo, conversión).
grant select, insert, update, delete on crm.equipo, crm.leads, crm.actividades to service_role;

revoke all on function crm.existe_cliente_por_dni(text) from public, anon;
grant execute on function crm.existe_cliente_por_dni(text) to authenticated;

-- Funciones-trigger: nadie las invoca por API.
revoke execute on function private.set_actualizado_en_crm()          from public, anon, authenticated;
revoke execute on function private.leads_before_update()             from public, anon, authenticated;
revoke execute on function private.leads_before_insert()             from public, anon, authenticated;
revoke execute on function private.trg_leads_normalizar_telefono()   from public, anon, authenticated;
revoke execute on function private.trg_leads_cambio_etapa()          from public, anon, authenticated;
revoke execute on function private.trg_leads_bloquear_reasignacion() from public, anon, authenticated;
revoke execute on function private.log_audit_crm()                   from public, anon, authenticated;
revoke execute on function private.normalizar_telefono(text)         from public, anon;
grant  execute on function private.normalizar_telefono(text)         to authenticated;

-- ============================================================================
-- FIXES APLICADOS TRAS REVISIÓN ADVERSARIAL (3 lentes: seguridad/portal/SQL)
--   [alta]  Oráculo de DNI: existe_cliente_por_dni ahora exige staff CRM/lector.
--   [alta]  Conversión a cliente / enlace perfil_id/contrato_id: bloqueada para
--           el cliente API; solo la RPC de F3 (fija crm.op_privilegiada='on').
--   [alta]  CHECK convertido_requiere_perfil movido a trigger (no rompe el
--           hard-delete de clientes del portal por ON DELETE SET NULL).
--   [media] Leads de un vendedor desactivado: gerencia SÍ los ve/reasigna
--           (vendedor_ids_visibles no filtra 'activo' del lado "visto").
--   [media] Inmutabilidad de id/creado_por/creado_en en leads (trigger).
--   [media] asignado_supervisor_id validado en insert/update (no parkeo cruzado).
--   [media] service_role con usage+grants en crm/private (edges de F1 no rotas).
--   [baja]  CTE recursivo con UNION (no ALL): inmune a ciclos A↔B.
--   [baja]  actividades_insert veta también 'conversion' y 'reasignacion'.
--   [baja]  Helpers private exigen auth.uid()/lector (no enumeración si se
--           expusiera private por error).
--   [baja]  es_lector_global()/rol_crm() envueltos en (select ...) → initplan.
-- ============================================================================
