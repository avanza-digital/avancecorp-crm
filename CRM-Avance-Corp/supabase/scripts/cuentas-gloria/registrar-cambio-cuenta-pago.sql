-- REGISTRO en supabase_migrations.schema_migrations de 20260926204051_crm_cambio_cuenta_pago (F3.1).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar. Se niega si las piezas vivas no
-- son exactamente las ensayadas: huella completa de las 16 funciones (cuerpo, DEFINER, search_path,
-- comentario y EXECUTE sin el dueño), tablas, triggers, políticas y bucket.
-- Generado desde la migración (el texto registrado es byte a byte el del archivo).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_cambio_cuenta_pago'));
do $chk$
declare
  v_funciones integer;
  v_huella text;
begin
  select count(*), pg_catalog.md5(pg_catalog.string_agg(linea, E'\n' order by linea))
    into v_funciones, v_huella
  from (
    select p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc) || '|' || p.prosecdef::text || '|'
           || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '-') || '|'
           || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-') || '|'
           || coalesce((select pg_catalog.string_agg(g, ',' order by g)
                        from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                                     || ':' || a.privilege_type as g
                              from pg_catalog.aclexplode(p.proacl) a
                              where a.grantee <> p.proowner) acl), '-') as linea
    from pg_catalog.pg_proc p
    where p.oid in (
      select to_regprocedure(f) from pg_catalog.unnest(array[
        'private.admin_banca_vigente(uuid)',
        'private.trg_registro_cuenta_pago_no_borrar()',
        'private.trg_contrato_cuenta_pago_cambios_inmutable()',
        'private.trg_cuotas_cuenta_pagada_solo_resello()',
        'private.sellar_cuenta_cuota_pagada()',
        'private.trg_contrato_cuenta_pago_inmutable()',
        'private.respaldo_cambio_cuenta_permitido(text)',
        'private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
        'crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)',
        'private.contratos_cuenta_pago_cliente_autorizado(uuid)',
        'crm.contratos_cuenta_pago_cliente_fn(uuid)',
        'private.cambios_cuenta_pago_cliente_autorizado(uuid)',
        'crm.cambios_cuenta_pago_cliente_fn(uuid)',
        'private.contratos_vigentes_de_cambio(uuid)',
        'crm.reclamar_aviso_cambio_cuenta(uuid,uuid,boolean)',
        'crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)']) f)
  ) s;
  if v_funciones <> 16 or v_huella is distinct from '21bb1838606355e1161a44fb0b66e809'
     or to_regclass('crm.cuotas_cuenta_pagada') is null
     or to_regclass('crm.contrato_cuenta_pago_cambios') is null
     or to_regclass('crm.cambio_cuenta_avisos') is null
     or (select count(*) from pg_catalog.pg_trigger where tgrelid = 'public.cronograma_pagos'::regclass
         and tgname like 'trg\_cronograma\_pagos\_20\_sellar\_cuenta\_%') <> 2
     or (select count(*) from pg_catalog.pg_trigger where not tgisinternal
         and tgrelid in ('crm.cuotas_cuenta_pagada'::regclass, 'crm.contrato_cuenta_pago_cambios'::regclass,
                         'crm.cambio_cuenta_avisos'::regclass)) <> 8
     or (select count(*) from pg_catalog.pg_policies where schemaname = 'storage'
         and policyname like 'respaldo\_cambio\_cuenta\_%') <> 7
     or not exists (select 1 from storage.buckets b where b.id = 'respaldos-cambio-cuenta' and b.public is false
                    and b.file_size_limit = 10485760
                    and b.allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png']::text[]) then
    raise exception 'REGISTRO: las piezas vivas no son la F3.1 ensayada (% funciones, huella %); aplica primero 20260926204051',
      v_funciones, v_huella;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260926204051' and coalesce(name, '') <> 'crm_cambio_cuenta_pago') then
    raise exception 'REGISTRO: la versión 20260926204051 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260926204051', 'crm_cambio_cuenta_pago', array[$registro$-- Cuentas de Gloria · F3.1: cambiar la cuenta de pago de contratos por pedido del cliente.
--
-- Qué hace (servidor; la pantalla es F3.2 y el aviso al cliente F3.3):
--   1. Registros SIN claves foráneas (ver «Diseño»); ninguno se borra:
--      · crm.cuotas_cuenta_pagada: la cuenta a la que se pagó cada cuota. La sella un trigger al
--        pasar la cuota a 'pagado' ('registro'), con la cuenta vigente en la FECHA del pago (si
--        después de esa fecha hubo un cambio, la cuenta anterior del primero); corregir la fecha
--        re-sella. Las ya pagadas se sellan con la cuenta contractual actual como 'inferido' (el
--        enlace nació el 25/09 desde el perfil). El registro de pagos NO cambia.
--      · crm.contrato_cuenta_pago_cambios: historial inmutable de cambios (solo notificado_en pasa
--        una vez de NULL a fecha).
--      · crm.cambio_cuenta_avisos: estado del aviso al cliente por solicitud.
--   2. El candado del enlace contrato→cuenta admite UN caso: el cambio escrito en el historial en
--      la MISMA transacción (cambiado_en = now()). Todo lo demás sigue inmutable.
--   3. Operación atómica crm.cambiar_cuenta_pago_contratos (puerta INVOKER → núcleo DEFINER):
--      solo admin/superadmin activo y con la membresía CRM NO revocada (P04); por contrato entero;
--      cuenta nueva vigente, del mismo cliente y moneda; contratos del cliente en 'activo'/'vencido'
--      con cuenta de pago y sin un aviso al cliente en curso; motivo y respaldo obligatorios (el
--      correo del cliente, subido por el mismo admin y que no respalde otra solicitud ni por ruta
--      ni por contenido); todo o nada; idempotente comparando TODOS los datos.
--   4. Lecturas para la pantalla, con la misma compuerta que el cambio.
--   5. Bucket privado 'respaldos-cambio-cuenta' (PDF/JPG/PNG ≤10 MB): solo el admin vigente sube y
--      lee; fronteras RESTRICTIVE: nadie sustituye ni borra, y anon no entra.
--   6. Aviso al cliente en dos pasos (solo service_role, para la Edge notificar-cambio-cuenta):
--      reclamar (reserva de 10 min con token; bloquea los enlaces para no anunciar una cuenta que
--      otro cambio deja atrás; no avisa cambios superados; exige que quien lo pide sea admin
--      vigente) y confirmar (con el token: registra lo que salió; notificado_en solo cuando llegó
--      por todos sus canales y solo en los contratos anunciados).
--
-- Decisiones de Miguel (26/09/2026): por contrato entero; solo admin y superadmin; aviso por portal
-- y correo; respaldo = el correo del cliente donde pide el cambio. Toca objetos de public (dos
-- triggers AFTER en public.cronograma_pagos; bloqueos FOR SHARE de public.contratos) y de storage
-- (bucket y políticas): requiere el OK explícito de Miguel, anotado en MIGRACIONES.md.
--
-- Diseño — por qué los registros no tienen claves foráneas: son constancias que deben SOBREVIVIR
-- a los contratos, cuotas, clientes, cuentas y personas que nombran. Con CASCADE se borrarían con
-- ellos; con RESTRICT bloquearían las eliminaciones auditadas; y las guardas de esas eliminaciones
-- (crm.contrato_eliminar_auditado y la eliminación de usuarios) fallan cerradas ante cualquier
-- dependencia nueva (revisión auditor-rls, P1-1). Sus únicos escritores —el núcleo, que valida
-- cada id bajo bloqueo, y el trigger del sello, que copia ids de filas reales— garantizan ids
-- válidos al escribir. Las lecturas unen con INNER JOIN a contratos y cuentas (un registro de una
-- fila eliminada no se muestra, pero se conserva) y con LEFT JOIN a perfiles para el nombre.
--
-- Bloqueos: el núcleo toma los contratos (FOR SHARE, por id) y DESPUÉS los enlaces (FOR UPDATE),
-- el mismo orden que el registro de un pago: su trigger 00 (private.proteger_cronograma_documental
-- → private.bloquear_fila_contrato_pdf) bloquea el contrato FOR UPDATE y su trigger 10
-- (private.exigir_cuenta_pago_cronograma) lee el enlace FOR SHARE. Así un pago y un cambio del mismo
-- contrato se ponen en fila en el contrato: sin abrazo mortal, y el pago que esperaba lee el enlace
-- ya cambiado. El aviso (reclamar) toma su fila de aviso y después los enlaces FOR SHARE: un
-- cambio espera a que termine la reserva de un aviso, y el núcleo rechaza cambiar un contrato con
-- un aviso en curso. Riesgo residual: un registro de pagos en lote que bloquee varios contratos en
-- otro orden podría cruzarse con un cambio de esos mismos contratos; Postgres detecta el abrazo y
-- aborta uno de los dos (falla cerrado, sin dato erróneo; basta con reintentarlo).
--
-- Reversión: ../scripts/cuentas-gloria/reversa-cambio-cuenta-pago.sql (se niega si ya hay cambios
-- registrados o si las piezas vivas no son las ensayadas).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = to_regprocedure('private.trg_contrato_cuenta_pago_inmutable()'))
     is distinct from '349a5a7f9a52283c5331aea6d90967f9' then
    raise exception 'CAMBIO_CUENTA: el candado del enlace contrato→cuenta no es el esperado; no se toca';
  end if;
  if to_regclass('crm.contrato_cuentas_pago') is null or to_regclass('crm.cuentas_bancarias') is null
     or to_regclass('crm.equipo') is null or to_regclass('public.perfiles') is null
     or to_regclass('public.contratos') is null or to_regclass('public.cronograma_pagos') is null
     or to_regclass('storage.objects') is null or to_regclass('storage.buckets') is null
     or to_regprocedure('auth.uid()') is null or to_regprocedure('auth.role()') is null
     or to_regprocedure('private.log_audit_crm()') is null then
    raise exception 'CAMBIO_CUENTA: faltan dependencias';
  end if;
  if to_regclass('crm.cuotas_cuenta_pagada') is not null
     or to_regclass('crm.contrato_cuenta_pago_cambios') is not null
     or to_regclass('crm.cambio_cuenta_avisos') is not null then
    raise exception 'CAMBIO_CUENTA: los objetos ya existen; no se sobrescriben';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'CAMBIO_CUENTA: authenticated necesita USAGE sobre private para las puertas INVOKER';
  end if;
  -- El núcleo (DEFINER, dueño = quien aplica) lee storage.objects para validar el respaldo: el
  -- dueño debe poder leerlo sin RLS y esas columnas deben existir con esos tipos.
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false)
     or not pg_catalog.has_table_privilege(current_user, 'storage.objects', 'SELECT') then
    raise exception 'CAMBIO_CUENTA: el dueño de las funciones no puede leer storage.objects sin RLS';
  end if;
  if (select count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'storage.objects'::regclass and not a.attisdropped
        and (a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod)) in
            (('owner', 'uuid'), ('owner_id', 'text'), ('metadata', 'jsonb'), ('bucket_id', 'text'), ('name', 'text'))) <> 5 then
    raise exception 'CAMBIO_CUENTA: storage.objects no tiene las columnas esperadas';
  end if;
  if (select count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'crm.cuentas_bancarias'::regclass and not a.attisdropped
        and a.attname in ('cliente_id', 'moneda', 'banco', 'numero_cuenta', 'activa',
                          'titular_distinto', 'beneficiario_nombre')) <> 7 then
    raise exception 'CAMBIO_CUENTA: crm.cuentas_bancarias no tiene las columnas esperadas';
  end if;
end;
$precondicion$;

-- ── 0. Compuerta común: admin o superadmin activo y con la membresía CRM no revocada (P04) ─────
create function private.admin_banca_vigente(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select p_uid is not null
     and exists (
       select 1 from public.perfiles p
       where p.id = p_uid and p.rol in ('admin', 'superadmin') and p.activo is true)
     and not exists (
       select 1 from crm.equipo e
       where e.perfil_id = p_uid and e.activo is false);
$function$;
revoke all on function private.admin_banca_vigente(uuid) from public, anon, authenticated, service_role;
grant execute on function private.admin_banca_vigente(uuid) to authenticated;

-- ── 1. Registros ─────────────────────────────────────────────────────────────────────────────
create table crm.cuotas_cuenta_pagada (
  id                  uuid primary key default gen_random_uuid(),
  cuota_id            uuid not null constraint cuotas_cuenta_pagada_cuota_uq unique,
  contrato_id         uuid not null,
  cuenta_bancaria_id  uuid not null,
  origen              text not null
                      constraint cuotas_cuenta_pagada_origen_valido check (origen in ('registro', 'inferido')),
  sellada_en          timestamptz not null default now()
);
alter table crm.cuotas_cuenta_pagada enable row level security;
revoke all on crm.cuotas_cuenta_pagada from public, anon, authenticated, service_role;
create index cuotas_cuenta_pagada_contrato_idx on crm.cuotas_cuenta_pagada (contrato_id);
create index cuotas_cuenta_pagada_cuenta_idx on crm.cuotas_cuenta_pagada (cuenta_bancaria_id);

create table crm.contrato_cuenta_pago_cambios (
  id                  uuid primary key default gen_random_uuid(),
  solicitud_id        uuid not null,
  contrato_id         uuid not null,
  cliente_id          uuid not null,
  cuenta_anterior_id  uuid not null,
  cuenta_nueva_id     uuid not null,
  motivo              text not null
                      constraint contrato_cuenta_pago_cambios_motivo_valido
                      check (motivo = btrim(motivo) and length(motivo) between 5 and 500),
  respaldo_ruta       text not null
                      constraint contrato_cuenta_pago_cambios_respaldo_valido
                      check (respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$'),
  cambiado_por        uuid not null,
  cambiado_en         timestamptz not null default now(),
  notificado_en       timestamptz,
  constraint contrato_cuenta_pago_cambios_solicitud_contrato_uq unique (solicitud_id, contrato_id),
  constraint contrato_cuenta_pago_cambios_cuentas_distintas check (cuenta_anterior_id <> cuenta_nueva_id)
);
alter table crm.contrato_cuenta_pago_cambios enable row level security;
revoke all on crm.contrato_cuenta_pago_cambios from public, anon, authenticated, service_role;
create index contrato_cuenta_pago_cambios_contrato_idx on crm.contrato_cuenta_pago_cambios (contrato_id, cambiado_en desc);
create index contrato_cuenta_pago_cambios_cliente_idx on crm.contrato_cuenta_pago_cambios (cliente_id, cambiado_en desc);
create index contrato_cuenta_pago_cambios_respaldo_idx on crm.contrato_cuenta_pago_cambios (respaldo_ruta);

create table crm.cambio_cuenta_avisos (
  id              uuid primary key default gen_random_uuid(),
  solicitud_id    uuid not null constraint cambio_cuenta_avisos_solicitud_uq unique,
  reserva         uuid,
  reclamado_en    timestamptz,
  novedad_en      timestamptz,
  correo_en       timestamptz,
  superada_en     timestamptz,
  intentos        integer not null default 0 constraint cambio_cuenta_avisos_intentos_validos check (intentos >= 0),
  ultimo_error    text constraint cambio_cuenta_avisos_error_corto check (ultimo_error is null or length(ultimo_error) <= 500),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);
alter table crm.cambio_cuenta_avisos enable row level security;
revoke all on crm.cambio_cuenta_avisos from public, anon, authenticated, service_role;

-- Candados de los registros: nada se borra; el historial solo sella el aviso; el sello solo se
-- re-sella (una cuota que vuelve a pagarse tras una anulación).
create function private.trg_registro_cuenta_pago_no_borrar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using errcode = '22023',
    message = 'Los registros de cuentas de pago no se borran';
end;
$function$;
revoke all on function private.trg_registro_cuenta_pago_no_borrar() from public, anon, authenticated, service_role;
create trigger trg_cuotas_cuenta_pagada_00_no_borrar before delete on crm.cuotas_cuenta_pagada
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();
create trigger trg_contrato_cuenta_pago_cambios_00_no_borrar before delete on crm.contrato_cuenta_pago_cambios
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();
create trigger trg_cambio_cuenta_avisos_00_no_borrar before delete on crm.cambio_cuenta_avisos
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();

create function private.trg_contrato_cuenta_pago_cambios_inmutable()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- Solo el sello del aviso, una vez: NULL → fecha. El resto es historia.
  if row(new.id, new.solicitud_id, new.contrato_id, new.cliente_id, new.cuenta_anterior_id,
         new.cuenta_nueva_id, new.motivo, new.respaldo_ruta, new.cambiado_por, new.cambiado_en)
     is distinct from
     row(old.id, old.solicitud_id, old.contrato_id, old.cliente_id, old.cuenta_anterior_id,
         old.cuenta_nueva_id, old.motivo, old.respaldo_ruta, old.cambiado_por, old.cambiado_en)
     or (old.notificado_en is not null and new.notificado_en is distinct from old.notificado_en) then
    raise exception using errcode = '22023',
      message = 'El historial de cambios de cuenta de pago no se modifica';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_contrato_cuenta_pago_cambios_inmutable() from public, anon, authenticated, service_role;
create trigger trg_contrato_cuenta_pago_cambios_00_inmutable
  before update on crm.contrato_cuenta_pago_cambios
  for each row execute function private.trg_contrato_cuenta_pago_cambios_inmutable();

create function private.trg_cuotas_cuenta_pagada_solo_resello()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.id is distinct from old.id or new.cuota_id is distinct from old.cuota_id then
    raise exception using errcode = '22023', message = 'El sello de una cuota solo se re-sella';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_cuotas_cuenta_pagada_solo_resello() from public, anon, authenticated, service_role;
create trigger trg_cuotas_cuenta_pagada_00_solo_resello
  before update on crm.cuotas_cuenta_pagada
  for each row execute function private.trg_cuotas_cuenta_pagada_solo_resello();

-- ── 2. Sello de la cuenta en cada cuota pagada ─────────────────────────────────────────────
create function private.sellar_cuenta_cuota_pagada()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_cuenta uuid;
  v_nuevo_pago boolean := tg_op = 'INSERT';
begin
  if not v_nuevo_pago then
    v_nuevo_pago := old.estado is distinct from 'pagado';
  end if;
  -- Corrección de la fecha de una cuota ya pagada: solo se recalcula un sello deducido por la
  -- fecha ('registro'); el inferido no depende de ella.
  if not v_nuevo_pago
     and exists (select 1 from crm.cuotas_cuenta_pagada q
                 where q.cuota_id = new.id and q.origen <> 'registro') then
    return null;
  end if;
  -- La cuenta vigente en la FECHA del pago: si después de esa fecha (día de Lima) hubo un cambio,
  -- la cuenta anterior del primero; si no, la cuenta contractual actual. Así, registrar tarde (o
  -- volver a registrar tras anular) un pago viejo no lo atribuye a la cuenta nueva. Un pago con
  -- fecha del mismo día del cambio va a la cuenta nueva: la fecha no dice la hora del depósito
  -- (la importación del Excel avisa esas filas).
  if new.fecha_pago_real is not null then
    select c.cuenta_anterior_id into v_cuenta
    from crm.contrato_cuenta_pago_cambios c
    where c.contrato_id = new.contrato_id
      and (c.cambiado_en at time zone 'America/Lima')::date > new.fecha_pago_real
    order by c.cambiado_en asc, c.id asc
    limit 1;
  end if;
  if v_cuenta is null then
    select l.cuenta_bancaria_id into v_cuenta
    from crm.contrato_cuentas_pago l
    where l.contrato_id = new.contrato_id;
  end if;
  -- Sin cuenta: el trigger BEFORE de exigencia ya rechazó el pago; nada que sellar.
  if v_cuenta is null then
    return null;
  end if;
  insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
  values (new.id, new.contrato_id, v_cuenta, case when v_nuevo_pago then 'registro' else 'inferido' end)
  on conflict (cuota_id) do update
    set contrato_id = excluded.contrato_id,
        cuenta_bancaria_id = excluded.cuenta_bancaria_id,
        origen = case when v_nuevo_pago then excluded.origen else crm.cuotas_cuenta_pagada.origen end,
        sellada_en = pg_catalog.now();
  return null;
end;
$function$;
revoke all on function private.sellar_cuenta_cuota_pagada() from public, anon, authenticated, service_role;

create trigger trg_cronograma_pagos_20_sellar_cuenta_insert
  after insert on public.cronograma_pagos
  for each row when (new.estado = 'pagado')
  execute function private.sellar_cuenta_cuota_pagada();
create trigger trg_cronograma_pagos_20_sellar_cuenta_update
  after update of estado, fecha_pago_real on public.cronograma_pagos
  for each row when (new.estado = 'pagado'
    and (old.estado is distinct from 'pagado' or old.fecha_pago_real is distinct from new.fecha_pago_real))
  execute function private.sellar_cuenta_cuota_pagada();

-- Backfill 'inferido': el enlace nació el 25/09 (P-0XX) desde la cuenta del perfil; es la mejor
-- inferencia de dónde se pagaron las cuotas anteriores, y la pantalla la muestra como tal.
insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
select cp.id, cp.contrato_id, l.cuenta_bancaria_id, 'inferido'
from public.cronograma_pagos cp
join crm.contrato_cuentas_pago l on l.contrato_id = cp.contrato_id
where cp.estado = 'pagado';

create trigger trg_audit_cuotas_cuenta_pagada
  after insert or delete or update on crm.cuotas_cuenta_pagada
  for each row execute function private.log_audit_crm();
create trigger trg_audit_contrato_cuenta_pago_cambios
  after insert or delete or update on crm.contrato_cuenta_pago_cambios
  for each row execute function private.log_audit_crm();
create trigger trg_audit_cambio_cuenta_avisos
  after insert or delete or update on crm.cambio_cuenta_avisos
  for each row execute function private.log_audit_crm();

-- ── 3. Candado del enlace: admite SOLO el cambio registrado en esta transacción ─────────────
create or replace function private.trg_contrato_cuenta_pago_inmutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if row(new.id, new.contrato_id, new.creado_en)
     is distinct from
     row(old.id, old.contrato_id, old.creado_en) then
    raise exception using
      errcode = '22023',
      message = 'La cuenta de pago del contrato es historica y no se reemplaza';
  end if;
  -- La cuenta solo cambia si el mismo cambio quedó escrito en el historial dentro de ESTA
  -- transacción (cambiado_en = now() de la transacción). Solo el núcleo del cambio escribe ese
  -- historial.
  if new.cuenta_bancaria_id is distinct from old.cuenta_bancaria_id
     and not exists (
       select 1 from crm.contrato_cuenta_pago_cambios c
       where c.contrato_id = new.contrato_id
         and c.cuenta_anterior_id = old.cuenta_bancaria_id
         and c.cuenta_nueva_id = new.cuenta_bancaria_id
         and c.cambiado_en = pg_catalog.now()
     ) then
    raise exception using
      errcode = '22023',
      message = 'La cuenta de pago del contrato solo cambia con un cambio registrado';
  end if;
  if new.creado_por is distinct from old.creado_por
     and not (
       new.creado_por is null
       and old.creado_por is not null
       and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
     ) then
    raise exception using errcode = '22023', message = 'La autoria del enlace bancario es inmutable';
  end if;
  return new;
end;
$$;

-- ── 4. Respaldo: bucket privado, solo el admin vigente sube y lee; nadie sustituye ni borra ─
-- Tolera el bucket si ya existe (una reversa no puede borrarlo: storage.protect_delete), pero
-- exige su configuración privada exacta.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('respaldos-cambio-cuenta', 'respaldos-cambio-cuenta', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png']::text[])
on conflict (id) do nothing;
do $bucket_privado$
begin
  if not exists (
    select 1 from storage.buckets b
    where b.id = 'respaldos-cambio-cuenta' and b.name = 'respaldos-cambio-cuenta'
      and b.public is false and b.file_size_limit = 10485760
      and b.allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png']::text[]
  ) then
    raise exception 'CAMBIO_CUENTA: el bucket respaldos-cambio-cuenta no tiene la configuración privada esperada';
  end if;
end;
$bucket_privado$;

create function private.respaldo_cambio_cuenta_permitido(p_nombre text)
returns boolean
language sql
stable
security invoker
set search_path to ''
as $function$
  select coalesce(private.admin_banca_vigente((select auth.uid())), false)
     and coalesce(p_nombre ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false);
$function$;
revoke all on function private.respaldo_cambio_cuenta_permitido(text) from public, anon, authenticated, service_role;
grant execute on function private.respaldo_cambio_cuenta_permitido(text) to authenticated;

create policy respaldo_cambio_cuenta_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'respaldos-cambio-cuenta' and private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_select on storage.objects for select to authenticated
  using (bucket_id = 'respaldos-cambio-cuenta' and private.respaldo_cambio_cuenta_permitido(name));
-- Fronteras RESTRICTIVE (patrón de f4-comprobantes): ninguna política permisiva de otro bucket
-- abre estos respaldos ni permite sustituir o borrar sus bytes. La de anon no llama funciones
-- (anon no tiene USAGE sobre private): simplemente lo deja fuera del bucket.
create policy respaldo_cambio_cuenta_insert_frontera on storage.objects as restrictive for insert to authenticated
  with check (bucket_id is distinct from 'respaldos-cambio-cuenta' or private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_select_frontera on storage.objects as restrictive for select to authenticated
  using (bucket_id is distinct from 'respaldos-cambio-cuenta' or private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_update_frontera on storage.objects as restrictive for update to authenticated
  using (bucket_id is distinct from 'respaldos-cambio-cuenta')
  with check (bucket_id is distinct from 'respaldos-cambio-cuenta');
create policy respaldo_cambio_cuenta_delete_frontera on storage.objects as restrictive for delete to authenticated
  using (bucket_id is distinct from 'respaldos-cambio-cuenta');
create policy respaldo_cambio_cuenta_anon_frontera on storage.objects as restrictive for all to anon
  using (bucket_id is distinct from 'respaldos-cambio-cuenta')
  with check (bucket_id is distinct from 'respaldos-cambio-cuenta');

-- ── 5. Operación: cambiar la cuenta de pago (núcleo DEFINER + puerta INVOKER) ───────────────
create function private.cambiar_cuenta_pago_contratos_autorizado(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_nueva_id uuid,
  p_contrato_ids uuid[], p_motivo text, p_respaldo_ruta text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ids uuid[];
  v_motivo text := pg_catalog.btrim(coalesce(p_motivo, ''));
  v_previos integer;
  v_igual boolean;
  v_prev_ids uuid[];
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_obj storage.objects%rowtype;
  v_ct record;
  v_contados integer := 0;
  v_hechos integer;
  v_etag text;
  v_en_curso text;
begin
  if not coalesce(private.admin_banca_vigente(v_actor), false) then
    raise exception using errcode = '42501',
      message = 'Solo administración puede cambiar la cuenta de pago';
  end if;
  if p_solicitud_id is null or p_cliente_id is null or p_cuenta_nueva_id is null then
    raise exception using errcode = '22023', message = 'Faltan datos del cambio';
  end if;
  v_ids := array(select distinct x from pg_catalog.unnest(p_contrato_ids) x where x is not null order by x);
  if coalesce(pg_catalog.cardinality(v_ids), 0) = 0
     or pg_catalog.cardinality(v_ids) <> coalesce(pg_catalog.cardinality(p_contrato_ids), 0)
     or pg_catalog.cardinality(v_ids) > 100 then
    raise exception using errcode = '22023', message = 'Elige entre 1 y 100 contratos, sin repetir';
  end if;
  if pg_catalog.length(v_motivo) not between 5 and 500 then
    raise exception using errcode = '22023', message = 'Escribe el motivo del cambio (5 a 500 caracteres)';
  end if;

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con datos
  -- distintos (cuenta, contratos, motivo o respaldo) se rechaza.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cambio-cuenta:' || p_solicitud_id::text, 0));
  select count(*),
         bool_and(c.cliente_id = p_cliente_id and c.cuenta_nueva_id = p_cuenta_nueva_id
                  and c.motivo = v_motivo and c.respaldo_ruta = p_respaldo_ruta),
         array_agg(c.contrato_id order by c.contrato_id)
    into v_previos, v_igual, v_prev_ids
  from crm.contrato_cuenta_pago_cambios c
  where c.solicitud_id = p_solicitud_id;
  if v_previos > 0 then
    if v_igual and v_prev_ids = v_ids then
      return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true,
        'contratos', v_previos);
    end if;
    raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  end if;

  -- Respaldo: el correo del cliente, en su carpeta, subido por este mismo admin y sin usar en otra
  -- solicitud (el segundo candado serializa dos solicitudes que intenten el mismo archivo).
  if p_respaldo_ruta is null
     or pg_catalog.split_part(p_respaldo_ruta, '/', 1) is distinct from p_cliente_id::text
     or not coalesce(p_respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false) then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-cambio-cuenta:' || p_respaldo_ruta, 0));
  select * into v_obj from storage.objects
  where bucket_id = 'respaldos-cambio-cuenta' and name = p_respaldo_ruta;
  if not found
     or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
     or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;
  if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then
    raise exception using errcode = '22023', message = 'El respaldo debe subirlo quien hace el cambio';
  end if;
  if exists (select 1 from crm.contrato_cuenta_pago_cambios c
             where c.respaldo_ruta = p_respaldo_ruta and c.solicitud_id <> p_solicitud_id) then
    raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
  end if;
  -- El mismo archivo subido otra vez con otra ruta tampoco vale: se compara la huella del
  -- contenido que calcula Storage (eTag), no un dato del navegador.
  v_etag := nullif(pg_catalog.btrim(v_obj.metadata->>'eTag', '"'), '');
  if v_etag is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-etag:' || v_etag, 0));
    if exists (select 1 from crm.contrato_cuenta_pago_cambios c
               join storage.objects o on o.bucket_id = 'respaldos-cambio-cuenta' and o.name = c.respaldo_ruta
               where c.solicitud_id <> p_solicitud_id
                 and pg_catalog.btrim(o.metadata->>'eTag', '"') = v_etag) then
      raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
    end if;
  end if;

  -- Cuenta nueva: del cliente y vigente.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_nueva_id for share;
  if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
    raise exception using errcode = '22023', message = 'La cuenta nueva no es de este cliente';
  end if;
  if not v_cuenta.activa then
    raise exception using errcode = '22023', message = 'La cuenta nueva ya no está vigente';
  end if;

  -- Contratos (se bloquean antes que los enlaces, como al registrar un pago): del cliente,
  -- abiertos y en la moneda de la cuenta.
  for v_ct in
    select ct.id, ct.cliente_id, ct.moneda, ct.estado, ct.numero_contrato
    from public.contratos ct
    where ct.id = any(v_ids)
    order by ct.id
    for share
  loop
    if v_ct.cliente_id is distinct from p_cliente_id then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s no es de este cliente', v_ct.numero_contrato);
    end if;
    if v_ct.estado not in ('activo', 'vencido') then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s está cerrado (%s)', v_ct.numero_contrato, v_ct.estado);
    end if;
    if v_ct.moneda is distinct from v_cuenta.moneda then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s es en %s y la cuenta nueva en %s',
          v_ct.numero_contrato, v_ct.moneda, v_cuenta.moneda);
    end if;
    v_contados := v_contados + 1;
  end loop;
  if v_contados <> pg_catalog.cardinality(v_ids) then
    raise exception using errcode = '22023', message = 'Algún contrato no existe';
  end if;
  perform 1 from crm.contrato_cuentas_pago l where l.contrato_id = any(v_ids) order by l.contrato_id for update;

  -- Un aviso al cliente en curso para estos contratos (reservado y sin confirmar): si el cambio
  -- entrara ahora, ese aviso anunciaría una cuenta que este cambio deja atrás. Con los enlaces ya
  -- bloqueados, toda reserva hecha antes está confirmada en la base y se ve aquí.
  select ct.numero_contrato into v_en_curso
  from crm.contrato_cuenta_pago_cambios c
  join crm.cambio_cuenta_avisos av on av.solicitud_id = c.solicitud_id
  join public.contratos ct on ct.id = c.contrato_id
  where c.contrato_id = any(v_ids)
    and av.reserva is not null
    and av.reclamado_en > pg_catalog.clock_timestamp() - interval '10 minutes'
  order by ct.numero_contrato
  limit 1;
  if v_en_curso is not null then
    raise exception using errcode = '22023',
      message = pg_catalog.format('Se está enviando al cliente el aviso de un cambio anterior del contrato %s; espera unos segundos y vuelve a intentar', v_en_curso);
  end if;

  -- Enlaces actuales: cada contrato debe tener cuenta de pago y no ser ya la nueva.
  for v_ct in
    select ct.numero_contrato, l.cuenta_bancaria_id
    from public.contratos ct
    left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
    where ct.id = any(v_ids)
    order by ct.id
  loop
    if v_ct.cuenta_bancaria_id is null then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s no tiene cuenta de pago; requiere conciliación', v_ct.numero_contrato);
    end if;
    if v_ct.cuenta_bancaria_id = p_cuenta_nueva_id then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s ya cobra en esa cuenta', v_ct.numero_contrato);
    end if;
  end loop;

  -- Primero la historia; luego el enlace (el candado exige esa historia en esta transacción).
  insert into crm.contrato_cuenta_pago_cambios
    (solicitud_id, contrato_id, cliente_id, cuenta_anterior_id, cuenta_nueva_id,
     motivo, respaldo_ruta, cambiado_por)
  select p_solicitud_id, l.contrato_id, p_cliente_id, l.cuenta_bancaria_id, p_cuenta_nueva_id,
         v_motivo, p_respaldo_ruta, v_actor
  from crm.contrato_cuentas_pago l
  where l.contrato_id = any(v_ids);

  update crm.contrato_cuentas_pago
     set cuenta_bancaria_id = p_cuenta_nueva_id
   where contrato_id = any(v_ids);
  get diagnostics v_hechos = row_count;
  if v_hechos <> pg_catalog.cardinality(v_ids) then
    raise exception 'CAMBIO_CUENTA: se esperaban % enlaces y se cambiaron %', pg_catalog.cardinality(v_ids), v_hechos;
  end if;

  return pg_catalog.jsonb_build_object(
    'solicitud_id', p_solicitud_id, 'ya_aplicada', false, 'contratos', v_hechos,
    'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda);
end;
$function$;
revoke all on function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)
  from public, anon, authenticated, service_role;
grant execute on function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)
  to authenticated;

create function crm.cambiar_cuenta_pago_contratos(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_nueva_id uuid,
  p_contrato_ids uuid[], p_motivo text, p_respaldo_ruta text)
returns jsonb
language sql
volatile security invoker
set search_path to ''
as $function$
  select private.cambiar_cuenta_pago_contratos_autorizado(
    p_solicitud_id, p_cliente_id, p_cuenta_nueva_id, p_contrato_ids, p_motivo, p_respaldo_ruta);
$function$;
revoke all on function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)
  to authenticated;

-- ── 6. Lecturas para la pantalla (misma compuerta) ──────────────────────────────────────────
create function private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id uuid)
returns table (
  contrato_id uuid, numero_contrato text, moneda text, estado text,
  cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text,
  cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb
)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if not coalesce(private.admin_banca_vigente((select auth.uid())), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede ver las cuentas de pago';
  end if;
  return query
  select ct.id, ct.numero_contrato, ct.moneda, ct.estado,
         l.cuenta_bancaria_id, cb.banco, cb.tipo_cuenta, cb.numero_cuenta, cb.cci,
         (select count(*) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         (select min(cp.fecha_programada) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'cuenta_bancaria_id', s.cuenta_bancaria_id, 'banco', sb.banco,
                    'numero_cuenta', sb.numero_cuenta, 'cuotas', s.n, 'inferidas', s.inferidas)
                  order by s.n desc)
           from (select q.cuenta_bancaria_id, count(*) as n,
                        count(*) filter (where q.origen = 'inferido') as inferidas
                 from crm.cuotas_cuenta_pagada q
                 join public.cronograma_pagos cp on cp.id = q.cuota_id and cp.estado = 'pagado'
                 where q.contrato_id = ct.id
                 group by q.cuenta_bancaria_id) s
           join crm.cuentas_bancarias sb on sb.id = s.cuenta_bancaria_id), '[]'::jsonb)
  from public.contratos ct
  left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  where ct.cliente_id = p_cliente_id
    and ct.estado in ('activo', 'vencido')
  order by ct.moneda, ct.numero_contrato;
end;
$function$;
revoke all on function private.contratos_cuenta_pago_cliente_autorizado(uuid) from public, anon, authenticated, service_role;
grant execute on function private.contratos_cuenta_pago_cliente_autorizado(uuid) to authenticated;

create function crm.contratos_cuenta_pago_cliente_fn(p_cliente_id uuid)
returns table (
  contrato_id uuid, numero_contrato text, moneda text, estado text,
  cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text,
  cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb
)
language sql
stable security invoker
set search_path to ''
as $function$
  select * from private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.contratos_cuenta_pago_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.contratos_cuenta_pago_cliente_fn(uuid) to authenticated;

create function private.cambios_cuenta_pago_cliente_autorizado(p_cliente_id uuid)
returns table (
  cambio_id uuid, solicitud_id uuid, cambiado_en timestamptz, numero_contrato text,
  banco_anterior text, numero_anterior text, banco_nuevo text, numero_nuevo text,
  motivo text, respaldo_ruta text, cambiado_por_nombre text, notificado_en timestamptz,
  aviso_estado text, aviso_error text
)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if not coalesce(private.admin_banca_vigente((select auth.uid())), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede ver el historial de cuentas de pago';
  end if;
  return query
  select c.id, c.solicitud_id, c.cambiado_en, ct.numero_contrato,
         a.banco, a.numero_cuenta, n.banco, n.numero_cuenta,
         c.motivo, c.respaldo_ruta, pr.nombre_completo, c.notificado_en,
         case when c.notificado_en is not null then 'enviado'
              when av.superada_en is not null
                or exists (select 1 from crm.contrato_cuenta_pago_cambios c2
                           where c2.contrato_id = c.contrato_id and c2.cambiado_en > c.cambiado_en)
                or not exists (select 1 from crm.contrato_cuentas_pago l
                               where l.contrato_id = c.contrato_id and l.cuenta_bancaria_id = c.cuenta_nueva_id) then 'superado'
              else 'pendiente' end,
         av.ultimo_error
  from crm.contrato_cuenta_pago_cambios c
  join public.contratos ct on ct.id = c.contrato_id
  join crm.cuentas_bancarias a on a.id = c.cuenta_anterior_id
  join crm.cuentas_bancarias n on n.id = c.cuenta_nueva_id
  left join public.perfiles pr on pr.id = c.cambiado_por and pr.rol <> 'cliente'
  left join crm.cambio_cuenta_avisos av on av.solicitud_id = c.solicitud_id
  where c.cliente_id = p_cliente_id
  order by c.cambiado_en desc, ct.numero_contrato;
end;
$function$;
revoke all on function private.cambios_cuenta_pago_cliente_autorizado(uuid) from public, anon, authenticated, service_role;
grant execute on function private.cambios_cuenta_pago_cliente_autorizado(uuid) to authenticated;

create function crm.cambios_cuenta_pago_cliente_fn(p_cliente_id uuid)
returns table (
  cambio_id uuid, solicitud_id uuid, cambiado_en timestamptz, numero_contrato text,
  banco_anterior text, numero_anterior text, banco_nuevo text, numero_nuevo text,
  motivo text, respaldo_ruta text, cambiado_por_nombre text, notificado_en timestamptz,
  aviso_estado text, aviso_error text
)
language sql
stable security invoker
set search_path to ''
as $function$
  select * from private.cambios_cuenta_pago_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.cambios_cuenta_pago_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.cambios_cuenta_pago_cliente_fn(uuid) to authenticated;

-- ── 7. Aviso al cliente en dos pasos (solo service_role, para la Edge Function) ─────────────
-- Contratos de la solicitud que SIGUEN cobrando en la cuenta de ese cambio (sin un cambio
-- posterior). Solo esos se anuncian: un aviso atrasado nunca presenta una cuenta superada.
-- INVOKER: solo la llama crm.reclamar_aviso_cambio_cuenta, que ya corre como su dueño.
create function private.contratos_vigentes_de_cambio(p_solicitud_id uuid)
returns text[]
language sql
stable
security invoker
set search_path to ''
as $function$
  select coalesce(array_agg(ct.numero_contrato order by ct.numero_contrato), '{}'::text[])
  from crm.contrato_cuenta_pago_cambios c
  join public.contratos ct on ct.id = c.contrato_id
  join crm.contrato_cuentas_pago l on l.contrato_id = c.contrato_id
  where c.solicitud_id = p_solicitud_id
    and l.cuenta_bancaria_id = c.cuenta_nueva_id
    and not exists (
      select 1 from crm.contrato_cuenta_pago_cambios c2
      where c2.contrato_id = c.contrato_id and c2.cambiado_en > c.cambiado_en);
$function$;
revoke all on function private.contratos_vigentes_de_cambio(uuid) from public, anon, authenticated, service_role;

create function crm.reclamar_aviso_cambio_cuenta(p_solicitud_id uuid, p_actor uuid, p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_cliente uuid;
  v_cuenta_nueva uuid;
  v_cambiado_en timestamptz;
  v_aviso crm.cambio_cuenta_avisos%rowtype;
  v_vigentes text[];
  v_perfil public.perfiles%rowtype;
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_reserva uuid;
begin
  if (select auth.role()) is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Solo el servicio de avisos reclama avisos';
  end if;
  -- Quien pide el aviso (lo identifica la Edge por su sesión) debe ser admin vigente (P04).
  if not coalesce(private.admin_banca_vigente(p_actor), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede avisar cambios de cuenta';
  end if;
  select c.cliente_id, c.cuenta_nueva_id, c.cambiado_en
    into v_cliente, v_cuenta_nueva, v_cambiado_en
  from crm.contrato_cuenta_pago_cambios c
  where c.solicitud_id = p_solicitud_id
  limit 1;
  if v_cliente is null then
    return pg_catalog.jsonb_build_object('encontrada', false);
  end if;
  if exists (select 1 from crm.contrato_cuenta_pago_cambios c
             where c.solicitud_id = p_solicitud_id and c.notificado_en is not null) then
    return pg_catalog.jsonb_build_object('encontrada', true, 'ya_notificada', true);
  end if;

  if not p_dry_run then
    insert into crm.cambio_cuenta_avisos (solicitud_id) values (p_solicitud_id)
    on conflict (solicitud_id) do nothing;
  end if;
  select * into v_aviso from crm.cambio_cuenta_avisos
  where solicitud_id = p_solicitud_id
  for update;

  if v_aviso.superada_en is not null then
    return pg_catalog.jsonb_build_object('encontrada', true, 'superada', true);
  end if;
  -- Enlaces de la solicitud FOR SHARE: un cambio en curso de esos contratos termina antes (y aquí
  -- se ve), y uno posterior espera a esta reserva y luego la respeta (el núcleo lo rechaza).
  perform 1 from crm.contrato_cuentas_pago l
  where l.contrato_id in (select c.contrato_id from crm.contrato_cuenta_pago_cambios c
                          where c.solicitud_id = p_solicitud_id)
  order by l.contrato_id
  for share;
  v_vigentes := private.contratos_vigentes_de_cambio(p_solicitud_id);
  if pg_catalog.cardinality(v_vigentes) = 0 then
    if not p_dry_run then
      update crm.cambio_cuenta_avisos
         set superada_en = pg_catalog.clock_timestamp(), reserva = null, reclamado_en = null,
             actualizado_en = pg_catalog.clock_timestamp()
       where solicitud_id = p_solicitud_id;
    end if;
    return pg_catalog.jsonb_build_object('encontrada', true, 'superada', true);
  end if;
  -- Reserva de 10 minutos, más que la ejecución máxima de una Edge Function (400 s): mientras un
  -- envío sigue en curso, otro intento no lo duplica.
  if v_aviso.reclamado_en is not null
     and v_aviso.reclamado_en > pg_catalog.clock_timestamp() - interval '10 minutes' then
    return pg_catalog.jsonb_build_object('encontrada', true, 'en_curso', true);
  end if;
  if not p_dry_run then
    v_reserva := gen_random_uuid();
    update crm.cambio_cuenta_avisos
       set reserva = v_reserva, reclamado_en = pg_catalog.clock_timestamp(), intentos = intentos + 1,
           actualizado_en = pg_catalog.clock_timestamp()
     where solicitud_id = p_solicitud_id;
  end if;

  select * into v_perfil from public.perfiles where id = v_cliente;
  select * into v_cuenta from crm.cuentas_bancarias where id = v_cuenta_nueva;
  return pg_catalog.jsonb_build_object(
    'encontrada', true, 'ya_notificada', false, 'superada', false, 'en_curso', false,
    'dry_run', p_dry_run, 'reserva', v_reserva,
    'cliente_id', v_perfil.id, 'nombre_completo', v_perfil.nombre_completo,
    'nombres', v_perfil.nombres, 'correo', v_perfil.correo, 'activo', v_perfil.activo,
    'banco_nuevo', v_cuenta.banco, 'moneda', v_cuenta.moneda,
    'ultimos_nuevo', pg_catalog.right(v_cuenta.numero_cuenta, 4),
    'titular_distinto', coalesce(v_cuenta.titular_distinto, false),
    'beneficiario_nombre', case when v_cuenta.titular_distinto then v_cuenta.beneficiario_nombre end,
    'cambiado_en', v_cambiado_en,
    'contratos', pg_catalog.to_jsonb(v_vigentes),
    'pendiente_novedad', v_aviso.novedad_en is null,
    'pendiente_correo', v_aviso.correo_en is null
                        and coalesce(pg_catalog.btrim(v_perfil.correo), '') <> '');
end;
$function$;
revoke all on function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean) to service_role;

create function crm.confirmar_aviso_cambio_cuenta(
  p_solicitud_id uuid, p_reserva uuid, p_novedad boolean, p_correo boolean, p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_aviso crm.cambio_cuenta_avisos%rowtype;
  v_tiene_correo boolean;
  v_completo boolean;
begin
  if (select auth.role()) is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Solo el servicio de avisos confirma avisos';
  end if;
  -- Solo la reserva vigente confirma: un intento viejo nunca libera la reserva de uno nuevo.
  update crm.cambio_cuenta_avisos
     set novedad_en = case when p_novedad and novedad_en is null then pg_catalog.clock_timestamp() else novedad_en end,
         correo_en  = case when p_correo and correo_en is null then pg_catalog.clock_timestamp() else correo_en end,
         reserva = null,
         reclamado_en = null,
         ultimo_error = pg_catalog.left(nullif(pg_catalog.btrim(p_error), ''), 500),
         actualizado_en = pg_catalog.clock_timestamp()
   where solicitud_id = p_solicitud_id
     and p_reserva is not null
     and reserva = p_reserva
  returning * into v_aviso;
  if not found then
    raise exception using errcode = '22023', message = 'La reserva del aviso ya no es válida; vuelve a intentarlo';
  end if;
  select coalesce(pg_catalog.btrim(p.correo), '') <> '' into v_tiene_correo
  from crm.contrato_cuenta_pago_cambios c
  join public.perfiles p on p.id = c.cliente_id
  where c.solicitud_id = p_solicitud_id
  limit 1;
  v_completo := v_aviso.novedad_en is not null
                and (v_aviso.correo_en is not null or not coalesce(v_tiene_correo, false));
  if v_completo then
    -- Solo los contratos que el aviso anunció: los superados por un cambio posterior no se avisan.
    update crm.contrato_cuenta_pago_cambios c
       set notificado_en = pg_catalog.clock_timestamp()
     where c.solicitud_id = p_solicitud_id and c.notificado_en is null
       and exists (select 1 from crm.contrato_cuentas_pago l
                   where l.contrato_id = c.contrato_id and l.cuenta_bancaria_id = c.cuenta_nueva_id)
       and not exists (select 1 from crm.contrato_cuenta_pago_cambios c2
                       where c2.contrato_id = c.contrato_id and c2.cambiado_en > c.cambiado_en);
  end if;
  return pg_catalog.jsonb_build_object(
    'completo', v_completo, 'novedad', v_aviso.novedad_en is not null,
    'correo', v_aviso.correo_en is not null, 'tiene_correo', coalesce(v_tiene_correo, false));
end;
$function$;
revoke all on function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text) from public, anon, authenticated, service_role;
grant execute on function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text) to service_role;

-- ── 8. Comentarios ─────────────────────────────────────────────────────────────────────────
comment on table crm.cuotas_cuenta_pagada is
  'Constancia: cuenta bancaria a la que se pagó cada cuota. origen=registro: la vigente en la fecha del pago, sellada al registrarlo (corregir la fecha re-sella); origen=inferido: backfill con la cuenta contractual (el enlace nació el 25/09 desde el perfil). Solo vale mientras la cuota esté en pagado. Sin claves foráneas a propósito: sobrevive a las eliminaciones auditadas. No se borra. DATOS SENSIBLES por referencia.';
comment on column crm.cuotas_cuenta_pagada.id is 'Identificador del sello.';
comment on column crm.cuotas_cuenta_pagada.cuota_id is 'Cuota de public.cronograma_pagos (sin FK; ver la tabla). Un sello por cuota.';
comment on column crm.cuotas_cuenta_pagada.contrato_id is 'Contrato de la cuota (sin FK).';
comment on column crm.cuotas_cuenta_pagada.cuenta_bancaria_id is 'Cuenta de crm.cuentas_bancarias a la que se pagó (sin FK).';
comment on column crm.cuotas_cuenta_pagada.origen is 'registro = deducida de la fecha del pago al registrarlo; inferido = backfill desde la cuenta contractual.';
comment on column crm.cuotas_cuenta_pagada.sellada_en is 'Cuándo se selló o re-selló.';
comment on table crm.contrato_cuenta_pago_cambios is
  'Historial inmutable de cambios de cuenta de pago de contratos por pedido del cliente (F3, 26/09/2026). Solo notificado_en pasa una vez de NULL a fecha; nada se borra. Sin claves foráneas a propósito: la constancia sobrevive a contratos, cliente, cuentas y personas. DATOS SENSIBLES: motivo y respaldo (correo del cliente).';
comment on column crm.contrato_cuenta_pago_cambios.id is 'Identificador del cambio.';
comment on column crm.contrato_cuenta_pago_cambios.solicitud_id is 'Id de la operación (idempotencia): un cambio de varios contratos comparte solicitud.';
comment on column crm.contrato_cuenta_pago_cambios.contrato_id is 'Contrato cuya cuenta de pago cambió (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.cliente_id is 'Cliente titular del contrato (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.cuenta_anterior_id is 'Cuenta de pago antes del cambio (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.cuenta_nueva_id is 'Cuenta de pago desde el cambio (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';
comment on column crm.contrato_cuenta_pago_cambios.respaldo_ruta is 'Ruta en el bucket privado respaldos-cambio-cuenta del correo del cliente que pide el cambio; respalda una sola solicitud. DATO SENSIBLE.';
comment on column crm.contrato_cuenta_pago_cambios.cambiado_por is 'Administrador que hizo el cambio (id de perfil, sin FK: sobrevive a la eliminación del usuario).';
comment on column crm.contrato_cuenta_pago_cambios.cambiado_en is 'Momento del cambio (hora de la transacción).';
comment on column crm.contrato_cuenta_pago_cambios.notificado_en is 'Aviso al cliente completo (todos sus canales entregados).';
comment on table crm.cambio_cuenta_avisos is 'Estado del aviso al cliente por solicitud de cambio de cuenta de pago: reserva de envío con token (10 min), canales entregados, superado por un cambio posterior, intentos y último error. No se borra.';
comment on column crm.cambio_cuenta_avisos.id is 'Identificador.';
comment on column crm.cambio_cuenta_avisos.solicitud_id is 'Solicitud de crm.contrato_cuenta_pago_cambios.';
comment on column crm.cambio_cuenta_avisos.reserva is 'Token de la reserva en curso: confirmar exige el mismo token.';
comment on column crm.cambio_cuenta_avisos.reclamado_en is 'Inicio de la reserva en curso (se libera al confirmar o a los 10 minutos).';
comment on column crm.cambio_cuenta_avisos.novedad_en is 'Cuándo se publicó la novedad en el portal del cliente.';
comment on column crm.cambio_cuenta_avisos.correo_en is 'Cuándo se envió el correo al cliente.';
comment on column crm.cambio_cuenta_avisos.superada_en is 'El cambio quedó superado por otro posterior: no se avisa.';
comment on column crm.cambio_cuenta_avisos.intentos is 'Reservas de envío realizadas.';
comment on column crm.cambio_cuenta_avisos.ultimo_error is 'Último error de envío (para la pantalla).';
comment on column crm.cambio_cuenta_avisos.creado_en is 'Primera reserva.';
comment on column crm.cambio_cuenta_avisos.actualizado_en is 'Último cambio de estado.';
comment on function private.admin_banca_vigente(uuid) is 'Compuerta de la F3: admin/superadmin activo y con la membresía CRM NO revocada (P04). SECURITY DEFINER porque lee crm.equipo, que authenticated no puede leer; solo responde sí/no y nunca amplía el público de public.es_admin().';
comment on function private.trg_registro_cuenta_pago_no_borrar() is 'Candado: los registros de cuentas de pago (sellos, historial, avisos) no se borran. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.trg_contrato_cuenta_pago_cambios_inmutable() is 'Candado del historial de cambios de cuenta de pago: solo notificado_en NULL→fecha. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.trg_cuotas_cuenta_pagada_solo_resello() is 'Candado del sello: id y cuota inmutables; solo se re-sella la cuenta. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.sellar_cuenta_cuota_pagada() is 'Trigger AFTER en public.cronograma_pagos: al pasar una cuota a pagado sella la cuenta vigente en la fecha del pago; corregir la fecha re-sella lo deducido por fecha. No cambia el registro del pago. SECURITY DEFINER porque quien registra el pago (gestor de cartera) no tiene grants sobre los registros crm.';
comment on function private.trg_contrato_cuenta_pago_inmutable() is 'Candado del enlace contrato→cuenta: id, contrato y fecha inmutables; la cuenta solo cambia con un cambio registrado en crm.contrato_cuenta_pago_cambios en la misma transacción (F3).';
comment on function private.respaldo_cambio_cuenta_permitido(text) is 'Storage: solo admin/superadmin vigente (P04) sube o lee respaldos, con nombre <cliente_uuid>/<uuid>.(pdf|jpg|jpeg|png).';
comment on function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text) is 'Núcleo del cambio de cuenta de pago: solo admin vigente (P04); por contrato entero; sin aviso en curso; respaldo propio y no reutilizado (ruta ni contenido); atómico e idempotente por solicitud (compara todos los datos). SECURITY DEFINER porque authenticated no tiene grants sobre el enlace, el historial ni storage.objects.';
comment on function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text) is 'Puerta (INVOKER) del cambio de cuenta de pago de contratos por pedido del cliente. La usa la ventana «Cuentas» del portal (solo admin).';
comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes y cuotas pagadas por cuenta (con las inferidas aparte). Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre enlace ni sellos. DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago. Solo admin.';
comment on function private.cambios_cuenta_pago_cliente_autorizado(uuid) is 'Historial de cambios de cuenta de pago del cliente con el estado del aviso. Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre el historial. DATOS SENSIBLES.';
comment on function crm.cambios_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) del historial de cambios de cuenta de pago del cliente. Solo admin.';
comment on function private.contratos_vigentes_de_cambio(uuid) is 'Contratos de una solicitud que siguen cobrando en la cuenta de ese cambio (sin cambios posteriores). INVOKER; la llama crm.reclamar_aviso_cambio_cuenta.';
comment on function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean) is 'Paso 1 del aviso al cliente: reserva el envío (token, 10 min), dice qué canales faltan y devuelve los datos (cuenta nueva tapada, titular, solo contratos vigentes). No avisa cambios superados. Solo service_role y para un actor admin vigente. SECURITY DEFINER porque escribe el estado del aviso.';
comment on function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text) is 'Paso 2 del aviso al cliente: con el token de la reserva, registra los canales entregados y el error; sella notificado_en cuando llegó por todos sus canales y solo en los contratos anunciados. Solo service_role. SECURITY DEFINER porque escribe el historial.';

-- ── 9. Postflight ──────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_pagadas_con_cuenta bigint;
  v_selladas bigint;
  v_f record;
begin
  select count(*) into v_pagadas_con_cuenta
  from public.cronograma_pagos cp join crm.contrato_cuentas_pago l on l.contrato_id = cp.contrato_id
  where cp.estado = 'pagado';
  select count(*) into v_selladas from crm.cuotas_cuenta_pagada where origen = 'inferido';
  if v_selladas <> v_pagadas_con_cuenta
     or exists (select 1 from crm.cuotas_cuenta_pagada where origen <> 'inferido') then
    raise exception 'CAMBIO_CUENTA: backfill incompleto (% sellos de % pagadas con cuenta)', v_selladas, v_pagadas_con_cuenta;
  end if;

  -- Ninguna clave foránea entra ni sale de los registros: las eliminaciones auditadas de
  -- contratos y de usuarios no ven dependencias nuevas.
  if exists (
    select 1 from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and (c.conrelid in ('crm.cuotas_cuenta_pagada'::regclass, 'crm.contrato_cuenta_pago_cambios'::regclass,
                          'crm.cambio_cuenta_avisos'::regclass)
           or c.confrelid in ('crm.cuotas_cuenta_pagada'::regclass, 'crm.contrato_cuenta_pago_cambios'::regclass,
                              'crm.cambio_cuenta_avisos'::regclass))
  ) then
    raise exception 'CAMBIO_CUENTA: los registros no deben tener claves foráneas';
  end if;

  -- Nadie de la API toca las tablas.
  if exists (
    select 1
    from (values ('crm.cuotas_cuenta_pagada'::regclass), ('crm.contrato_cuenta_pago_cambios'::regclass),
                 ('crm.cambio_cuenta_avisos'::regclass)) t(oid)
    cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol)
    where pg_catalog.has_table_privilege(r.rol, t.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  ) or exists (
    select 1 from pg_catalog.pg_class t
    where t.oid in ('crm.cuotas_cuenta_pagada'::regclass, 'crm.contrato_cuenta_pago_cambios'::regclass,
                    'crm.cambio_cuenta_avisos'::regclass)
      and not t.relrowsecurity
  ) then
    raise exception 'CAMBIO_CUENTA: una tabla de registro quedó accesible desde la API o sin RLS';
  end if;

  -- EXECUTE exacto por función (rol NULL = solo su dueño) y search_path vacío.
  for v_f in
    select * from (values
      ('private.admin_banca_vigente(uuid)', 'authenticated'),
      ('private.trg_registro_cuenta_pago_no_borrar()', null),
      ('private.trg_contrato_cuenta_pago_cambios_inmutable()', null),
      ('private.trg_cuotas_cuenta_pagada_solo_resello()', null),
      ('private.sellar_cuenta_cuota_pagada()', null),
      ('private.respaldo_cambio_cuenta_permitido(text)', 'authenticated'),
      ('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)', 'authenticated'),
      ('crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)', 'authenticated'),
      ('private.contratos_cuenta_pago_cliente_autorizado(uuid)', 'authenticated'),
      ('crm.contratos_cuenta_pago_cliente_fn(uuid)', 'authenticated'),
      ('private.cambios_cuenta_pago_cliente_autorizado(uuid)', 'authenticated'),
      ('crm.cambios_cuenta_pago_cliente_fn(uuid)', 'authenticated'),
      ('private.contratos_vigentes_de_cambio(uuid)', null),
      ('crm.reclamar_aviso_cambio_cuenta(uuid,uuid,boolean)', 'service_role'),
      ('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)', 'service_role')
    ) as f(firma, rol)
  loop
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'CAMBIO_CUENTA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'CAMBIO_CUENTA: search_path inesperado en %', v_f.firma;
    end if;
  end loop;

  if (select count(*) from pg_catalog.pg_trigger
      where tgrelid = 'public.cronograma_pagos'::regclass
        and tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert', 'trg_cronograma_pagos_20_sellar_cuenta_update')) <> 2 then
    raise exception 'CAMBIO_CUENTA: faltan los triggers del sello';
  end if;
  if (select count(*) from pg_catalog.pg_policies
      where schemaname = 'storage' and tablename = 'objects' and policyname like 'respaldo\_cambio\_cuenta\_%') <> 7 then
    raise exception 'CAMBIO_CUENTA: las políticas del bucket no son las 7 esperadas';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$registro$])
on conflict (version) do nothing;
select version, name from supabase_migrations.schema_migrations where version = '20260926204051';
commit;
