-- REGISTRO en supabase_migrations.schema_migrations de RENTABILIDAD R1 (20260906170000).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración.
-- Idempotente; se niega si la migración no está aplicada o si la versión ya está registrada con OTRO contenido.
-- Toma el MISMO candado que la migración y la reversa (serializa contra una reversa concurrente).
-- Generado a partir del archivo de la migración (md5 758b26b21a84cb27990e8d93de6ae6e8).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r1'));
do $chk$
begin
  if to_regclass('crm.politica_rentabilidad') is null or to_regclass('crm.solicitudes_tasa') is null
     or to_regclass('crm.ledger_rentabilidad') is null
     or to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz)') is null
     or to_regprocedure('private.vencer_solicitudes_tasa(uuid)') is null
     or to_regprocedure('crm.resolver_tasa_fn(uuid,text,uuid)') is null
     or to_regprocedure('crm.solicitar_tasa_fn(jsonb)') is null
     or to_regprocedure('crm.resolver_solicitud_tasa_fn(uuid,text,numeric,text)') is null
     or to_regprocedure('crm.responder_tope_tasa_fn(uuid,boolean,text)') is null
     or to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)') is null then
    raise exception 'REGISTRO R1: la migración 20260906170000 NO está aplicada (faltan objetos); aplica primero';
  end if;
  -- La policy de solicitudes debe llevar la rama de Gerencia (auditor M1): distingue el texto auditado del primer borrador.
  if not exists (select 1 from pg_policies where schemaname = 'crm' and tablename = 'solicitudes_tasa'
                 and policyname = 'solicitudes_tasa_select' and qual like '%gerencia%') then
    raise exception 'REGISTRO R1: la policy solicitudes_tasa_select no es la auditada (falta la rama de Gerencia)';
  end if;
  if not exists (select 1 from crm.politica_rentabilidad where version = 1 and modo = 'observacion') then
    raise exception 'REGISTRO R1: falta la política v1 en observación';
  end if;
  if (select count(*) from crm.ledger_rentabilidad where origen = 'backfill_legacy') = 0 then
    raise exception 'REGISTRO R1: el ledger no tiene el backfill legacy';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260906170000' and coalesce(md5(statements[1]), '') <> '758b26b21a84cb27990e8d93de6ae6e8') then
    raise exception 'REGISTRO R1: la versión 20260906170000 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906170000', 'crm_rentabilidad_r1_politica_solicitudes_ledger_resolver', array[$m$-- ============================================================================
-- CRM · RENTABILIDAD SERVER-SIDE · R1 — NÚCLEO: política versionada, solicitudes de tasa, ledger y UN resolver
-- (plan del vault «Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06», decisiones D1..D6 acordadas el 06/09)
-- ============================================================================
--
-- QUÉ PASA HOY (medido en producción el 06/09/2026, solo lectura). La tasa anual del contrato la fija quien llena el
-- formulario: el CRM propone 15% pero la deja editable, el navegador manda la tasa y el cronograma, y las TRES puertas de
-- escritura (crm.crear_contrato_con_cuenta_pdf_v2, public.crear_contrato desde el portal admin y
-- crm.actualizar_contrato_con_cuenta_pdf_v3 en la corrección) aceptan cualquier tasa entre 0 y 50. El catálogo versionado
-- tiene tasa_min/tasa_max por condición, pero con 0 productos publicados el puente legacy crea el snapshot con la tasa que
-- llegó: no restringe nada. Censo: 524 contratos, 357 con tasa distinta de 15, 17 tasas distintas, 21 sin categoría.
--
-- QUÉ HACE ESTA MIGRACIÓN (aditiva; NO cambia ninguna alta ni corrección: las cinco puertas quedan byte a byte).
--   1. crm.politica_rentabilidad — política VERSIONADA e inmutable (molde de crm.sla_politicas): tasa base para primera
--      inversión, reglas de herencia, tope técnico, días de vigencia de una solicitud y `modo` (observacion|enforcement).
--      Nace la versión 1: 15% · heredada · tope 50 · 7 días · OBSERVACIÓN. Solo Gerencia publica (crm.publicar_politica_rentabilidad_fn);
--      en R1 el modo enforcement se RECHAZA (0A000): todavía no hay nada que lo lea.
--   2. private.resolver_tasa(cliente, categoría, contrato_origen) — EL ÚNICO NÚCLEO que responde «qué tasa base corresponde
--      a este contrato y por qué»: nuevo → tasa base de la política (D1: aunque el cliente ya tenga contratos; se marca
--      prioridad para la bandeja); renovación → hereda la tasa_anual del contrato origen (activo o vencido, no renovado);
--      upgrade → hereda la del contrato origen ACTIVO que el analista selecciona (D2). Nadie más calcula tasa.
--      La puerta crm.resolver_tasa_fn añade autorización (la misma pregunta que el alta: puede_registrar_ventas) y ámbito
--      (el cliente es visible para el actor: cartera/subárbol/gerencia/admin), con 42501 uniforme.
--   Autoridad de las puertas de tasa = la del alta (private.puede_registrar_ventas, decisión B: sin ámbito de cartera) sobre
--   un cliente ACTIVO; 42501 uniforme para no autorizado / inexistente / inactivo (auditor 06/09: M1, m1, m2).
--   3. crm.solicitudes_tasa — la excepción comercial: el analista pide una tasa SUPERIOR a la base (D4) con motivo;
--      Gerencia (nunca quien pidió, D3) aprueba, rechaza o «aprueba hasta X%» (D6, base < X <= pedida); con tope, el
--      analista acepta o declina. Un solo uso, atada a la HUELLA (cliente, categoría, origen, producto, capital, moneda,
--      modalidad, interés, fechas) y con vencimiento (7 días por política). Estados: pendiente → aprobada | aprobada_con_tope |
--      rechazada; aprobada_con_tope → aceptada_por_analista | declinada_por_analista; (aprobada | aceptada) → consumida (R4);
--      cualquier viva → vencida. Solo se escribe por sus puertas (trigger con GUC crm.solicitud_tasa_por_puerta).
--   4. crm.ledger_rentabilidad — append-only: por contrato, tasa base, tasa final, regla, origen, política y solicitud.
--      Backfill EXACTO de todos los contratos de hoy como `historica_legacy` (base = final = tasa_anual; no se reescribe
--      ninguna historia). Postflight: mismo conteo, misma suma y misma huella (id, tasa) que public.contratos.
--
-- QUÉ NO TOCA. Nada de `public` (ni DDL ni triggers; las tablas nuevas NO llevan FK a public.contratos a propósito:
-- una autorización o una fila histórica no deben impedir que Gerencia elimine un contrato por su puerta; la existencia
-- del contrato origen la valida el resolver). Ninguna de las cinco puertas de escritura cambia (guarda + postflight).
-- Modo observación (R2) y enforcement (R4) vienen en migraciones posteriores.
--
-- Ensayo: scripts/oraculo-rentabilidad-r1.sh (banco). Reversa: scripts/rollback-rentabilidad-r1.sql.
-- Registro: scripts/registrar-rentabilidad-r1.sql. Bloque «rentabilidad R1» en scripts/test-rls.mjs.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r1'));

-- ---------------------------------------------------------------------------
-- 0. GUARDAS: premisas vivas (prod = banco el 06/09) y que nada de esto exista aún.
-- ---------------------------------------------------------------------------
create temp table _r1_puertas on commit drop as
select p.oid as fnoid, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as firma, md5(p.prosrc) as h
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'crm' and p.proname in ('crear_contrato_con_cuenta_pdf_v2', 'actualizar_contrato_con_cuenta_pdf_v3', 'crear_contrato_con_cuenta'))
   or (n.nspname = 'public' and p.proname in ('crear_contrato', 'actualizar_contrato'));

do $guard$
declare
  v_h text;
  v_esperado jsonb := '{
    "crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)": "0fd6fa8d1d8f8106cb52662cb64193e0",
    "crm.actualizar_contrato_con_cuenta_pdf_v3(p_id uuid, p_contrato jsonb, p_cronograma jsonb)": "85614480d6c8939e818342ef3fe63c65",
    "crm.crear_contrato_con_cuenta(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)": "7f2b4976640553a50ab27cf25b30fb36",
    "public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)": "061c40e345312ca5e515ddd5ee282e5c",
    "public.actualizar_contrato(p_id uuid, p_contrato jsonb, p_cronograma jsonb)": "db2e6d36d46c72250fd6f42022af80be"
  }'::jsonb;
  v_k text;
begin
  if (select count(*) from _r1_puertas) <> 5 then
    raise exception 'RENTABILIDAD R1: faltan puertas de escritura de contratos (esperaba 5, hay %)', (select count(*) from _r1_puertas);
  end if;
  for v_k in select jsonb_object_keys(v_esperado) loop
    select h into v_h from _r1_puertas where firma = v_k;
    if v_h is distinct from (v_esperado ->> v_k) then
      raise exception 'RENTABILIDAD R1: % no es el texto vivo de producción del 06/09 (esperado %, hay %)', v_k, left(v_esperado ->> v_k, 8), coalesce(left(v_h, 8), 'nada');
    end if;
  end loop;
  -- Helpers que esta migración reutiliza (autoridad, ámbito, auditoría, inmutabilidad): huellas de producción.
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.rol_crm(uuid)'::regprocedure) is distinct from 'd2878a210be96ac85973d51dfcfb27a5' then
    raise exception 'RENTABILIDAD R1: private.rol_crm(uuid) no es el texto vivo (d2878a21…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.puede_registrar_ventas()'::regprocedure) is distinct from '2749bb0e5616eae42a0dd410bee4f52a' then
    raise exception 'RENTABILIDAD R1: private.puede_registrar_ventas() no es el texto vivo (2749bb0e…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.puede_consultar_cliente_ficha(uuid)'::regprocedure) is distinct from 'c1afbe30f28add201886f43cd80654e9' then
    raise exception 'RENTABILIDAD R1: private.puede_consultar_cliente_ficha(uuid) no es el texto vivo (c1afbe30…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.vendedor_ids_visibles(uuid)'::regprocedure) is distinct from '33ece9bae4828f7ffdb837c6128ca9d6' then
    raise exception 'RENTABILIDAD R1: private.vendedor_ids_visibles(uuid) no es el texto vivo (33ece9ba…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.es_lector_global()'::regprocedure) is distinct from 'c7c5828be6d74121a1a0ef0de374f712' then
    raise exception 'RENTABILIDAD R1: private.es_lector_global() no es el texto vivo (c7c5828b…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.log_audit_crm()'::regprocedure) is distinct from 'faccaae7fd104734408c8a0376023c6f' then
    raise exception 'RENTABILIDAD R1: private.log_audit_crm() no es el texto vivo (faccaae7…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.trg_config_versionada_inmutable()'::regprocedure) is distinct from 'fff4b96eba9f5511941a7f0ff4cceab2' then
    raise exception 'RENTABILIDAD R1: private.trg_config_versionada_inmutable() no es el texto vivo (fff4b96e…)';
  end if;
  -- Las policies se evalúan como el LLAMANTE: los helpers que usan deben tener EXECUTE para authenticated.
  if not has_function_privilege('authenticated', 'private.rol_crm(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.es_lector_global()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.vendedor_ids_visibles(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.puede_consultar_cliente_ficha(uuid)', 'EXECUTE') then
    raise exception 'RENTABILIDAD R1: un helper de las policies no tiene EXECUTE para authenticated';
  end if;
  if to_regclass('crm.politica_rentabilidad') is not null or to_regclass('crm.solicitudes_tasa') is not null
     or to_regclass('crm.ledger_rentabilidad') is not null or to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz)') is not null then
    raise exception 'RENTABILIDAD R1: ya está aplicada (existen sus objetos); no se reaplica';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906170000') then
    raise exception 'RENTABILIDAD R1: la versión 20260906170000 ya está registrada';
  end if;
end
$guard$;

-- ---------------------------------------------------------------------------
-- 1. POLÍTICA VERSIONADA (inmutable, se publica una revisión nueva)
-- ---------------------------------------------------------------------------
create table crm.politica_rentabilidad (
  id                      uuid primary key default gen_random_uuid(),
  version                 integer not null unique check (version > 0),
  version_anterior_id     uuid references crm.politica_rentabilidad(id) on delete restrict,
  vigente_desde           timestamptz not null unique,
  tasa_base_nueva         numeric not null check (tasa_base_nueva > 0 and tasa_base_nueva <= 50),
  regla_renovacion        text not null default 'heredada' check (regla_renovacion = 'heredada'),
  regla_upgrade           text not null default 'heredada' check (regla_upgrade = 'heredada'),
  tope_tecnico            numeric not null default 50 check (tope_tecnico > 0 and tope_tecnico <= 50),
  vigencia_solicitud_dias integer not null default 7 check (vigencia_solicitud_dias between 1 and 30),
  modo                    text not null default 'observacion' check (modo in ('observacion', 'enforcement')),
  nota                    text check (nota is null or length(btrim(nota)) between 1 and 500),
  publicada_por           uuid references public.perfiles(id) on delete restrict,
  publicada_en            timestamptz not null default statement_timestamp(),
  constraint politica_rentabilidad_tope_sobre_base check (tope_tecnico >= tasa_base_nueva)
);
alter table crm.politica_rentabilidad enable row level security;
comment on table crm.politica_rentabilidad is
  'Rentabilidad R1. Política VERSIONADA e inmutable de la tasa anual: base para primera inversión, herencia en renovación/upgrade, tope técnico, vigencia de solicitudes y modo (observacion: no bloquea; enforcement: R4). Solo Gerencia publica (crm.publicar_politica_rentabilidad_fn). La lee UN solo núcleo: private.resolver_tasa.';
comment on column crm.politica_rentabilidad.tasa_base_nueva is 'Tasa anual (%) de una PRIMERA inversión (D1: también para un cliente existente que abre inversión nueva).';
comment on column crm.politica_rentabilidad.tope_tecnico is 'Defensa técnica del servidor (D5). El tope comercial lo fija Gerencia en cada solicitud.';
comment on column crm.politica_rentabilidad.vigencia_solicitud_dias is 'Días que vive una solicitud/autorización sin consumirse (D6: 7).';
comment on column crm.politica_rentabilidad.modo is 'observacion: se registra la divergencia sin bloquear (R2). enforcement: la puerta impone la tasa resuelta (R4). En R1 solo se admite observacion.';

create trigger trg_politica_rentabilidad_inmutable
before update or delete on crm.politica_rentabilidad
for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_audit_politica_rentabilidad
after insert on crm.politica_rentabilidad
for each row execute function private.log_audit_crm();

revoke all on table crm.politica_rentabilidad from public, anon, authenticated, service_role;
grant select on table crm.politica_rentabilidad to authenticated, service_role;
create policy politica_rentabilidad_select on crm.politica_rentabilidad for select to authenticated
using ((select private.es_lector_global()) or (select private.rol_crm((select auth.uid()))) is not null);

insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, publicada_por, nota)
values (1, statement_timestamp(), 15, 50, 7, 'observacion', null,
        'R1 (06/09/2026): política inicial, espejo del 15% que hoy propone el formulario. Modo observación: no bloquea ninguna alta.');

create or replace function private.politica_rentabilidad_vigente(p_instante timestamptz)
returns crm.politica_rentabilidad
language sql stable security definer set search_path = ''
as $function$
  select p.* from crm.politica_rentabilidad p
  where p.vigente_desde <= coalesce(p_instante, statement_timestamp())
  order by p.vigente_desde desc, p.version desc
  limit 1
$function$;
revoke all on function private.politica_rentabilidad_vigente(timestamptz) from public, anon, authenticated, service_role;
comment on function private.politica_rentabilidad_vigente(timestamptz) is 'Rentabilidad R1: la política vigente en un instante (la última publicada con vigente_desde <= instante).';

-- ---------------------------------------------------------------------------
-- 2. EL NÚCLEO: private.resolver_tasa — la ÚNICA definición de «tasa base y por qué»
-- ---------------------------------------------------------------------------
create or replace function private.resolver_tasa(
  p_cliente_id uuid,
  p_categoria text,
  p_contrato_origen_id uuid,
  p_instante timestamptz default statement_timestamp()
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_pol      crm.politica_rentabilidad;
  v_cli      record;
  v_origen   public.contratos%rowtype;
  v_previos  integer;
  v_activos  integer;
  v_base     numeric;
  v_regla    text;
begin
  if p_cliente_id is null then
    raise exception 'El cliente es obligatorio' using errcode = '22023';
  end if;
  if p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (nuevo, renovacion o upgrade)' using errcode = '22023';
  end if;
  v_pol := private.politica_rentabilidad_vigente(p_instante);
  if v_pol.id is null then
    raise exception 'No hay política de rentabilidad vigente' using errcode = 'P0002';
  end if;
  select p.id, p.activo, p.asesor_perfil_id into v_cli
  from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente';
  if v_cli.id is null then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  if v_cli.activo is not true then
    -- Las puertas de alta exigen cliente ACTIVO: una tasa para un cliente inactivo sería una promesa que ningún alta cumple (auditor m1).
    raise exception 'El cliente está inactivo' using errcode = 'P0409';
  end if;
  select count(*), count(*) filter (where c.estado = 'activo')
    into v_previos, v_activos
  from public.contratos c where c.cliente_id = p_cliente_id and not c.es_demo;

  if p_categoria = 'nuevo' then
    if p_contrato_origen_id is not null then
      raise exception 'Una primera inversión no lleva contrato origen' using errcode = '22023';
    end if;
    v_base := v_pol.tasa_base_nueva;
    v_regla := 'primera_inversion';
  else
    if p_contrato_origen_id is null then
      raise exception 'Selecciona el contrato que se % (contrato origen)', case when p_categoria = 'renovacion' then 'renueva' else 'amplía' end
        using errcode = '22023';
    end if;
    select * into v_origen from public.contratos c where c.id = p_contrato_origen_id;
    if v_origen.id is null then
      raise exception 'El contrato origen no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from p_cliente_id then
      raise exception 'El contrato origen pertenece a otro cliente' using errcode = 'P0409';
    end if;
    if p_categoria = 'renovacion' then
      -- Mismo criterio que public.crear_contrato: se renueva un contrato activo o vencido que aún no fue renovado.
      if v_origen.estado not in ('activo', 'vencido') or v_origen.renovado_a_id is not null then
        raise exception 'El contrato origen ya fue cerrado o renovado (estado «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_renovacion';
    else
      -- D2: el upgrade amplía un contrato ACTIVO concreto que el analista selecciona.
      if v_origen.estado <> 'activo' or v_origen.renovado_a_id is not null then
        raise exception 'El upgrade solo amplía un contrato activo (este está «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_upgrade';
    end if;
    v_base := v_origen.tasa_anual;
  end if;

  return jsonb_build_object(
    'tasa_base', v_base,
    'regla', v_regla,
    'categoria', p_categoria,
    'cliente_id', p_cliente_id,
    'contrato_origen', case when v_origen.id is null then null else jsonb_build_object(
        'id', v_origen.id, 'numero_contrato', v_origen.numero_contrato, 'tasa_anual', v_origen.tasa_anual,
        'estado', v_origen.estado, 'moneda', v_origen.moneda, 'capital', v_origen.capital,
        'fecha_vencimiento', v_origen.fecha_vencimiento) end,
    'contratos_previos', v_previos,
    'contratos_activos', v_activos,
    -- D1: la excepción de un cliente que YA invirtió tiene prioridad en la bandeja de Gerencia.
    'prioridad_bandeja', (p_categoria = 'nuevo' and v_previos > 0),
    'politica', jsonb_build_object('id', v_pol.id, 'version', v_pol.version, 'modo', v_pol.modo,
        'tasa_base_nueva', v_pol.tasa_base_nueva, 'tope_tecnico', v_pol.tope_tecnico,
        'vigencia_solicitud_dias', v_pol.vigencia_solicitud_dias),
    'resuelto_en', coalesce(p_instante, statement_timestamp())
  );
end;
$function$;
revoke all on function private.resolver_tasa(uuid, text, uuid, timestamptz) from public, anon, authenticated, service_role;
comment on function private.resolver_tasa(uuid, text, uuid, timestamptz) is
  'Rentabilidad R1: EL ÚNICO NÚCLEO que responde «qué tasa base corresponde a este contrato y por qué». nuevo → tasa base de la política vigente (D1); renovacion → hereda tasa_anual del origen activo/vencido no renovado; upgrade → hereda la del origen ACTIVO seleccionado (D2). Toda puerta, trigger o pantalla que necesite la tasa base la CONSUME de aquí; está prohibido reimplementarla.';

-- Autoridad común a las puertas de tasa: EXACTAMENTE la misma pregunta que el alta (private.puede_registrar_ventas: admin
-- del Portal, analista del Portal vigente o miembro activo del CRM, sin revocar) y que el cliente exista ACTIVO con rol
-- cliente. Deliberadamente SIN ámbito de cartera: la decisión B del alta («cualquier analista, cualquier cliente») ya rige
-- en public.crear_contrato, y una puerta de tasa más estricta que el alta dejaría al formulario sin tasa para un contrato
-- que el alta sí aceptaría (auditor m2). Si Miguel quiere acotar por cartera, se hace aquí y en el alta a la vez.
-- Un no autorizado, un cliente inexistente o uno inactivo responden lo mismo: false → 42501 uniforme.
create or replace function private.puede_operar_tasa_cliente(p_cliente_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $function$
  select (select auth.uid()) is not null
     and p_cliente_id is not null
     and private.puede_registrar_ventas()
     and exists (select 1 from public.perfiles p
                 where p.id = p_cliente_id and p.rol = 'cliente' and p.activo is true);
$function$;
revoke all on function private.puede_operar_tasa_cliente(uuid) from public, anon, authenticated, service_role;
comment on function private.puede_operar_tasa_cliente(uuid) is 'Rentabilidad R1: la autoridad del alta (puede_registrar_ventas, decisión B: sin ámbito de cartera) sobre un cliente ACTIVO. False → 42501 uniforme.';

create or replace function crm.resolver_tasa_fn(
  p_cliente_id uuid,
  p_categoria text,
  p_contrato_origen_id uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
begin
  if not private.puede_operar_tasa_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  return private.resolver_tasa(p_cliente_id, p_categoria, p_contrato_origen_id, statement_timestamp());
end;
$function$;
revoke all on function crm.resolver_tasa_fn(uuid, text, uuid) from public, anon, service_role;
grant execute on function crm.resolver_tasa_fn(uuid, text, uuid) to authenticated;
comment on function crm.resolver_tasa_fn(uuid, text, uuid) is
  'Rentabilidad R1: la puerta de lectura del núcleo private.resolver_tasa para el formulario de contrato. Solo authenticated con la autoridad del alta y el cliente en su ámbito (42501 uniforme). Devuelve {tasa_base, regla, contrato_origen, contratos_previos, prioridad_bandeja, politica}.';

-- ---------------------------------------------------------------------------
-- 3. SOLICITUDES DE TASA (la excepción comercial)
-- ---------------------------------------------------------------------------
create table crm.solicitudes_tasa (
  id                          uuid primary key default gen_random_uuid(),
  politica_id                 uuid not null references crm.politica_rentabilidad(id) on delete restrict,
  cliente_id                  uuid not null references public.perfiles(id) on delete restrict,
  categoria                   text not null check (categoria in ('nuevo', 'renovacion', 'upgrade')),
  contrato_origen_id          uuid,
  contrato_origen_numero      text,
  producto_condicion_id       uuid,
  capital                     numeric not null check (capital >= 100 and capital <= 100000000),
  moneda                      text not null check (moneda in ('PEN', 'USD')),
  modalidad                   text not null check (modalidad in ('mensual', 'trimestral', 'semestral', 'anual')),
  tipo_interes                text not null check (tipo_interes in ('simple', 'compuesto')),
  fecha_inicio                date not null,
  fecha_vencimiento           date not null,
  huella                      text not null,
  tasa_base                   numeric not null check (tasa_base > 0 and tasa_base <= 50),
  regla_base                  text not null check (regla_base in ('primera_inversion', 'heredada_renovacion', 'heredada_upgrade')),
  contratos_previos           integer not null default 0 check (contratos_previos >= 0),
  prioridad_bandeja           boolean not null default false,
  tasa_solicitada             numeric not null check (tasa_solicitada > 0 and tasa_solicitada <= 50 and scale(tasa_solicitada) <= 2),
  motivo                      text not null check (length(btrim(motivo)) between 5 and 500),
  estado                      text not null default 'pendiente' check (estado in (
                                'pendiente', 'aprobada', 'aprobada_con_tope', 'rechazada',
                                'aceptada_por_analista', 'declinada_por_analista', 'consumida', 'vencida')),
  tasa_maxima_autorizada      numeric check (tasa_maxima_autorizada is null or (tasa_maxima_autorizada > 0 and tasa_maxima_autorizada <= 50 and scale(tasa_maxima_autorizada) <= 2)),
  motivo_resolucion           text check (motivo_resolucion is null or length(btrim(motivo_resolucion)) between 1 and 500),
  solicitada_por              uuid not null references public.perfiles(id) on delete restrict,
  solicitada_en               timestamptz not null default statement_timestamp(),
  vence_en                    timestamptz not null,
  resuelta_por                uuid references public.perfiles(id) on delete restrict,
  resuelta_en                 timestamptz,
  respondida_por_analista_en  timestamptz,
  motivo_analista             text check (motivo_analista is null or length(btrim(motivo_analista)) between 1 and 500),
  consumida_en                timestamptz,
  contrato_id                 uuid,
  actualizado_en              timestamptz not null default statement_timestamp(),
  constraint solicitudes_tasa_plazo check (fecha_vencimiento > fecha_inicio),
  constraint solicitudes_tasa_solo_eleva check (tasa_solicitada > tasa_base),
  constraint solicitudes_tasa_origen_por_categoria check (
    (categoria = 'nuevo' and contrato_origen_id is null) or (categoria <> 'nuevo' and contrato_origen_id is not null)),
  constraint solicitudes_tasa_nadie_se_aprueba check (resuelta_por is null or resuelta_por <> solicitada_por),
  constraint solicitudes_tasa_tope_en_rango check (
    tasa_maxima_autorizada is null or (tasa_maxima_autorizada > tasa_base and tasa_maxima_autorizada <= tasa_solicitada)),
  constraint solicitudes_tasa_vence_despues check (vence_en > solicitada_en),
  constraint solicitudes_tasa_estado_coherente check (
    case estado
      when 'pendiente'              then resuelta_por is null and tasa_maxima_autorizada is null and respondida_por_analista_en is null and consumida_en is null
      when 'rechazada'              then resuelta_por is not null and tasa_maxima_autorizada is null and consumida_en is null
      when 'aprobada'               then resuelta_por is not null and tasa_maxima_autorizada = tasa_solicitada and consumida_en is null
      when 'aprobada_con_tope'      then resuelta_por is not null and tasa_maxima_autorizada < tasa_solicitada and respondida_por_analista_en is null and consumida_en is null
      when 'aceptada_por_analista'  then resuelta_por is not null and tasa_maxima_autorizada < tasa_solicitada and respondida_por_analista_en is not null and consumida_en is null
      when 'declinada_por_analista' then resuelta_por is not null and tasa_maxima_autorizada < tasa_solicitada and respondida_por_analista_en is not null and consumida_en is null
      when 'consumida'              then resuelta_por is not null and tasa_maxima_autorizada is not null and consumida_en is not null and contrato_id is not null
      when 'vencida'                then consumida_en is null
      else false
    end)
);
alter table crm.solicitudes_tasa enable row level security;
comment on table crm.solicitudes_tasa is
  'Rentabilidad R1. Solicitud de una tasa SUPERIOR a la base (D4) para un contrato en intención, identificado por su HUELLA. El analista pide con motivo; Gerencia —nunca quien pidió (D3)— aprueba, rechaza o aprueba hasta un tope (D6); con tope, el analista acepta o declina. Un solo uso (consumida, R4) y con vencimiento. Solo se escribe por sus puertas crm.*_tasa_fn (trigger con GUC crm.solicitud_tasa_por_puerta).';
comment on column crm.solicitudes_tasa.huella is 'md5 de la intención canónica (cliente, categoría, origen, producto, capital, moneda, modalidad, interés, fechas) — private.huella_solicitud_tasa. Si el contrato cambia, la autorización no aplica.';
comment on column crm.solicitudes_tasa.tasa_maxima_autorizada is 'La tasa AUTORIZADA efectiva: = tasa_solicitada si Gerencia aprobó tal cual; < tasa_solicitada si aprobó hasta un tope (D6). NULL si pendiente o rechazada.';
comment on column crm.solicitudes_tasa.prioridad_bandeja is 'D1: primera inversión de un cliente que ya tiene contratos → va primero en la bandeja de Gerencia.';
comment on column crm.solicitudes_tasa.contrato_id is 'Contrato que consumió la autorización (R4). Sin FK a public.contratos a propósito: la eliminación del contrato por su puerta no se bloquea.';
comment on column crm.solicitudes_tasa.contrato_origen_id is 'Renovación/upgrade: contrato del que se hereda la tasa base. Sin FK a public.contratos a propósito (ver contrato_id).';

create index solicitudes_tasa_estado_idx on crm.solicitudes_tasa (estado, prioridad_bandeja desc, solicitada_en);
create index solicitudes_tasa_solicitante_idx on crm.solicitudes_tasa (solicitada_por, solicitada_en desc);
create index solicitudes_tasa_cliente_idx on crm.solicitudes_tasa (cliente_id);
-- D6: UNA solicitud viva por intención (huella), pida quien pida: el supervisor no puede abrir otra sobre la del analista.
create unique index solicitudes_tasa_una_viva_por_huella on crm.solicitudes_tasa (huella)
  where estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista');

create or replace function private.trg_solicitudes_tasa_solo_por_puerta()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una solicitud de tasa no se borra: queda como historia' using errcode = 'P0409';
  end if;
  if coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off') <> 'on' then
    raise exception 'Una solicitud de tasa solo cambia por sus puertas (crm.*_tasa_fn)' using errcode = 'P0409';
  end if;
  new.actualizado_en := statement_timestamp();
  return new;
end;
$function$;
revoke all on function private.trg_solicitudes_tasa_solo_por_puerta() from public, anon, authenticated, service_role;
comment on function private.trg_solicitudes_tasa_solo_por_puerta() is
  'Rentabilidad R1: cinturón contra escrituras ACCIDENTALES desde postgres (dashboard, migraciones, scripts): la API no tiene UPDATE/DELETE en la tabla (esa es la frontera de seguridad); el GUC crm.solicitud_tasa_por_puerta lo fijan las puertas crm.*_tasa_fn. No cubre INSERT (solo lo hace solicitar_tasa_fn).';
create trigger trg_solicitudes_tasa_00_solo_por_puerta
before update or delete on crm.solicitudes_tasa
for each row execute function private.trg_solicitudes_tasa_solo_por_puerta();
create trigger trg_audit_solicitudes_tasa
after insert or update on crm.solicitudes_tasa
for each row execute function private.log_audit_crm();

revoke all on table crm.solicitudes_tasa from public, anon, authenticated, service_role;
grant select on table crm.solicitudes_tasa to authenticated, service_role;
-- Quién ve una solicitud: quien la pidió; su supervisor (subárbol); Gerencia (TODAS, también las de solicitantes sin ficha
-- CRM: admin del Portal o analista del Portal —auditor M1—); Directorio (lector global).
create policy solicitudes_tasa_select on crm.solicitudes_tasa for select to authenticated
using (
  solicitada_por = (select auth.uid())
  or (select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) = 'gerencia'
  or solicitada_por in (select private.vendedor_ids_visibles((select auth.uid())))
);

create or replace function private.huella_solicitud_tasa(
  p_cliente_id uuid, p_categoria text, p_contrato_origen_id uuid, p_producto_condicion_id uuid,
  p_capital numeric, p_moneda text, p_modalidad text, p_tipo_interes text, p_fecha_inicio date, p_fecha_vencimiento date
)
returns text
language sql immutable set search_path = ''
as $function$
  select md5(jsonb_build_object(
    'cliente_id', p_cliente_id, 'categoria', p_categoria, 'contrato_origen_id', p_contrato_origen_id,
    'producto_condicion_id', p_producto_condicion_id, 'capital', p_capital::numeric(14,2), 'moneda', p_moneda,
    'modalidad', p_modalidad, 'tipo_interes', p_tipo_interes,
    'fecha_inicio', p_fecha_inicio::text, 'fecha_vencimiento', p_fecha_vencimiento::text)::text)
$function$;
revoke all on function private.huella_solicitud_tasa(uuid, text, uuid, uuid, numeric, text, text, text, date, date) from public, anon, authenticated, service_role;
comment on function private.huella_solicitud_tasa(uuid, text, uuid, uuid, numeric, text, text, text, date, date) is
  'Rentabilidad R1: la ÚNICA definición de la huella de una intención de contrato. R4 la recalcula en la puerta del alta: si no coincide con la de la autorización, la autorización no aplica.';

create or replace function private.vencer_solicitudes_tasa(p_solicitud_id uuid default null)
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
  v_n integer;
begin
  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  update crm.solicitudes_tasa s
     set estado = 'vencida'
   where s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
     and s.vence_en < statement_timestamp()
     and (p_solicitud_id is null or s.id = p_solicitud_id);
  get diagnostics v_n = row_count;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return v_n;
end;
$function$;
revoke all on function private.vencer_solicitudes_tasa(uuid) from public, anon, authenticated, service_role;
comment on function private.vencer_solicitudes_tasa(uuid) is 'Rentabilidad R1: caduca (estado vencida) las solicitudes vivas con vence_en pasado: TODAS al pedir (barrido global), solo la fila objetivo al resolver/responder (auditor m4: la auditoría atribuye el sello a quien entró). Sin cron.';

-- 3.a El analista PIDE una tasa superior a la base.
create or replace function crm.solicitar_tasa_fn(p_solicitud jsonb)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_cliente uuid; v_cat text; v_origen uuid; v_pc uuid;
  v_capital numeric; v_moneda text; v_mod text; v_ti text; v_fi date; v_fv date;
  v_tasa numeric; v_motivo text;
  v_res jsonb; v_base numeric; v_tope numeric; v_dias integer; v_pol_id uuid;
  v_huella text; v_viva record; v_fila crm.solicitudes_tasa;
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
begin
  -- La AUTORIDAD se pregunta antes de mirar el JSON (auditor n2): un no autorizado muere en el 42501 uniforme sin
  -- distinguir «formato inválido»; el cliente (activo, rol cliente) se comprueba justo después de leerlo.
  if v_uid is null or not private.puede_registrar_ventas() then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if p_solicitud is null or jsonb_typeof(p_solicitud) <> 'object' then
    raise exception 'Faltan los datos de la solicitud' using errcode = '22023';
  end if;
  begin
    v_cliente := (p_solicitud ->> 'cliente_id')::uuid;
    v_cat     := p_solicitud ->> 'categoria';
    v_origen  := (p_solicitud ->> 'contrato_origen_id')::uuid;
    v_pc      := (p_solicitud ->> 'producto_condicion_id')::uuid;
    v_capital := (p_solicitud ->> 'capital')::numeric;
    v_moneda  := p_solicitud ->> 'moneda';
    v_mod     := p_solicitud ->> 'modalidad';
    v_ti      := p_solicitud ->> 'tipo_interes';
    v_fi      := (p_solicitud ->> 'fecha_inicio')::date;
    v_fv      := (p_solicitud ->> 'fecha_vencimiento')::date;
    v_tasa    := round((p_solicitud ->> 'tasa_solicitada')::numeric, 2);   -- misma escala que contratos.tasa_anual (auditor m5)
    v_motivo  := btrim(p_solicitud ->> 'motivo');
  exception when others then
    raise exception 'Datos de la solicitud inválidos' using errcode = '22023';
  end;
  if not private.puede_operar_tasa_cliente(v_cliente) then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if v_capital is null or v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000' using errcode = '22023';
  end if;
  if v_moneda is null or v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;
  if v_mod is null or v_mod not in ('mensual', 'trimestral', 'semestral', 'anual')
     or v_ti is null or v_ti not in ('simple', 'compuesto') then
    raise exception 'Modalidad o tipo de interés inválidos' using errcode = '22023';
  end if;
  if v_fi is null or v_fv is null or v_fv <= v_fi then
    raise exception 'El plazo del contrato es inválido' using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 500 then
    raise exception 'Escribe el motivo comercial (entre 5 y 500 caracteres)' using errcode = '22023';
  end if;
  if v_tasa is null or v_tasa <= 0 then
    raise exception 'La tasa solicitada es inválida' using errcode = '22023';
  end if;

  perform private.vencer_solicitudes_tasa();
  -- EL NÚCLEO decide la base y la regla; esta puerta no calcula tasa.
  v_res := private.resolver_tasa(v_cliente, v_cat, v_origen, statement_timestamp());
  v_base := (v_res ->> 'tasa_base')::numeric;
  v_tope := (v_res #>> '{politica,tope_tecnico}')::numeric;
  v_dias := (v_res #>> '{politica,vigencia_solicitud_dias}')::integer;
  v_pol_id := (v_res #>> '{politica,id}')::uuid;
  if v_tasa <= v_base then
    raise exception 'La excepción debe ser superior a la tasa base de % %%', rtrim(rtrim(to_char(v_base, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;
  if v_tasa > v_tope then
    raise exception 'La tasa solicitada supera el tope técnico de % %%', rtrim(rtrim(to_char(v_tope, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;

  v_huella := private.huella_solicitud_tasa(v_cliente, v_cat, v_origen, v_pc, v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv);
  perform pg_advisory_xact_lock(hashtext('crm.solicitudes_tasa'), hashtext(v_huella));
  select s.id, s.estado, s.solicitada_por into v_viva from crm.solicitudes_tasa s
   where s.huella = v_huella
     and s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
   limit 1;
  if v_viva.id is not null then
    raise exception 'Ya hay una solicitud viva para este contrato (estado «%»)', v_viva.estado
      using errcode = 'P0409',
            detail = jsonb_build_object('solicitud_id', v_viva.id, 'estado', v_viva.estado, 'solicitada_por', v_viva.solicitada_por,
                                        'propia', v_viva.solicitada_por = v_uid)::text;
  end if;

  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  insert into crm.solicitudes_tasa (
    politica_id, cliente_id, categoria, contrato_origen_id, contrato_origen_numero, producto_condicion_id,
    capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, huella,
    tasa_base, regla_base, contratos_previos, prioridad_bandeja, tasa_solicitada, motivo,
    estado, solicitada_por, solicitada_en, vence_en
  ) values (
    v_pol_id, v_cliente, v_cat, v_origen, v_res #>> '{contrato_origen,numero_contrato}', v_pc,
    v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv, v_huella,
    v_base, v_res ->> 'regla', (v_res ->> 'contratos_previos')::integer, (v_res ->> 'prioridad_bandeja')::boolean, v_tasa, v_motivo,
    'pendiente', v_uid, statement_timestamp(), statement_timestamp() + make_interval(days => v_dias)
  ) returning * into v_fila;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return to_jsonb(v_fila) || jsonb_build_object('ok', true, 'resolucion', v_res);
end;
$function$;
revoke all on function crm.solicitar_tasa_fn(jsonb) from public, anon, service_role;
grant execute on function crm.solicitar_tasa_fn(jsonb) to authenticated;
comment on function crm.solicitar_tasa_fn(jsonb) is
  'Rentabilidad R1: el analista pide una tasa SUPERIOR a la base para un contrato en intención {cliente_id, categoria, contrato_origen_id?, producto_condicion_id?, capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, tasa_solicitada, motivo}. Autoridad del alta + cliente en ámbito (42501); base y regla del núcleo; base < tasa <= tope técnico (22023); una viva por huella (P0409). Devuelve la solicitud + resolucion.';

-- 3.b Gerencia RESUELVE: aprobar | rechazar | aprobar_hasta (D6). Nunca quien pidió (D3).
create or replace function crm.resolver_solicitud_tasa_fn(
  p_solicitud_id uuid,
  p_decision text,
  p_tasa_maxima numeric default null,
  p_motivo text default null
)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_s crm.solicitudes_tasa;
  v_estado text; v_tope numeric;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia resuelve una solicitud de tasa' using errcode = '42501';
  end if;
  if p_solicitud_id is null then
    raise exception 'La solicitud es obligatoria' using errcode = '22023';
  end if;
  if p_decision is null or p_decision not in ('aprobar', 'rechazar', 'aprobar_hasta') then
    raise exception 'Decisión inválida: aprobar, rechazar o aprobar_hasta' using errcode = '22023';
  end if;
  if v_motivo is not null and length(v_motivo) > 500 then
    raise exception 'El motivo no puede superar 500 caracteres' using errcode = '22023';
  end if;
  perform private.vencer_solicitudes_tasa(p_solicitud_id);
  select * into v_s from crm.solicitudes_tasa s where s.id = p_solicitud_id for update;
  if v_s.id is null then
    raise exception 'Solicitud no encontrada' using errcode = 'P0002';
  end if;
  if v_s.solicitada_por = v_uid then
    raise exception 'Quien solicita no resuelve su propia solicitud' using errcode = '42501';
  end if;
  -- Una viva con vence_en pasado ES vencida aunque la fila aún diga otra cosa: el sello «vencida» lo escribe
  -- private.vencer_solicitudes_tasa en la siguiente llamada que COMMITEA (esta lanza y revierte). Quien lea la tabla
  -- debe mirar también vence_en.
  if v_s.estado <> 'pendiente' or v_s.vence_en < statement_timestamp() then
    raise exception 'La solicitud ya no está pendiente (estado «%»)',
      case when v_s.estado = 'pendiente' then 'vencida' else v_s.estado end using errcode = 'P0409';
  end if;

  if p_decision = 'rechazar' then
    v_estado := 'rechazada'; v_tope := null;
  elsif p_decision = 'aprobar' then
    v_estado := 'aprobada'; v_tope := v_s.tasa_solicitada;
  else
    if p_tasa_maxima is null then
      raise exception 'Indica hasta qué tasa apruebas' using errcode = '22023';
    end if;
    p_tasa_maxima := round(p_tasa_maxima, 2);   -- misma escala que contratos.tasa_anual (auditor m5)
    if p_tasa_maxima <= v_s.tasa_base then
      raise exception 'El tope debe superar la tasa base de % %% (la excepción solo eleva)', rtrim(rtrim(to_char(v_s.tasa_base, 'FM999990.99'), '0'), '.') using errcode = '22023';
    end if;
    if p_tasa_maxima > v_s.tasa_solicitada then
      raise exception 'El tope no puede superar la tasa pedida de % %%', rtrim(rtrim(to_char(v_s.tasa_solicitada, 'FM999990.99'), '0'), '.') using errcode = '22023';
    end if;
    if p_tasa_maxima = v_s.tasa_solicitada then
      v_estado := 'aprobada'; v_tope := v_s.tasa_solicitada;      -- «hasta lo pedido» es aprobar tal cual
    else
      v_estado := 'aprobada_con_tope'; v_tope := p_tasa_maxima;
    end if;
  end if;

  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  update crm.solicitudes_tasa s
     set estado = v_estado, tasa_maxima_autorizada = v_tope, motivo_resolucion = v_motivo,
         resuelta_por = v_uid, resuelta_en = statement_timestamp()
   where s.id = p_solicitud_id
   returning * into v_s;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return to_jsonb(v_s) || jsonb_build_object('ok', true);
end;
$function$;
revoke all on function crm.resolver_solicitud_tasa_fn(uuid, text, numeric, text) from public, anon, service_role;
grant execute on function crm.resolver_solicitud_tasa_fn(uuid, text, numeric, text) to authenticated;
comment on function crm.resolver_solicitud_tasa_fn(uuid, text, numeric, text) is
  'Rentabilidad R1: Gerencia (42501 si no; nunca quien pidió, D3) resuelve una solicitud PENDIENTE (P0409 si no): aprobar (tasa autorizada = pedida), rechazar, o aprobar_hasta X con base < X <= pedida (D6; X = pedida equivale a aprobar). Un clic.';

-- 3.c El analista RESPONDE a un tope: acepta y sigue, o declina.
create or replace function crm.responder_tope_tasa_fn(
  p_solicitud_id uuid,
  p_acepta boolean,
  p_motivo text default null
)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_s crm.solicitudes_tasa;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
begin
  if v_uid is null or not private.puede_registrar_ventas() then
    raise exception 'Solicitud no encontrada o fuera de tu ámbito' using errcode = '42501';
  end if;
  if p_solicitud_id is null or p_acepta is null then
    raise exception 'La solicitud y la respuesta son obligatorias' using errcode = '22023';
  end if;
  if v_motivo is not null and length(v_motivo) > 500 then
    raise exception 'El motivo no puede superar 500 caracteres' using errcode = '22023';
  end if;
  perform private.vencer_solicitudes_tasa(p_solicitud_id);
  select * into v_s from crm.solicitudes_tasa s where s.id = p_solicitud_id for update;
  if v_s.id is null or v_s.solicitada_por <> v_uid then
    -- Solo quien pidió responde (ni Gerencia en su nombre); ajena o inexistente responden igual.
    raise exception 'Solicitud no encontrada o fuera de tu ámbito' using errcode = '42501';
  end if;
  if v_s.estado <> 'aprobada_con_tope' or v_s.vence_en < statement_timestamp() then
    raise exception 'Solo se responde a una autorización con tope vigente (estado «%»)',
      case when v_s.estado = 'aprobada_con_tope' then 'vencida' else v_s.estado end using errcode = 'P0409';
  end if;
  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  update crm.solicitudes_tasa s
     set estado = case when p_acepta then 'aceptada_por_analista' else 'declinada_por_analista' end,
         respondida_por_analista_en = statement_timestamp(), motivo_analista = v_motivo
   where s.id = p_solicitud_id
   returning * into v_s;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return to_jsonb(v_s) || jsonb_build_object('ok', true);
end;
$function$;
revoke all on function crm.responder_tope_tasa_fn(uuid, boolean, text) from public, anon, service_role;
grant execute on function crm.responder_tope_tasa_fn(uuid, boolean, text) to authenticated;
comment on function crm.responder_tope_tasa_fn(uuid, boolean, text) is
  'Rentabilidad R1: quien pidió (y solo él/ella) acepta (→ aceptada_por_analista, puede seguir con cualquier tasa entre la base y el tope) o declina (→ declinada_por_analista) una autorización con tope (D6). Ajena/inexistente → 42501; sin tope → P0409.';

-- 3.d Gerencia PUBLICA una revisión de la política.
create or replace function crm.publicar_politica_rentabilidad_fn(p_expected_version integer, p_config jsonb)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_actual integer; v_anterior uuid; v_ultimo timestamptz;
  v_tasa numeric; v_tope numeric; v_dias numeric; v_modo text; v_nota text;
  v_fila crm.politica_rentabilidad;
  v_desde timestamptz := clock_timestamp();
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa publica la política de rentabilidad' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'expected_version inválido' using errcode = '22023';
  end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object'
     or not (p_config ?& array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo'])
     or (p_config - array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo', 'nota']) <> '{}'::jsonb
     or jsonb_typeof(p_config -> 'tasa_base_nueva') is distinct from 'number'
     or jsonb_typeof(p_config -> 'tope_tecnico') is distinct from 'number'
     or jsonb_typeof(p_config -> 'vigencia_solicitud_dias') is distinct from 'number'
     or jsonb_typeof(p_config -> 'modo') is distinct from 'string'
     or (p_config ? 'nota' and jsonb_typeof(p_config -> 'nota') not in ('string', 'null')) then
    raise exception 'Formato de política inválido' using errcode = '22023';
  end if;
  v_tasa := (p_config ->> 'tasa_base_nueva')::numeric;
  v_tope := (p_config ->> 'tope_tecnico')::numeric;
  v_dias := (p_config ->> 'vigencia_solicitud_dias')::numeric;
  v_modo := p_config ->> 'modo';
  v_nota := nullif(btrim(p_config ->> 'nota'), '');
  if v_tasa <= 0 or v_tasa > 50 or v_tope <= 0 or v_tope > 50 or v_tope < v_tasa
     or trunc(v_dias) <> v_dias or v_dias < 1 or v_dias > 30 then
    raise exception 'Política fuera de rango (tasa 0-50, tope >= tasa y <= 50, vigencia 1-30 días)' using errcode = '22023';
  end if;
  if v_modo not in ('observacion', 'enforcement') then
    raise exception 'Modo inválido: observacion o enforcement' using errcode = '22023';
  end if;
  if v_modo = 'enforcement' then
    -- R1/R2: nada lee aún el modo enforcement; publicarlo prometería un bloqueo que no existe. Se habilita en R4.
    raise exception 'El modo enforcement todavía no está construido (llega en R4); publica en observacion' using errcode = '0A000';
  end if;
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'La nota no puede superar 500 caracteres' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('crm.politica_rentabilidad'), 1);
  select p.id, p.version, p.vigente_desde into v_anterior, v_actual, v_ultimo
  from crm.politica_rentabilidad p order by p.version desc limit 1;
  if p_expected_version <> v_actual then
    raise exception 'Conflicto de versión: esperada %, vigente %', p_expected_version, v_actual using errcode = '40001';
  end if;
  if v_desde <= v_ultimo then
    v_desde := v_ultimo + interval '1 millisecond';
  end if;
  insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico,
                                         vigencia_solicitud_dias, modo, nota, publicada_por)
  values (v_actual + 1, v_anterior, v_desde, v_tasa, v_tope, v_dias::integer, v_modo, v_nota, v_uid)
  returning * into v_fila;
  return to_jsonb(v_fila) || jsonb_build_object('ok', true);
end;
$function$;
revoke all on function crm.publicar_politica_rentabilidad_fn(integer, jsonb) from public, anon, service_role;
grant execute on function crm.publicar_politica_rentabilidad_fn(integer, jsonb) to authenticated;
comment on function crm.publicar_politica_rentabilidad_fn(integer, jsonb) is
  'Rentabilidad R1: Gerencia publica una revisión {tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota?} con control optimista por versión (40001). En R1 el modo enforcement se rechaza (0A000).';

-- ---------------------------------------------------------------------------
-- 4. LEDGER DE RENTABILIDAD (append-only) + BACKFILL EXACTO
-- ---------------------------------------------------------------------------
create table crm.ledger_rentabilidad (
  id                  uuid primary key default gen_random_uuid(),
  contrato_id         uuid not null,
  numero_contrato     text not null,
  cliente_id          uuid not null,
  categoria           text check (categoria is null or categoria in ('nuevo', 'renovacion', 'upgrade')),
  contrato_origen_id  uuid,
  politica_id         uuid references crm.politica_rentabilidad(id) on delete restrict,
  solicitud_id        uuid references crm.solicitudes_tasa(id) on delete restrict,
  tasa_base           numeric not null check (tasa_base > 0 and tasa_base <= 50),
  tasa_final          numeric not null check (tasa_final > 0 and tasa_final <= 50),
  tasa_recibida       numeric check (tasa_recibida is null or (tasa_recibida > 0 and tasa_recibida <= 50)),
  regla               text not null check (regla in ('primera_inversion', 'heredada_renovacion', 'heredada_upgrade', 'historica_legacy', 'sin_regla')),
  origen              text not null check (origen in ('backfill_legacy', 'observacion', 'enforcement')),
  divergente          boolean not null generated always as (tasa_final <> tasa_base) stored,
  actor_id            uuid,
  registrado_en       timestamptz not null default statement_timestamp(),
  detalle             jsonb not null default '{}'::jsonb check (jsonb_typeof(detalle) = 'object')
);
alter table crm.ledger_rentabilidad enable row level security;
comment on table crm.ledger_rentabilidad is
  'Rentabilidad R1. Libro APPEND-ONLY de la tasa de cada contrato: base (lo que dice la política/núcleo), final (lo que quedó en el contrato), recibida (lo que mandó el navegador), regla y origen. Los contratos anteriores al 06/09/2026 entran como historica_legacy (base = final; su historia no se reescribe). R2 escribe origen=observacion; R4 origen=enforcement. Sin FK a public.contratos a propósito: la eliminación de un contrato no borra su historia.';
comment on column crm.ledger_rentabilidad.divergente is 'true cuando la tasa final no coincide con la base: en observación (R2) es el margen cedido sin autorización o con ella (ver solicitud_id).';

create or replace function private.trg_ledger_rentabilidad_append_only()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception 'El ledger de rentabilidad es append-only: no se edita ni se borra' using errcode = 'P0409';
end;
$function$;
revoke all on function private.trg_ledger_rentabilidad_append_only() from public, anon, authenticated, service_role;
create trigger trg_ledger_rentabilidad_00_append_only
before update or delete on crm.ledger_rentabilidad
for each row execute function private.trg_ledger_rentabilidad_append_only();

create index ledger_rentabilidad_contrato_idx on crm.ledger_rentabilidad (contrato_id, registrado_en desc);
create index ledger_rentabilidad_cliente_idx on crm.ledger_rentabilidad (cliente_id);
create index ledger_rentabilidad_registrado_idx on crm.ledger_rentabilidad (registrado_en desc);
create unique index ledger_rentabilidad_una_legacy_por_contrato on crm.ledger_rentabilidad (contrato_id) where origen = 'backfill_legacy';

revoke all on table crm.ledger_rentabilidad from public, anon, authenticated, service_role;
grant select on table crm.ledger_rentabilidad to authenticated, service_role;
-- Quién lee el ledger: Gerencia y Directorio todo; el resto, los contratos de los clientes de su ámbito.
create policy ledger_rentabilidad_select on crm.ledger_rentabilidad for select to authenticated
using (
  (select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) = 'gerencia'
  or (select private.puede_consultar_cliente_ficha(cliente_id))
);

-- BACKFILL: todos los contratos de hoy, tal cual (base = final = tasa_anual), sin tocar public.contratos.
insert into crm.ledger_rentabilidad (
  contrato_id, numero_contrato, cliente_id, categoria, contrato_origen_id, politica_id, solicitud_id,
  tasa_base, tasa_final, tasa_recibida, regla, origen, actor_id, registrado_en, detalle
)
select c.id, c.numero_contrato, c.cliente_id, c.categoria, oc.contrato_origen_id, null, null,
       c.tasa_anual, c.tasa_anual, c.tasa_anual, 'historica_legacy', 'backfill_legacy', null, statement_timestamp(),
       jsonb_build_object('estado', c.estado, 'es_demo', c.es_demo, 'creado_en', c.creado_en,
                          'fecha_cierre_comercial', c.fecha_cierre_comercial, 'operacion_cartera', oc.tipo,
                          'backfill', 'R1 2026-09-06')
from public.contratos c
left join crm.operaciones_cartera oc on oc.contrato_nuevo_id = c.id;

-- La auditoría del ledger se monta DESPUÉS del backfill: las filas legacy ya son la propia bitácora de la carga.
create trigger trg_audit_ledger_rentabilidad
after insert on crm.ledger_rentabilidad
for each row execute function private.log_audit_crm();

-- ---------------------------------------------------------------------------
-- 5. POSTFLIGHT: nada de lo vivo cambió; lo nuevo quedó como se declara.
-- ---------------------------------------------------------------------------
do $post$
declare
  v_n_contratos bigint; v_n_ledger bigint;
  v_h_contratos text; v_h_ledger text;
  v_s_contratos numeric; v_s_ledger numeric;
  v_f text;
begin
  -- 5.a Las cinco puertas de escritura, byte a byte como al empezar.
  for v_f in select firma from _r1_puertas g
             where g.h is distinct from (select md5(p.prosrc) from pg_proc p where p.oid = g.fnoid) loop
    raise exception 'POSTFLIGHT R1: la puerta % cambió durante la migración', v_f;
  end loop;
  -- 5.b Backfill exacto: mismo conteo, misma suma, misma huella (id, tasa).
  select count(*), sum(tasa_anual), md5(string_agg(id::text || ':' || tasa_anual::text, ',' order by id))
    into v_n_contratos, v_s_contratos, v_h_contratos from public.contratos;
  select count(*), sum(tasa_final), md5(string_agg(contrato_id::text || ':' || tasa_final::text, ',' order by contrato_id))
    into v_n_ledger, v_s_ledger, v_h_ledger from crm.ledger_rentabilidad where origen = 'backfill_legacy';
  if v_n_contratos <> v_n_ledger or v_s_contratos is distinct from v_s_ledger or v_h_contratos is distinct from v_h_ledger then
    raise exception 'POSTFLIGHT R1: el backfill no es exacto (contratos % / ledger %, sumas % / %, huellas % / %)',
      v_n_contratos, v_n_ledger, v_s_contratos, v_s_ledger, left(v_h_contratos, 8), left(v_h_ledger, 8);
  end if;
  if exists (select 1 from crm.ledger_rentabilidad where origen = 'backfill_legacy' and (divergente or tasa_base <> tasa_final or regla <> 'historica_legacy')) then
    raise exception 'POSTFLIGHT R1: una fila legacy quedó divergente o con otra regla';
  end if;
  -- 5.c Política v1 en observación.
  if (select count(*) from crm.politica_rentabilidad) <> 1
     or not exists (select 1 from crm.politica_rentabilidad where version = 1 and tasa_base_nueva = 15 and tope_tecnico = 50 and vigencia_solicitud_dias = 7 and modo = 'observacion') then
    raise exception 'POSTFLIGHT R1: la política v1 no es 15 / 50 / 7 días / observacion';
  end if;
  -- 5.d RLS encendida y una policy SELECT (y solo SELECT) por tabla nueva.
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'crm' and c.relname in ('politica_rentabilidad', 'solicitudes_tasa', 'ledger_rentabilidad') and not c.relrowsecurity) then
    raise exception 'POSTFLIGHT R1: una tabla nueva quedó sin RLS';
  end if;
  if (select count(*) from pg_policies where schemaname = 'crm' and tablename in ('politica_rentabilidad', 'solicitudes_tasa', 'ledger_rentabilidad')) <> 3
     or exists (select 1 from pg_policies where schemaname = 'crm' and tablename in ('politica_rentabilidad', 'solicitudes_tasa', 'ledger_rentabilidad') and cmd <> 'SELECT') then
    raise exception 'POSTFLIGHT R1: las policies no son exactamente una SELECT por tabla';
  end if;
  -- 5.e Privilegios de tabla: solo SELECT para authenticated/service_role; nada para anon/PUBLIC.
  if has_table_privilege('anon', 'crm.solicitudes_tasa', 'SELECT') or has_table_privilege('authenticated', 'crm.solicitudes_tasa', 'INSERT')
     or has_table_privilege('authenticated', 'crm.solicitudes_tasa', 'UPDATE') or has_table_privilege('authenticated', 'crm.solicitudes_tasa', 'DELETE')
     or has_table_privilege('authenticated', 'crm.ledger_rentabilidad', 'INSERT') or has_table_privilege('authenticated', 'crm.politica_rentabilidad', 'INSERT')
     or has_table_privilege('service_role', 'crm.ledger_rentabilidad', 'UPDATE') or has_table_privilege('service_role', 'crm.solicitudes_tasa', 'INSERT')
     or not has_table_privilege('authenticated', 'crm.solicitudes_tasa', 'SELECT') then
    raise exception 'POSTFLIGHT R1: los privilegios de tabla no son «solo SELECT para authenticated/service_role»';
  end if;
  -- 5.f Puertas crm.*: DEFINER de postgres, search_path vacío, EXECUTE solo authenticated (ni anon, ni service_role, ni PUBLIC).
  for v_f in select unnest(array['crm.resolver_tasa_fn(uuid,text,uuid)', 'crm.solicitar_tasa_fn(jsonb)',
                                 'crm.resolver_solicitud_tasa_fn(uuid,text,numeric,text)', 'crm.responder_tope_tasa_fn(uuid,boolean,text)',
                                 'crm.publicar_politica_rentabilidad_fn(integer,jsonb)']) loop
    if not exists (select 1 from pg_proc p where p.oid = v_f::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']) then
      raise exception 'POSTFLIGHT R1: % no es DEFINER de postgres con search_path vacío', v_f;
    end if;
    if not has_function_privilege('authenticated', v_f, 'EXECUTE') or has_function_privilege('anon', v_f, 'EXECUTE')
       or has_function_privilege('service_role', v_f, 'EXECUTE')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f::regprocedure and a.grantee = 0) then
      raise exception 'POSTFLIGHT R1: los grants de % no son «solo authenticated»', v_f;
    end if;
  end loop;
  -- 5.g Helpers private.*: sin EXECUTE para la API ni PUBLIC.
  for v_f in select unnest(array['private.resolver_tasa(uuid,text,uuid,timestamptz)', 'private.politica_rentabilidad_vigente(timestamptz)',
                                 'private.puede_operar_tasa_cliente(uuid)', 'private.huella_solicitud_tasa(uuid,text,uuid,uuid,numeric,text,text,text,date,date)',
                                 'private.vencer_solicitudes_tasa(uuid)', 'private.trg_solicitudes_tasa_solo_por_puerta()', 'private.trg_ledger_rentabilidad_append_only()']) loop
    if has_function_privilege('authenticated', v_f, 'EXECUTE') or has_function_privilege('anon', v_f, 'EXECUTE')
       or has_function_privilege('service_role', v_f, 'EXECUTE')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f::regprocedure and a.grantee = 0) then
      raise exception 'POSTFLIGHT R1: % tiene EXECUTE para la API o PUBLIC', v_f;
    end if;
  end loop;
  -- 5.h Triggers montados y habilitados.
  if (select count(*) from pg_trigger t where t.tgrelid in ('crm.politica_rentabilidad'::regclass, 'crm.solicitudes_tasa'::regclass, 'crm.ledger_rentabilidad'::regclass)
        and not t.tgisinternal and t.tgenabled = 'O'
        and t.tgname in ('trg_politica_rentabilidad_inmutable', 'trg_audit_politica_rentabilidad', 'trg_solicitudes_tasa_00_solo_por_puerta',
                         'trg_audit_solicitudes_tasa', 'trg_ledger_rentabilidad_00_append_only', 'trg_audit_ledger_rentabilidad')) <> 6 then
    raise exception 'POSTFLIGHT R1: faltan triggers (inmutable, auditoría, solo-por-puerta, append-only)';
  end if;
  raise notice 'RENTABILIDAD R1 OK: política v1 (15%% · observación), % contratos en el ledger como historica_legacy, núcleo private.resolver_tasa y 5 puertas crm.*; las 5 puertas de escritura de contratos intactas.', v_n_ledger;
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260906170000' and md5(statements[1]) = '758b26b21a84cb27990e8d93de6ae6e8') then
    raise exception 'REGISTRO R1: la versión no quedó registrada con el contenido esperado';
  end if;
  raise notice 'REGISTRO RENTABILIDAD R1 OK (20260906170000, md5 758b26b2…)';
end
$post$;
commit;
