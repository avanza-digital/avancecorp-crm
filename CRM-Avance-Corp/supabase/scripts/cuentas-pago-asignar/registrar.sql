-- REGISTRO en supabase_migrations.schema_migrations de 20261002005004_crm_asignar_cuenta_pago.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 beea048bf51318ac6416872310c8e7f3).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_asignar_cuenta_pago_registro'));
do $chk$
begin
  if (
    to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is not null
    and to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null
    and (select true from pg_catalog.pg_proc p where p.oid = to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') and md5(p.prosrc) = '57297bc7f18279578c2f16f6aaad7247') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261002005004 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261002005004' and (coalesce(name, '') <> 'crm_asignar_cuenta_pago' or statements is distinct from array[$mig$-- Cuentas de pago · ASIGNAR la cuenta de pago a un contrato que no tiene ninguna (02/10/2026).
--
-- Contexto: quedaron 22 contratos viejos sin vínculo en crm.contrato_cuentas_pago que NO se pueden
-- vincular solos (el cliente tiene dos cuentas, o solo en la otra moneda, o ninguna): hace falta
-- que una persona diga en cuál cobra. Hasta hoy no existía ninguna operación para eso:
-- crm.crear_contrato_con_cuenta solo vincula al dar de alta y crm.cambiar_cuenta_pago_contratos
-- (F3) rechaza los contratos sin cuenta, porque su historial exige una cuenta ANTERIOR y el correo
-- del cliente. Decisión de Miguel (01/10/2026): «solo quiero que pueda marcar los pagos»; botón
-- «Asignar cuenta» en Pagos; solo administración; con motivo obligatorio y SIN adjunto.
--
-- Qué hace:
--   1. crm.contrato_cuenta_pago_asignaciones: constancia inmutable de cada asignación (quién,
--      cuándo, contrato, cuenta y motivo). Mismas reglas que las constancias de F3: sin claves
--      foráneas (sobrevive a las eliminaciones auditadas), RLS sin políticas y sin permisos para
--      la API, no se borra ni se modifica, y con bitácora.
--   2. crm.asignar_cuenta_pago_contrato (puerta INVOKER) →
--      private.asignar_cuenta_pago_contrato_autorizado (núcleo DEFINER): PRIMERA cuenta de pago de
--      un contrato. Solo admin o superadmin vigente (la compuerta de F3,
--      private.admin_banca_vigente); contrato abierto (activo o vencido) y SIN cuenta de pago;
--      cuenta VIGENTE, del mismo cliente y de la misma moneda; motivo de 5 a 500 caracteres;
--      idempotente por solicitud. El vínculo queda con creado_por = quien asigna, y la bitácora
--      de siempre (trg_audit_contrato_cuentas_pago) lo registra con su autor.
--
-- Lo que NO hace: no cambia una cuenta ya asignada (eso sigue siendo F3, con el correo del
-- cliente), no registra cuentas nuevas, no convierte moneda, no toca el bloqueo de pagos ni el
-- alta de contratos, y no sella las cuotas que el contrato ya tenía pagadas. No avisa al cliente:
-- no es un cambio pedido por él, es completar una instrucción que el contrato no tenía.
--
-- Candados, en el orden del cambio de cuenta de F3 (cuenta → contrato → vínculo): la cuenta FOR
-- SHARE (un retiro en curso termina antes y aquí se ve), el contrato FOR SHARE (un pago, que lo
-- bloquea FOR UPDATE, espera y al seguir ya encuentra el vínculo) y la unicidad del vínculo por
-- contrato, que deja pasar a una sola de dos asignaciones simultáneas.
--
-- De public solo LEE y bloquea FOR SHARE la fila del contrato. No crea ni cambia triggers,
-- políticas ni tablas de public. OK de Miguel: 01/10/2026.
-- No depende de 20261001233019 (motivo del bloqueo y carga del rezago) ni la modifica.
-- SÍ depende de piezas de F3 (20260926204051): la compuerta private.admin_banca_vigente y el
-- candado private.trg_registro_cuenta_pago_no_borrar. Con esta migración aplicada, la reversa de
-- F3 ya no puede quitar ese candado (se niega; primero habría que revertir esta).
-- Excepción anotada al estándar de tablas: sin negocio_id ni updated_at, como las constancias de
-- F3 y F4 del mismo módulo (una fila inmutable no tiene «última modificación»).
-- Reversión: ../scripts/cuentas-pago-asignar/reversa.sql (si ya hay asignaciones registradas no
-- borra nada: solo cierra la puerta).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null
     or pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is not null
     or pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is not null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is not null then
    raise exception 'ASIGNAR PREFLIGHT: ya aplicada (los objetos existen); no se sobrescriben';
  end if;
  if pg_catalog.to_regclass('crm.contrato_cuentas_pago') is null
     or pg_catalog.to_regclass('crm.cuentas_bancarias') is null
     or pg_catalog.to_regclass('public.contratos') is null
     or pg_catalog.to_regprocedure('auth.uid()') is null
     or pg_catalog.to_regprocedure('private.log_audit_crm()') is null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_inmutable()') is null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()') is null then
    raise exception 'ASIGNAR PREFLIGHT: faltan dependencias';
  end if;
  -- Las piezas de las que depende, por identidad: la compuerta de F3, el candado de coherencia
  -- del vínculo (cuenta del mismo cliente y moneda) y el candado «no se borra» de las constancias.
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = pg_catalog.to_regprocedure('private.admin_banca_vigente(uuid)'))
       is distinct from '810dce30e37d1da9d913ef48ab6a4aa1'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()'))
       is distinct from '7e946a5af78a827c18ee5b218896f24c'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_registro_cuenta_pago_no_borrar()'))
       is distinct from 'e95919db53c44ff1fe6632c346f27a06' then
    raise exception 'ASIGNAR PREFLIGHT: la compuerta de administración o los candados del vínculo no son los esperados; no se toca';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass
        and (t.tgname, t.tgfoid) in (
          ('trg_contrato_cuenta_pago_coherente', 'private.trg_contrato_cuenta_pago_coherente()'::regprocedure::oid),
          ('trg_audit_contrato_cuentas_pago', 'private.log_audit_crm()'::regprocedure::oid),
          ('trg_contrato_cuenta_pago_00_inmutable', 'private.trg_contrato_cuenta_pago_inmutable()'::regprocedure::oid))
        and t.tgenabled = 'O') <> 3 then
    raise exception 'ASIGNAR PREFLIGHT: faltan los triggers de coherencia, bitácora o candado del vínculo';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'public.contratos'::regclass and not a.attisdropped
        and a.attname in ('id', 'numero_contrato', 'cliente_id', 'moneda', 'estado')) <> 5
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.cuentas_bancarias'::regclass and not a.attisdropped
           and a.attname in ('id', 'cliente_id', 'moneda', 'banco', 'activa')) <> 5
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.contrato_cuentas_pago'::regclass and not a.attisdropped
           and a.attname in ('id', 'contrato_id', 'cuenta_bancaria_id', 'creado_por')) <> 4 then
    raise exception 'ASIGNAR PREFLIGHT: alguna tabla no tiene las columnas esperadas';
  end if;
  -- Un contrato solo puede tener UN vínculo: de eso depende que dos asignaciones a la vez no
  -- queden las dos.
  if not exists (
    select 1 from pg_catalog.pg_index i
    where i.indrelid = 'crm.contrato_cuentas_pago'::regclass and i.indisunique and i.indpred is null
      and i.indisvalid and i.indimmediate and i.indnatts = 1
      and i.indkey[0] = (select a.attnum from pg_catalog.pg_attribute a
                         where a.attrelid = 'crm.contrato_cuentas_pago'::regclass and a.attname = 'contrato_id')
  ) then
    raise exception 'ASIGNAR PREFLIGHT: el vínculo ya no es único por contrato';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE')
     or not pg_catalog.has_schema_privilege('authenticated', 'crm', 'USAGE') then
    raise exception 'ASIGNAR PREFLIGHT: authenticated necesita USAGE sobre crm y private para la puerta INVOKER';
  end if;
  -- El núcleo (DEFINER, dueño = quien aplica) lee contratos, cuentas y vínculos sin RLS.
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'ASIGNAR PREFLIGHT: el dueño de las funciones debe tener bypassrls';
  end if;
end;
$precondicion$;

-- ── 1. Constancia de cada asignación ─────────────────────────────────────────────────────────
create table crm.contrato_cuenta_pago_asignaciones (
  id                  uuid primary key default gen_random_uuid(),
  solicitud_id        uuid not null constraint contrato_cuenta_pago_asignaciones_solicitud_uq unique,
  contrato_id         uuid not null,
  cliente_id          uuid not null,
  cuenta_bancaria_id  uuid not null,
  vinculo_id          uuid not null,
  motivo              text not null
                      constraint contrato_cuenta_pago_asignaciones_motivo_valido
                      check (motivo = regexp_replace(motivo, '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g')
                             and length(regexp_replace(motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) >= 5
                             and length(motivo) <= 500),
  asignado_por        uuid not null,
  asignado_en         timestamptz not null default now()
);
alter table crm.contrato_cuenta_pago_asignaciones enable row level security;
revoke all on crm.contrato_cuenta_pago_asignaciones from public, anon, authenticated, service_role;

-- Candados de la constancia: no se borra (el mismo de las constancias de F3) y no se modifica.
create function private.trg_contrato_cuenta_pago_asignaciones_inmutable()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using errcode = '22023',
    message = 'El registro de asignaciones de cuenta de pago no se modifica ni se vacía';
end;
$function$;
revoke all on function private.trg_contrato_cuenta_pago_asignaciones_inmutable() from public, anon, authenticated, service_role;

create trigger trg_contrato_cuenta_pago_asignaciones_00_no_borrar
  before delete on crm.contrato_cuenta_pago_asignaciones
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();
create trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable
  before update on crm.contrato_cuenta_pago_asignaciones
  for each row execute function private.trg_contrato_cuenta_pago_asignaciones_inmutable();
create trigger trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar
  before truncate on crm.contrato_cuenta_pago_asignaciones
  for each statement execute function private.trg_contrato_cuenta_pago_asignaciones_inmutable();
create trigger trg_audit_contrato_cuenta_pago_asignaciones
  after insert or delete or update on crm.contrato_cuenta_pago_asignaciones
  for each row execute function private.log_audit_crm();

-- ── 2. Operación: asignar la primera cuenta de pago (núcleo DEFINER + puerta INVOKER) ────────
create function private.asignar_cuenta_pago_contrato_autorizado(
  p_solicitud_id uuid, p_contrato_id uuid, p_cuenta_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_motivo text := pg_catalog.regexp_replace(coalesce(p_motivo, ''), '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g');
  v_previa crm.contrato_cuenta_pago_asignaciones%rowtype;
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_ct record;
  v_vinculo uuid;
  v_esquema text;
  v_tabla text;
begin
  if not coalesce(private.admin_banca_vigente(v_actor), false) then
    raise exception using errcode = '42501',
      message = 'Solo administración puede asignar la cuenta de pago';
  end if;
  if p_solicitud_id is null or p_contrato_id is null or p_cuenta_id is null then
    raise exception using errcode = '22023', message = 'Faltan datos de la asignación';
  end if;
  if pg_catalog.length(pg_catalog.regexp_replace(v_motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) < 5
     or pg_catalog.length(v_motivo) > 500 then
    raise exception using errcode = '22023', message = 'Escribe el motivo de la asignación (5 a 500 caracteres)';
  end if;

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con datos
  -- distintos se rechaza.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('asignar-cuenta-pago:' || p_solicitud_id::text, 0));
  select * into v_previa
  from crm.contrato_cuenta_pago_asignaciones a
  where a.solicitud_id = p_solicitud_id;
  if found then
    if v_previa.contrato_id = p_contrato_id and v_previa.cuenta_bancaria_id = p_cuenta_id
       and v_previa.motivo = v_motivo then
      return pg_catalog.jsonb_build_object(
        'solicitud_id', p_solicitud_id, 'ya_aplicada', true,
        'numero_contrato', (select ct.numero_contrato from public.contratos ct where ct.id = v_previa.contrato_id),
        'banco', (select cb.banco from crm.cuentas_bancarias cb where cb.id = v_previa.cuenta_bancaria_id),
        'moneda', (select cb.moneda from crm.cuentas_bancarias cb where cb.id = v_previa.cuenta_bancaria_id),
        'ultimos', (select case when pg_catalog.length(cb.numero_cuenta) >= 8
                                then pg_catalog.right(cb.numero_cuenta, 4) end
                    from crm.cuentas_bancarias cb
                    where cb.id = v_previa.cuenta_bancaria_id));
    end if;
    raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  end if;

  -- Candados en el orden del cambio de cuenta (F3): cuenta → contrato → vínculo.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_id for share;
  if not found then
    raise exception using errcode = '22023', message = 'La cuenta elegida no existe';
  end if;
  select ct.id, ct.cliente_id, ct.moneda, ct.estado, ct.numero_contrato into v_ct
  from public.contratos ct
  where ct.id = p_contrato_id
  for share;
  if not found then
    raise exception using errcode = '22023', message = 'El contrato no existe';
  end if;

  if v_cuenta.cliente_id is distinct from v_ct.cliente_id then
    raise exception using errcode = '22023',
      message = pg_catalog.format('La cuenta elegida no es del cliente del contrato %s', v_ct.numero_contrato);
  end if;
  if v_cuenta.activa is not true then
    raise exception using errcode = '22023', message = 'La cuenta elegida ya no está vigente';
  end if;
  if v_cuenta.moneda is distinct from v_ct.moneda then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s es en %s y la cuenta elegida en %s',
        v_ct.numero_contrato, v_ct.moneda, v_cuenta.moneda);
  end if;
  if v_ct.estado is null or v_ct.estado not in ('activo', 'vencido') then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s está cerrado (%s)', v_ct.numero_contrato, coalesce(v_ct.estado, 'sin estado'));
  end if;
  if exists (select 1 from crm.contrato_cuentas_pago l where l.contrato_id = p_contrato_id) then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»', v_ct.numero_contrato);
  end if;

  -- Dos asignaciones a la vez del mismo contrato: la unicidad del vínculo deja pasar una sola; la
  -- otra espera y recibe este mismo mensaje. El trigger de coherencia vuelve a exigir cliente y
  -- moneda.
  begin
    insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id, creado_por)
    values (p_contrato_id, p_cuenta_id, v_actor)
    returning id into v_vinculo;
  exception when unique_violation then
    get stacked diagnostics v_esquema = schema_name, v_tabla = table_name;
    if v_esquema is distinct from 'crm' or v_tabla is distinct from 'contrato_cuentas_pago' then
      raise;
    end if;
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»', v_ct.numero_contrato);
  end;

  insert into crm.contrato_cuenta_pago_asignaciones
    (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)
  values (p_solicitud_id, p_contrato_id, v_ct.cliente_id, p_cuenta_id, v_vinculo, v_motivo, v_actor);

  return pg_catalog.jsonb_build_object(
    'solicitud_id', p_solicitud_id, 'ya_aplicada', false,
    'numero_contrato', v_ct.numero_contrato, 'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda,
    -- Los 4 últimos solo de un número de 8 o más caracteres: nunca el número entero.
    'ultimos', case when pg_catalog.length(v_cuenta.numero_cuenta) >= 8
                    then pg_catalog.right(v_cuenta.numero_cuenta, 4) end);
end;
$function$;
revoke all on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)
  to authenticated;

create function crm.asignar_cuenta_pago_contrato(
  p_solicitud_id uuid, p_contrato_id uuid, p_cuenta_id uuid, p_motivo text)
returns jsonb
language sql
volatile security invoker
set search_path to ''
as $function$
  select private.asignar_cuenta_pago_contrato_autorizado(p_solicitud_id, p_contrato_id, p_cuenta_id, p_motivo);
$function$;
revoke all on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)
  to authenticated;

-- ── 3. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on table crm.contrato_cuenta_pago_asignaciones is
  'Constancia inmutable de cada asignación de la PRIMERA cuenta de pago a un contrato que no tenía ninguna (02/10/2026): quién, cuándo, a qué cuenta y por qué. No es un cambio pedido por el cliente (eso es crm.contrato_cuenta_pago_cambios). Sin claves foráneas a propósito: sobrevive a contratos, cliente, cuentas y personas. No se borra ni se modifica. DATOS SENSIBLES por referencia.';
comment on column crm.contrato_cuenta_pago_asignaciones.id is 'Identificador de la asignación.';
comment on column crm.contrato_cuenta_pago_asignaciones.solicitud_id is 'Id de la operación (idempotencia): un reintento con la misma solicitud no se aplica dos veces.';
comment on column crm.contrato_cuenta_pago_asignaciones.contrato_id is 'Contrato al que se asignó la cuenta de pago (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.cliente_id is 'Cliente titular del contrato en ese momento (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.cuenta_bancaria_id is 'Cuenta de crm.cuentas_bancarias asignada (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.vinculo_id is 'Fila de crm.contrato_cuentas_pago que creó la asignación (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';
comment on column crm.contrato_cuenta_pago_asignaciones.asignado_por is 'Administrador que asignó (id de perfil, sin FK: sobrevive a la eliminación del usuario).';
comment on column crm.contrato_cuenta_pago_asignaciones.asignado_en is 'Momento de la asignación (hora de la transacción).';
comment on function private.trg_contrato_cuenta_pago_asignaciones_inmutable() is 'Candado de la constancia de asignaciones de cuenta de pago: ninguna fila se modifica y la tabla no se vacía. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) is 'Núcleo de la asignación de la PRIMERA cuenta de pago de un contrato: solo admin vigente (P04); contrato abierto y sin cuenta de pago; cuenta vigente del mismo cliente y moneda; motivo obligatorio; idempotente por solicitud; deja constancia en crm.contrato_cuenta_pago_asignaciones. SECURITY DEFINER porque authenticated no tiene permisos sobre el vínculo, las cuentas ni la constancia.';
comment on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) is 'Puerta (INVOKER) para asignar la primera cuenta de pago a un contrato que no tiene ninguna. La usa Pagos del portal (solo admin). Para cambiar una cuenta ya asignada: crm.cambiar_cuenta_pago_contratos.';

-- ── 4. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  -- Ninguna clave foránea entra ni sale de la constancia: las eliminaciones auditadas de contratos
  -- y de usuarios no ven dependencias nuevas.
  if exists (
    select 1 from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and (c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
           or c.confrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass)
  ) then
    raise exception 'ASIGNAR POSTFLIGHT: la constancia no debe tener claves foráneas';
  end if;
  -- Nadie de la API toca la tabla, y tiene RLS.
  if exists (
    select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
    where pg_catalog.has_table_privilege(r.rol, 'crm.contrato_cuenta_pago_asignaciones',
            'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  ) or not (select t.relrowsecurity from pg_catalog.pg_class t
            where t.oid = 'crm.contrato_cuenta_pago_asignaciones'::regclass) then
    raise exception 'ASIGNAR POSTFLIGHT: la constancia quedó accesible desde la API o sin RLS';
  end if;
  -- Bitácora completa (los tres verbos, por fila, sin condición) y los dos candados, habilitados.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
      and t.tgname = 'trg_audit_contrato_cuenta_pago_asignaciones'
      and t.tgfoid = 'private.log_audit_crm()'::regprocedure
      and t.tgenabled = 'O' and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0 and (t.tgtype & 28) = 28
      and t.tgqual is null and t.tgattr::text = ''
  ) or (select pg_catalog.count(*) from pg_catalog.pg_trigger t
        where t.tgrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
          and t.tgenabled = 'O' and t.tgqual is null and t.tgattr::text = ''
          -- tgtype: fila 1 · antes 2 · borrar 8 · modificar 16 · vaciar 32
          and (t.tgname, t.tgfoid, t.tgtype::integer) in (
            ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
             'private.trg_registro_cuenta_pago_no_borrar()'::regprocedure::oid, 11),
            ('trg_contrato_cuenta_pago_asignaciones_00_inmutable',
             'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure::oid, 19),
            ('trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
             'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure::oid, 34))) <> 3 then
    raise exception 'ASIGNAR POSTFLIGHT: la bitácora o los candados de la constancia no quedaron como se espera';
  end if;
  -- Las dos reglas de la tabla: el motivo y la solicitud única (de ella depende la idempotencia).
  if not exists (
       select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and c.contype = 'c'
         and c.conname = 'contrato_cuenta_pago_asignaciones_motivo_valido' and c.convalidated
         and pg_catalog.pg_get_constraintdef(c.oid) like '%regexp_replace%')
     or not exists (
       select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and c.contype = 'u'
         and c.conname = 'contrato_cuenta_pago_asignaciones_solicitud_uq' and not c.condeferrable) then
    raise exception 'ASIGNAR POSTFLIGHT: faltan las reglas de la constancia (motivo válido o solicitud única)';
  end if;
  -- Forma, cuerpo, EXECUTE exacto (rol NULL = solo su dueño), search_path vacío y comentario.
  for v_f in
    select * from (values
      ('private.trg_contrato_cuenta_pago_asignaciones_inmutable()', null, true, '49bb93b9429aa7b0c168cc8ceb43acfc'),
      ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)', 'authenticated', true, '57297bc7f18279578c2f16f6aaad7247'),
      ('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)', 'authenticated', false, '46e03517fc68ffd79fed6892d1128c2b')
    ) as f(firma, rol, definer, huella)
  loop
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure
                     and pg_catalog.md5(p.prosrc) = v_f.huella
                     and p.prosecdef = v_f.definer and p.provolatile = 'v'
                     and pg_catalog.pg_get_userbyid(p.proowner) = current_user::text) then
      raise exception 'ASIGNAR POSTFLIGHT: cuerpo, DEFINER/INVOKER, volatilidad o dueño inesperados en %', v_f.firma;
    end if;
    if exists (
         select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
         where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
           and a.grantee <> p.proowner
           and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid))
       or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
       or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE'))
       or not exists (select 1 from pg_catalog.pg_proc p
                      where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""'])
       or pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'ASIGNAR POSTFLIGHT: EXECUTE, search_path o comentario inesperados en %', v_f.firma;
    end if;
  end loop;
  -- Toda columna con su comentario.
  if exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and a.attnum > 0 and not a.attisdropped
      and pg_catalog.col_description(a.attrelid, a.attnum) is null
  ) or pg_catalog.obj_description('crm.contrato_cuenta_pago_asignaciones'::regclass, 'pg_class') is null then
    raise exception 'ASIGNAR POSTFLIGHT: falta el comentario de la tabla o de alguna columna';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila (el canal de `db query` no transporta los avisos) y sale del
-- estado real: el núcleo de ESTA migración está puesto y la puerta abierta para authenticated.
select case
         when (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
              = '57297bc7f18279578c2f16f6aaad7247'
          and exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                      where p.oid = pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)')
                        and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::regrole::oid)
         then 'ASIGNAR_CUENTA_PAGO_OK'
       end as resultado;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261002005004 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261002005004', 'crm_asignar_cuenta_pago', array[$mig$-- Cuentas de pago · ASIGNAR la cuenta de pago a un contrato que no tiene ninguna (02/10/2026).
--
-- Contexto: quedaron 22 contratos viejos sin vínculo en crm.contrato_cuentas_pago que NO se pueden
-- vincular solos (el cliente tiene dos cuentas, o solo en la otra moneda, o ninguna): hace falta
-- que una persona diga en cuál cobra. Hasta hoy no existía ninguna operación para eso:
-- crm.crear_contrato_con_cuenta solo vincula al dar de alta y crm.cambiar_cuenta_pago_contratos
-- (F3) rechaza los contratos sin cuenta, porque su historial exige una cuenta ANTERIOR y el correo
-- del cliente. Decisión de Miguel (01/10/2026): «solo quiero que pueda marcar los pagos»; botón
-- «Asignar cuenta» en Pagos; solo administración; con motivo obligatorio y SIN adjunto.
--
-- Qué hace:
--   1. crm.contrato_cuenta_pago_asignaciones: constancia inmutable de cada asignación (quién,
--      cuándo, contrato, cuenta y motivo). Mismas reglas que las constancias de F3: sin claves
--      foráneas (sobrevive a las eliminaciones auditadas), RLS sin políticas y sin permisos para
--      la API, no se borra ni se modifica, y con bitácora.
--   2. crm.asignar_cuenta_pago_contrato (puerta INVOKER) →
--      private.asignar_cuenta_pago_contrato_autorizado (núcleo DEFINER): PRIMERA cuenta de pago de
--      un contrato. Solo admin o superadmin vigente (la compuerta de F3,
--      private.admin_banca_vigente); contrato abierto (activo o vencido) y SIN cuenta de pago;
--      cuenta VIGENTE, del mismo cliente y de la misma moneda; motivo de 5 a 500 caracteres;
--      idempotente por solicitud. El vínculo queda con creado_por = quien asigna, y la bitácora
--      de siempre (trg_audit_contrato_cuentas_pago) lo registra con su autor.
--
-- Lo que NO hace: no cambia una cuenta ya asignada (eso sigue siendo F3, con el correo del
-- cliente), no registra cuentas nuevas, no convierte moneda, no toca el bloqueo de pagos ni el
-- alta de contratos, y no sella las cuotas que el contrato ya tenía pagadas. No avisa al cliente:
-- no es un cambio pedido por él, es completar una instrucción que el contrato no tenía.
--
-- Candados, en el orden del cambio de cuenta de F3 (cuenta → contrato → vínculo): la cuenta FOR
-- SHARE (un retiro en curso termina antes y aquí se ve), el contrato FOR SHARE (un pago, que lo
-- bloquea FOR UPDATE, espera y al seguir ya encuentra el vínculo) y la unicidad del vínculo por
-- contrato, que deja pasar a una sola de dos asignaciones simultáneas.
--
-- De public solo LEE y bloquea FOR SHARE la fila del contrato. No crea ni cambia triggers,
-- políticas ni tablas de public. OK de Miguel: 01/10/2026.
-- No depende de 20261001233019 (motivo del bloqueo y carga del rezago) ni la modifica.
-- SÍ depende de piezas de F3 (20260926204051): la compuerta private.admin_banca_vigente y el
-- candado private.trg_registro_cuenta_pago_no_borrar. Con esta migración aplicada, la reversa de
-- F3 ya no puede quitar ese candado (se niega; primero habría que revertir esta).
-- Excepción anotada al estándar de tablas: sin negocio_id ni updated_at, como las constancias de
-- F3 y F4 del mismo módulo (una fila inmutable no tiene «última modificación»).
-- Reversión: ../scripts/cuentas-pago-asignar/reversa.sql (si ya hay asignaciones registradas no
-- borra nada: solo cierra la puerta).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null
     or pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is not null
     or pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is not null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is not null then
    raise exception 'ASIGNAR PREFLIGHT: ya aplicada (los objetos existen); no se sobrescriben';
  end if;
  if pg_catalog.to_regclass('crm.contrato_cuentas_pago') is null
     or pg_catalog.to_regclass('crm.cuentas_bancarias') is null
     or pg_catalog.to_regclass('public.contratos') is null
     or pg_catalog.to_regprocedure('auth.uid()') is null
     or pg_catalog.to_regprocedure('private.log_audit_crm()') is null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_inmutable()') is null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()') is null then
    raise exception 'ASIGNAR PREFLIGHT: faltan dependencias';
  end if;
  -- Las piezas de las que depende, por identidad: la compuerta de F3, el candado de coherencia
  -- del vínculo (cuenta del mismo cliente y moneda) y el candado «no se borra» de las constancias.
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = pg_catalog.to_regprocedure('private.admin_banca_vigente(uuid)'))
       is distinct from '810dce30e37d1da9d913ef48ab6a4aa1'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()'))
       is distinct from '7e946a5af78a827c18ee5b218896f24c'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_registro_cuenta_pago_no_borrar()'))
       is distinct from 'e95919db53c44ff1fe6632c346f27a06' then
    raise exception 'ASIGNAR PREFLIGHT: la compuerta de administración o los candados del vínculo no son los esperados; no se toca';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass
        and (t.tgname, t.tgfoid) in (
          ('trg_contrato_cuenta_pago_coherente', 'private.trg_contrato_cuenta_pago_coherente()'::regprocedure::oid),
          ('trg_audit_contrato_cuentas_pago', 'private.log_audit_crm()'::regprocedure::oid),
          ('trg_contrato_cuenta_pago_00_inmutable', 'private.trg_contrato_cuenta_pago_inmutable()'::regprocedure::oid))
        and t.tgenabled = 'O') <> 3 then
    raise exception 'ASIGNAR PREFLIGHT: faltan los triggers de coherencia, bitácora o candado del vínculo';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'public.contratos'::regclass and not a.attisdropped
        and a.attname in ('id', 'numero_contrato', 'cliente_id', 'moneda', 'estado')) <> 5
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.cuentas_bancarias'::regclass and not a.attisdropped
           and a.attname in ('id', 'cliente_id', 'moneda', 'banco', 'activa')) <> 5
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.contrato_cuentas_pago'::regclass and not a.attisdropped
           and a.attname in ('id', 'contrato_id', 'cuenta_bancaria_id', 'creado_por')) <> 4 then
    raise exception 'ASIGNAR PREFLIGHT: alguna tabla no tiene las columnas esperadas';
  end if;
  -- Un contrato solo puede tener UN vínculo: de eso depende que dos asignaciones a la vez no
  -- queden las dos.
  if not exists (
    select 1 from pg_catalog.pg_index i
    where i.indrelid = 'crm.contrato_cuentas_pago'::regclass and i.indisunique and i.indpred is null
      and i.indisvalid and i.indimmediate and i.indnatts = 1
      and i.indkey[0] = (select a.attnum from pg_catalog.pg_attribute a
                         where a.attrelid = 'crm.contrato_cuentas_pago'::regclass and a.attname = 'contrato_id')
  ) then
    raise exception 'ASIGNAR PREFLIGHT: el vínculo ya no es único por contrato';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE')
     or not pg_catalog.has_schema_privilege('authenticated', 'crm', 'USAGE') then
    raise exception 'ASIGNAR PREFLIGHT: authenticated necesita USAGE sobre crm y private para la puerta INVOKER';
  end if;
  -- El núcleo (DEFINER, dueño = quien aplica) lee contratos, cuentas y vínculos sin RLS.
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'ASIGNAR PREFLIGHT: el dueño de las funciones debe tener bypassrls';
  end if;
end;
$precondicion$;

-- ── 1. Constancia de cada asignación ─────────────────────────────────────────────────────────
create table crm.contrato_cuenta_pago_asignaciones (
  id                  uuid primary key default gen_random_uuid(),
  solicitud_id        uuid not null constraint contrato_cuenta_pago_asignaciones_solicitud_uq unique,
  contrato_id         uuid not null,
  cliente_id          uuid not null,
  cuenta_bancaria_id  uuid not null,
  vinculo_id          uuid not null,
  motivo              text not null
                      constraint contrato_cuenta_pago_asignaciones_motivo_valido
                      check (motivo = regexp_replace(motivo, '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g')
                             and length(regexp_replace(motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) >= 5
                             and length(motivo) <= 500),
  asignado_por        uuid not null,
  asignado_en         timestamptz not null default now()
);
alter table crm.contrato_cuenta_pago_asignaciones enable row level security;
revoke all on crm.contrato_cuenta_pago_asignaciones from public, anon, authenticated, service_role;

-- Candados de la constancia: no se borra (el mismo de las constancias de F3) y no se modifica.
create function private.trg_contrato_cuenta_pago_asignaciones_inmutable()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using errcode = '22023',
    message = 'El registro de asignaciones de cuenta de pago no se modifica ni se vacía';
end;
$function$;
revoke all on function private.trg_contrato_cuenta_pago_asignaciones_inmutable() from public, anon, authenticated, service_role;

create trigger trg_contrato_cuenta_pago_asignaciones_00_no_borrar
  before delete on crm.contrato_cuenta_pago_asignaciones
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();
create trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable
  before update on crm.contrato_cuenta_pago_asignaciones
  for each row execute function private.trg_contrato_cuenta_pago_asignaciones_inmutable();
create trigger trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar
  before truncate on crm.contrato_cuenta_pago_asignaciones
  for each statement execute function private.trg_contrato_cuenta_pago_asignaciones_inmutable();
create trigger trg_audit_contrato_cuenta_pago_asignaciones
  after insert or delete or update on crm.contrato_cuenta_pago_asignaciones
  for each row execute function private.log_audit_crm();

-- ── 2. Operación: asignar la primera cuenta de pago (núcleo DEFINER + puerta INVOKER) ────────
create function private.asignar_cuenta_pago_contrato_autorizado(
  p_solicitud_id uuid, p_contrato_id uuid, p_cuenta_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_motivo text := pg_catalog.regexp_replace(coalesce(p_motivo, ''), '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g');
  v_previa crm.contrato_cuenta_pago_asignaciones%rowtype;
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_ct record;
  v_vinculo uuid;
  v_esquema text;
  v_tabla text;
begin
  if not coalesce(private.admin_banca_vigente(v_actor), false) then
    raise exception using errcode = '42501',
      message = 'Solo administración puede asignar la cuenta de pago';
  end if;
  if p_solicitud_id is null or p_contrato_id is null or p_cuenta_id is null then
    raise exception using errcode = '22023', message = 'Faltan datos de la asignación';
  end if;
  if pg_catalog.length(pg_catalog.regexp_replace(v_motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) < 5
     or pg_catalog.length(v_motivo) > 500 then
    raise exception using errcode = '22023', message = 'Escribe el motivo de la asignación (5 a 500 caracteres)';
  end if;

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con datos
  -- distintos se rechaza.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('asignar-cuenta-pago:' || p_solicitud_id::text, 0));
  select * into v_previa
  from crm.contrato_cuenta_pago_asignaciones a
  where a.solicitud_id = p_solicitud_id;
  if found then
    if v_previa.contrato_id = p_contrato_id and v_previa.cuenta_bancaria_id = p_cuenta_id
       and v_previa.motivo = v_motivo then
      return pg_catalog.jsonb_build_object(
        'solicitud_id', p_solicitud_id, 'ya_aplicada', true,
        'numero_contrato', (select ct.numero_contrato from public.contratos ct where ct.id = v_previa.contrato_id),
        'banco', (select cb.banco from crm.cuentas_bancarias cb where cb.id = v_previa.cuenta_bancaria_id),
        'moneda', (select cb.moneda from crm.cuentas_bancarias cb where cb.id = v_previa.cuenta_bancaria_id),
        'ultimos', (select case when pg_catalog.length(cb.numero_cuenta) >= 8
                                then pg_catalog.right(cb.numero_cuenta, 4) end
                    from crm.cuentas_bancarias cb
                    where cb.id = v_previa.cuenta_bancaria_id));
    end if;
    raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  end if;

  -- Candados en el orden del cambio de cuenta (F3): cuenta → contrato → vínculo.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_id for share;
  if not found then
    raise exception using errcode = '22023', message = 'La cuenta elegida no existe';
  end if;
  select ct.id, ct.cliente_id, ct.moneda, ct.estado, ct.numero_contrato into v_ct
  from public.contratos ct
  where ct.id = p_contrato_id
  for share;
  if not found then
    raise exception using errcode = '22023', message = 'El contrato no existe';
  end if;

  if v_cuenta.cliente_id is distinct from v_ct.cliente_id then
    raise exception using errcode = '22023',
      message = pg_catalog.format('La cuenta elegida no es del cliente del contrato %s', v_ct.numero_contrato);
  end if;
  if v_cuenta.activa is not true then
    raise exception using errcode = '22023', message = 'La cuenta elegida ya no está vigente';
  end if;
  if v_cuenta.moneda is distinct from v_ct.moneda then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s es en %s y la cuenta elegida en %s',
        v_ct.numero_contrato, v_ct.moneda, v_cuenta.moneda);
  end if;
  if v_ct.estado is null or v_ct.estado not in ('activo', 'vencido') then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s está cerrado (%s)', v_ct.numero_contrato, coalesce(v_ct.estado, 'sin estado'));
  end if;
  if exists (select 1 from crm.contrato_cuentas_pago l where l.contrato_id = p_contrato_id) then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»', v_ct.numero_contrato);
  end if;

  -- Dos asignaciones a la vez del mismo contrato: la unicidad del vínculo deja pasar una sola; la
  -- otra espera y recibe este mismo mensaje. El trigger de coherencia vuelve a exigir cliente y
  -- moneda.
  begin
    insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id, creado_por)
    values (p_contrato_id, p_cuenta_id, v_actor)
    returning id into v_vinculo;
  exception when unique_violation then
    get stacked diagnostics v_esquema = schema_name, v_tabla = table_name;
    if v_esquema is distinct from 'crm' or v_tabla is distinct from 'contrato_cuentas_pago' then
      raise;
    end if;
    raise exception using errcode = '22023',
      message = pg_catalog.format('El contrato %s ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»', v_ct.numero_contrato);
  end;

  insert into crm.contrato_cuenta_pago_asignaciones
    (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)
  values (p_solicitud_id, p_contrato_id, v_ct.cliente_id, p_cuenta_id, v_vinculo, v_motivo, v_actor);

  return pg_catalog.jsonb_build_object(
    'solicitud_id', p_solicitud_id, 'ya_aplicada', false,
    'numero_contrato', v_ct.numero_contrato, 'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda,
    -- Los 4 últimos solo de un número de 8 o más caracteres: nunca el número entero.
    'ultimos', case when pg_catalog.length(v_cuenta.numero_cuenta) >= 8
                    then pg_catalog.right(v_cuenta.numero_cuenta, 4) end);
end;
$function$;
revoke all on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)
  to authenticated;

create function crm.asignar_cuenta_pago_contrato(
  p_solicitud_id uuid, p_contrato_id uuid, p_cuenta_id uuid, p_motivo text)
returns jsonb
language sql
volatile security invoker
set search_path to ''
as $function$
  select private.asignar_cuenta_pago_contrato_autorizado(p_solicitud_id, p_contrato_id, p_cuenta_id, p_motivo);
$function$;
revoke all on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)
  to authenticated;

-- ── 3. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on table crm.contrato_cuenta_pago_asignaciones is
  'Constancia inmutable de cada asignación de la PRIMERA cuenta de pago a un contrato que no tenía ninguna (02/10/2026): quién, cuándo, a qué cuenta y por qué. No es un cambio pedido por el cliente (eso es crm.contrato_cuenta_pago_cambios). Sin claves foráneas a propósito: sobrevive a contratos, cliente, cuentas y personas. No se borra ni se modifica. DATOS SENSIBLES por referencia.';
comment on column crm.contrato_cuenta_pago_asignaciones.id is 'Identificador de la asignación.';
comment on column crm.contrato_cuenta_pago_asignaciones.solicitud_id is 'Id de la operación (idempotencia): un reintento con la misma solicitud no se aplica dos veces.';
comment on column crm.contrato_cuenta_pago_asignaciones.contrato_id is 'Contrato al que se asignó la cuenta de pago (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.cliente_id is 'Cliente titular del contrato en ese momento (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.cuenta_bancaria_id is 'Cuenta de crm.cuentas_bancarias asignada (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.vinculo_id is 'Fila de crm.contrato_cuentas_pago que creó la asignación (sin FK).';
comment on column crm.contrato_cuenta_pago_asignaciones.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';
comment on column crm.contrato_cuenta_pago_asignaciones.asignado_por is 'Administrador que asignó (id de perfil, sin FK: sobrevive a la eliminación del usuario).';
comment on column crm.contrato_cuenta_pago_asignaciones.asignado_en is 'Momento de la asignación (hora de la transacción).';
comment on function private.trg_contrato_cuenta_pago_asignaciones_inmutable() is 'Candado de la constancia de asignaciones de cuenta de pago: ninguna fila se modifica y la tabla no se vacía. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) is 'Núcleo de la asignación de la PRIMERA cuenta de pago de un contrato: solo admin vigente (P04); contrato abierto y sin cuenta de pago; cuenta vigente del mismo cliente y moneda; motivo obligatorio; idempotente por solicitud; deja constancia en crm.contrato_cuenta_pago_asignaciones. SECURITY DEFINER porque authenticated no tiene permisos sobre el vínculo, las cuentas ni la constancia.';
comment on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) is 'Puerta (INVOKER) para asignar la primera cuenta de pago a un contrato que no tiene ninguna. La usa Pagos del portal (solo admin). Para cambiar una cuenta ya asignada: crm.cambiar_cuenta_pago_contratos.';

-- ── 4. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  -- Ninguna clave foránea entra ni sale de la constancia: las eliminaciones auditadas de contratos
  -- y de usuarios no ven dependencias nuevas.
  if exists (
    select 1 from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and (c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
           or c.confrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass)
  ) then
    raise exception 'ASIGNAR POSTFLIGHT: la constancia no debe tener claves foráneas';
  end if;
  -- Nadie de la API toca la tabla, y tiene RLS.
  if exists (
    select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
    where pg_catalog.has_table_privilege(r.rol, 'crm.contrato_cuenta_pago_asignaciones',
            'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  ) or not (select t.relrowsecurity from pg_catalog.pg_class t
            where t.oid = 'crm.contrato_cuenta_pago_asignaciones'::regclass) then
    raise exception 'ASIGNAR POSTFLIGHT: la constancia quedó accesible desde la API o sin RLS';
  end if;
  -- Bitácora completa (los tres verbos, por fila, sin condición) y los dos candados, habilitados.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
      and t.tgname = 'trg_audit_contrato_cuenta_pago_asignaciones'
      and t.tgfoid = 'private.log_audit_crm()'::regprocedure
      and t.tgenabled = 'O' and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0 and (t.tgtype & 28) = 28
      and t.tgqual is null and t.tgattr::text = ''
  ) or (select pg_catalog.count(*) from pg_catalog.pg_trigger t
        where t.tgrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
          and t.tgenabled = 'O' and t.tgqual is null and t.tgattr::text = ''
          -- tgtype: fila 1 · antes 2 · borrar 8 · modificar 16 · vaciar 32
          and (t.tgname, t.tgfoid, t.tgtype::integer) in (
            ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
             'private.trg_registro_cuenta_pago_no_borrar()'::regprocedure::oid, 11),
            ('trg_contrato_cuenta_pago_asignaciones_00_inmutable',
             'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure::oid, 19),
            ('trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
             'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure::oid, 34))) <> 3 then
    raise exception 'ASIGNAR POSTFLIGHT: la bitácora o los candados de la constancia no quedaron como se espera';
  end if;
  -- Las dos reglas de la tabla: el motivo y la solicitud única (de ella depende la idempotencia).
  if not exists (
       select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and c.contype = 'c'
         and c.conname = 'contrato_cuenta_pago_asignaciones_motivo_valido' and c.convalidated
         and pg_catalog.pg_get_constraintdef(c.oid) like '%regexp_replace%')
     or not exists (
       select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and c.contype = 'u'
         and c.conname = 'contrato_cuenta_pago_asignaciones_solicitud_uq' and not c.condeferrable) then
    raise exception 'ASIGNAR POSTFLIGHT: faltan las reglas de la constancia (motivo válido o solicitud única)';
  end if;
  -- Forma, cuerpo, EXECUTE exacto (rol NULL = solo su dueño), search_path vacío y comentario.
  for v_f in
    select * from (values
      ('private.trg_contrato_cuenta_pago_asignaciones_inmutable()', null, true, '49bb93b9429aa7b0c168cc8ceb43acfc'),
      ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)', 'authenticated', true, '57297bc7f18279578c2f16f6aaad7247'),
      ('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)', 'authenticated', false, '46e03517fc68ffd79fed6892d1128c2b')
    ) as f(firma, rol, definer, huella)
  loop
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure
                     and pg_catalog.md5(p.prosrc) = v_f.huella
                     and p.prosecdef = v_f.definer and p.provolatile = 'v'
                     and pg_catalog.pg_get_userbyid(p.proowner) = current_user::text) then
      raise exception 'ASIGNAR POSTFLIGHT: cuerpo, DEFINER/INVOKER, volatilidad o dueño inesperados en %', v_f.firma;
    end if;
    if exists (
         select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
         where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
           and a.grantee <> p.proowner
           and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid))
       or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
       or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE'))
       or not exists (select 1 from pg_catalog.pg_proc p
                      where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""'])
       or pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'ASIGNAR POSTFLIGHT: EXECUTE, search_path o comentario inesperados en %', v_f.firma;
    end if;
  end loop;
  -- Toda columna con su comentario.
  if exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and a.attnum > 0 and not a.attisdropped
      and pg_catalog.col_description(a.attrelid, a.attnum) is null
  ) or pg_catalog.obj_description('crm.contrato_cuenta_pago_asignaciones'::regclass, 'pg_class') is null then
    raise exception 'ASIGNAR POSTFLIGHT: falta el comentario de la tabla o de alguna columna';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila (el canal de `db query` no transporta los avisos) y sale del
-- estado real: el núcleo de ESTA migración está puesto y la puerta abierta para authenticated.
select case
         when (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
              = '57297bc7f18279578c2f16f6aaad7247'
          and exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                      where p.oid = pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)')
                        and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::regrole::oid)
         then 'ASIGNAR_CUENTA_PAGO_OK'
       end as resultado;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261002005004' and name = 'crm_asignar_cuenta_pago' and cardinality(statements) = 1
                   and md5(statements[1]) = 'beea048bf51318ac6416872310c8e7f3') then
    raise exception 'REGISTRO: la fila 20261002005004 / crm_asignar_cuenta_pago no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261002005004 / crm_asignar_cuenta_pago (1 sentencia: el archivo entero)';
end $post$;
commit;
