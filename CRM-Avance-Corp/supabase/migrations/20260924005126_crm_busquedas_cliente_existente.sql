-- Venta cruzada · Fase 1 (1 de 2): bitácora de búsquedas de cliente existente.
--
-- QUÉ HACE. Crea crm.busquedas_cliente_existente: una fila por cada búsqueda
-- exacta de un cliente que ya existe (por documento, por teléfono o desde un
-- lead), con quién buscó, qué criterio usó, el valor normalizado y el
-- veredicto. Es el rastro anti-pesca de la venta cruzada y, además, la llave de
-- su puerta: solo se puede preparar la inversión de un cliente ajeno a partir de
-- una búsqueda PROPIA, reciente, por documento y con veredicto «encontrado» de
-- esa misma persona (lo exige la base en la migración siguiente, 20260924005127).
--
-- POR QUÉ. Decisión D1 de Miguel (23/09/2026): un vendedor o supervisor puede
-- registrar la nueva inversión de un cliente que no es suyo, dejando rastro para
-- Gerencia. Buscar por documento revela si esa persona es cliente; el precedente
-- es crm.verificaciones_lead (anti-pesca del alta de leads). Plan y decisiones:
-- tablero FigJam «Venta cruzada».
--
-- CONDUCTA. NINGUNA cambia: la tabla nace vacía y nadie la escribe todavía. La
-- escribirá crm.buscar_cliente_existente_fn (Fase 4).
--
-- ACCESO. Sin grants ni policies para anon, authenticated ni service_role:
-- nadie la lee directo; solo funciones security definer. Advisor esperado:
-- rls_enabled_no_policy (INFO), deliberado como en crm.lead_temperatura.
--
-- DATOS PERSONALES. valor_consultado guarda el documento o el teléfono
-- tecleados, normalizados, también los de personas que NO son clientes. La
-- auditoría lo enmascara (private.log_audit_sin_secretos, literal «***») porque
-- public.audit_log lo lee cualquier es_admin(). Quedan visibles en la auditoría,
-- como en el resto del CRM, la persona hallada (inversionista_id) y el lead.
-- La retención y purga de esta bitácora se decide antes de la Fase 4.
--
-- INMUTABLE. Es un rastro: no se actualiza, no se borra ni se vacía (triggers por
-- fila y de TRUNCATE que abortan). Las llaves a crm.leads y crm.inversionistas no
-- tienen ON DELETE: un borrado físico de esas filas falla cerrado aquí en vez de
-- dejar el rastro huérfano.
--
-- MULTITENANCY. Como el resto de crm: sin negocio_id, un solo negocio.
--
-- REVERSA. supabase/scripts/venta-cruzada/reversa-fase1.sql (retira las dos
-- migraciones de la Fase 1; falla cerrada si ya hay filas o dependencias).
begin;
set local lock_timeout = '5s';

do $pre$ begin
  if to_regclass('crm.busquedas_cliente_existente') is not null then
    raise exception 'La bitácora de búsquedas de clientes ya existe: esta migración ya se aplicó';
  end if;
end $pre$;

-- ---------------------------------------------------------------------------
-- 1. Tabla y reglas
-- ---------------------------------------------------------------------------
create table crm.busquedas_cliente_existente (
  id uuid primary key default gen_random_uuid(),
  consultado_por uuid not null references public.perfiles(id),
  criterio text not null
    constraint busqueda_cliente_criterio_valido check (criterio in ('documento','telefono','lead')),
  tipo_documento text
    constraint busqueda_cliente_tipo_valido check (tipo_documento in ('DNI','CE','PASAPORTE')),
  valor_consultado text not null
    constraint busqueda_cliente_valor_acotado check (length(valor_consultado) between 1 and 64),
  lead_id uuid references crm.leads(id),
  veredicto text not null
    constraint busqueda_cliente_veredicto_valido check (veredicto in
      ('encontrado','no_encontrado','ambiguo','conflicto','no_operable','limite','invalido')),
  inversionista_id uuid references crm.inversionistas(id),
  creado_en timestamptz not null default now(),
  constraint busqueda_cliente_documento_coherente check ((criterio = 'documento') = (tipo_documento is not null)),
  constraint busqueda_cliente_lead_coherente check ((criterio = 'lead') = (lead_id is not null)),
  -- «encontrado» siempre nombra a la persona; «no_operable» puede nombrarla
  -- (existe pero hoy no admite inversiones); el resto nunca la nombra.
  constraint busqueda_cliente_persona_coherente check (
    (veredicto = 'encontrado' and inversionista_id is not null)
    or veredicto = 'no_operable'
    or (veredicto not in ('encontrado','no_operable') and inversionista_id is null))
);
alter table crm.busquedas_cliente_existente enable row level security;
revoke all on crm.busquedas_cliente_existente from public, anon, authenticated, service_role;

-- El tope por hora y por actor lee siempre por (consultado_por, creado_en); las
-- otras dos cubren las llaves ajenas (advisor unindexed_foreign_keys).
create index busquedas_cliente_existente_actor_idx
  on crm.busquedas_cliente_existente (consultado_por, creado_en desc);
create index busquedas_cliente_existente_lead_idx
  on crm.busquedas_cliente_existente (lead_id) where lead_id is not null;
create index busquedas_cliente_existente_persona_idx
  on crm.busquedas_cliente_existente (inversionista_id) where inversionista_id is not null;

-- ---------------------------------------------------------------------------
-- 2. La llave: UNA sola definición de «esta búsqueda abre la venta cruzada»
-- ---------------------------------------------------------------------------
-- Propia (la hizo p_actor), por documento, «encontrado», de la misma persona
-- canónica y de las últimas 2 horas. La usan el trigger de las solicitudes
-- (20260924005127) y la autorización de la venta cruzada (Fase 2), para que la
-- regla no tenga dos copias. Security invoker: solo la llaman funciones del dueño.
create function private.busqueda_cliente_es_llave(p_busqueda uuid, p_actor uuid, p_persona uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select p_busqueda is not null and p_actor is not null and p_persona is not null and exists (
    select 1 from crm.busquedas_cliente_existente b
     where b.id = p_busqueda
       and b.consultado_por = p_actor
       and b.criterio = 'documento'
       and b.veredicto = 'encontrado'
       and private.inversionista_canonica(b.inversionista_id) = private.inversionista_canonica(p_persona)
       and b.creado_en >= statement_timestamp() - interval '2 hours')
$$;
revoke all on function private.busqueda_cliente_es_llave(uuid,uuid,uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Inmutabilidad y auditoría
-- ---------------------------------------------------------------------------
-- Security invoker a propósito: solo lanza un error; no lee ni escribe nada.
create function private.busqueda_cliente_inmutable()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  raise exception 'La bitácora de búsquedas de clientes no se modifica, no se borra ni se vacía'
    using errcode = 'P0409';
end $$;
revoke all on function private.busqueda_cliente_inmutable() from public, anon, authenticated, service_role;

create trigger busqueda_cliente_inmutable before update or delete
  on crm.busquedas_cliente_existente
  for each row execute function private.busqueda_cliente_inmutable();
-- TRUNCATE salta los triggers por fila (y con CASCADE vaciaría las solicitudes que
-- la referencian): se cierra también.
create trigger busqueda_cliente_no_truncate before truncate
  on crm.busquedas_cliente_existente
  for each statement execute function private.busqueda_cliente_inmutable();

create trigger trg_audit_busquedas_cliente_existente after insert or update or delete
  on crm.busquedas_cliente_existente
  for each row execute function private.log_audit_sin_secretos('valor_consultado');

-- ---------------------------------------------------------------------------
-- 4. Comentarios
-- ---------------------------------------------------------------------------
comment on function private.busqueda_cliente_es_llave(uuid,uuid,uuid) is
  'Venta cruzada: verdadero si la búsqueda es propia de p_actor, por documento, con veredicto encontrado, de la misma persona canónica que p_persona y de las últimas 2 horas. Única definición de la llave.';
comment on table crm.busquedas_cliente_existente is
  'Venta cruzada: bitácora inmutable de cada búsqueda exacta de un cliente existente (documento, teléfono o lead). Rastro anti-pesca para Gerencia y llave de la puerta de preparación. Sin lectura directa: solo funciones security definer. Contiene datos personales (valor_consultado), también de personas que no son clientes.';
comment on column crm.busquedas_cliente_existente.id is
  'Identificador de la búsqueda. La solicitud de venta cruzada lo guarda en busqueda_id como su llave.';
comment on column crm.busquedas_cliente_existente.consultado_por is
  'Perfil del miembro del CRM que hizo la búsqueda (auth.uid() de la puerta).';
comment on column crm.busquedas_cliente_existente.criterio is
  'Cómo se buscó: documento (exacto y normalizado), telefono (normalizado +51...) o lead (un lead del ámbito del actor).';
comment on column crm.busquedas_cliente_existente.tipo_documento is
  'DNI, CE o PASAPORTE. Solo cuando criterio = documento.';
comment on column crm.busquedas_cliente_existente.valor_consultado is
  'DATO PERSONAL. Valor buscado ya normalizado: documento, teléfono o id del lead (1 a 64 caracteres; la puerta trunca). La auditoría lo enmascara.';
comment on column crm.busquedas_cliente_existente.lead_id is
  'Lead desde el que se buscó. Solo cuando criterio = lead.';
comment on column crm.busquedas_cliente_existente.veredicto is
  'encontrado, no_encontrado, ambiguo (varias personas), conflicto (identidades discordantes), no_operable (existe pero hoy no admite inversiones), limite (tope por hora) o invalido (valor mal formado).';
comment on column crm.busquedas_cliente_existente.inversionista_id is
  'Persona canónica hallada. Obligatoria si el veredicto es encontrado; opcional si es no_operable; nula en el resto.';
comment on column crm.busquedas_cliente_existente.creado_en is
  'Momento de la búsqueda. La puerta de preparación exige una búsqueda de las últimas 2 horas.';
comment on function private.busqueda_cliente_inmutable() is
  'Trigger: la bitácora de búsquedas de clientes es inmutable (ni UPDATE, ni DELETE, ni TRUNCATE).';

-- ---------------------------------------------------------------------------
-- 5. Postflight: la tabla nace cerrada, auditada e inmutable
-- ---------------------------------------------------------------------------
do $post$
declare v_n integer;
begin
  if not (select relrowsecurity from pg_class where oid = 'crm.busquedas_cliente_existente'::regclass) then
    raise exception 'POSTFLIGHT: la bitácora nació sin RLS';
  end if;
  select count(*) into v_n from aclexplode((select relacl from pg_class where oid = 'crm.busquedas_cliente_existente'::regclass)) a
  where a.grantee in (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid);
  if v_n <> 0 then
    raise exception 'POSTFLIGHT: la bitácora quedó con % permisos para roles de la API', v_n;
  end if;
  if exists (select 1 from private.tablas_sin_rastro() t where t.tabla = 'crm.busquedas_cliente_existente') then
    raise exception 'POSTFLIGHT: la bitácora nació sin rastro de auditoría completo';
  end if;
  if (select count(*) from pg_trigger where tgrelid = 'crm.busquedas_cliente_existente'::regclass
      and not tgisinternal) <> 3 then
    raise exception 'POSTFLIGHT: la bitácora debía nacer con 3 triggers (inmutable, sin TRUNCATE y auditoría)';
  end if;
end $post$;

commit;
