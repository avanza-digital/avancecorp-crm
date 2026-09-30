ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: Cuentas de Gloria · F3 — cambiar la cuenta de pago de contratos por pedido del cliente (LEVEL 3: pagos)

Tu trabajo es REFUTAR: busca fallos reales en SQL (autorización, válvula del candado, carreras
con el registro de pagos, idempotencia, Storage, fugas, sello de cuotas), en la Edge Function
(auth, idempotencia del aviso, fugas en el texto/HTML, CORS) y en la pantalla (estados, reintentos,
subidas, XSS). Sin hallazgo sin evidencia.

## Decisiones de Miguel (dueño, NO son hallazgos)
- Por contrato entero; solo admin y superadmin (public.es_admin()); aviso al cliente por portal y
  correo; respaldo obligatorio = el correo del cliente donde pide el cambio (archivo PDF/imagen).
- Todo el que ya ve la cuenta la ve completa (F2b): no se discute el tapado.

## Contexto verificado del sistema (producción)
- `crm.contrato_cuentas_pago`: UNA fila por contrato (contrato_id unique) con la cuenta de pago; hasta
  hoy inmutable por `private.trg_contrato_cuenta_pago_inmutable` (BEFORE UPDATE); coherencia
  cliente/moneda por otro trigger; auditada. authenticated no tiene grants sobre ella.
- Registrar un pago = UPDATE de public.cronograma_pagos a estado 'pagado' (desde el portal, por RLS
  de gestor de cartera). Un trigger BEFORE `private.exigir_cuenta_pago_cronograma` exige el enlace y
  lo bloquea `for share of cp, ct` hasta el COMMIT. La pantalla de Pagos y su Excel leen la cuenta del
  contrato en vivo por `crm.cuentas_pago_contratos_fn` (solo gestor de cartera).
- Estados de contrato: activo, vencido, renovado, retirado. Cuotas: pendiente, pagado, vencido, trasladado.
- En prod: 915 cuotas pagadas, 877 con enlace (las 38 restantes son de contratos sin cuenta de pago,
  pendientes de conciliación). El PDF firmado del contrato imprime la cuenta (no se regenera: decisión).
- Storage de Supabase impide borrar objetos/buckets por SQL (storage.protect_delete).
- Patrón de puertas: `crm.*` INVOKER que delega en `private.*` DEFINER con EXECUTE a authenticated
  (aplicado ya en prod; private no está expuesto en la API).

## Migración (texto íntegro)
```sql
-- Cuentas de Gloria · F3.1: cambiar la cuenta de pago de contratos por pedido del cliente.
--
-- Qué hace (servidor; la pantalla es F3.2 y el aviso al cliente F3.3):
--   1. Sello: cada cuota que pasa a 'pagado' guarda la cuenta a la que se pagó
--      (crm.cuotas_cuenta_pagada). Backfill de las ya pagadas con su cuenta contractual
--      actual, que no pudo cambiar hasta hoy (el enlace era inmutable).
--   2. Historial de cambios crm.contrato_cuenta_pago_cambios (inmutable salvo el sello
--      único de aviso notificado_en).
--   3. El candado del enlace contrato→cuenta (private.trg_contrato_cuenta_pago_inmutable)
--      pasa a admitir UN caso: el cambio de cuenta registrado en ese historial en la MISMA
--      transacción. Todo lo demás sigue inmutable.
--   4. Operación atómica crm.cambiar_cuenta_pago_contratos (puerta INVOKER → núcleo
--      private DEFINER): solo public.es_admin(); por contrato entero; cuenta nueva vigente,
--      del mismo cliente y moneda; contratos del cliente en 'activo'/'vencido' con cuenta
--      de pago; motivo y respaldo (correo del cliente) obligatorios; todo o nada;
--      idempotente por p_solicitud_id.
--   5. Lecturas para la pantalla (solo admin): contratos abiertos con su cuenta, cuotas
--      pendientes y pagadas por cuenta; historial de cambios.
--   6. Bucket privado 'respaldos-cambio-cuenta' (PDF/JPG/PNG ≤10 MB), solo admin sube y
--      lee; nadie sustituye ni borra.
--   7. crm.reclamar_aviso_cambio_cuenta: sello atómico del aviso (solo service_role; lo usa
--      la Edge Function de F3.3).
--
-- Decisiones de Miguel (26/09/2026): por contrato entero; solo admin y superadmin; aviso al
-- cliente por portal y correo; respaldo = el correo del cliente donde pide el cambio.
-- Toca objetos de public (dos triggers AFTER en public.cronograma_pagos) y de storage
-- (bucket y políticas): mostrado a Miguel antes de aplicar.
--
-- Reversión: ../scripts/cuentas-gloria/reversa-cambio-cuenta-pago.sql (se niega si ya hay
-- cambios registrados: a partir de ahí el historial es la única verdad de a dónde se paga).
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
     or to_regclass('public.cronograma_pagos') is null or to_regclass('storage.objects') is null
     or to_regprocedure('public.es_admin()') is null
     or to_regprocedure('private.log_audit_crm()') is null then
    raise exception 'CAMBIO_CUENTA: faltan dependencias';
  end if;
  if to_regclass('crm.cuotas_cuenta_pagada') is not null
     or to_regclass('crm.contrato_cuenta_pago_cambios') is not null then
    raise exception 'CAMBIO_CUENTA: los objetos ya existen; no se sobrescriben';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'CAMBIO_CUENTA: authenticated necesita USAGE sobre private para las puertas INVOKER';
  end if;
end;
$precondicion$;

-- ── 1. Sello de la cuenta en cada cuota pagada ─────────────────────────────────────────────
create table crm.cuotas_cuenta_pagada (
  cuota_id            uuid primary key references public.cronograma_pagos(id) on delete cascade,
  contrato_id         uuid not null references public.contratos(id) on delete cascade,
  cuenta_bancaria_id  uuid not null references crm.cuentas_bancarias(id) on delete restrict,
  sellada_en          timestamptz not null default now()
);
alter table crm.cuotas_cuenta_pagada enable row level security;
revoke all on crm.cuotas_cuenta_pagada from public, anon, authenticated;
create index cuotas_cuenta_pagada_contrato_idx on crm.cuotas_cuenta_pagada (contrato_id);
create index cuotas_cuenta_pagada_cuenta_idx on crm.cuotas_cuenta_pagada (cuenta_bancaria_id);

create function private.sellar_cuenta_cuota_pagada()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- La cuenta contractual vigente en el momento en que se registra el pago. Si el
  -- contrato no tiene cuenta, el trigger BEFORE de exigencia ya rechazó el pago.
  insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id)
  select new.id, new.contrato_id, l.cuenta_bancaria_id
  from crm.contrato_cuentas_pago l
  where l.contrato_id = new.contrato_id
  on conflict (cuota_id) do update
    set contrato_id = excluded.contrato_id,
        cuenta_bancaria_id = excluded.cuenta_bancaria_id,
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
  after update of estado on public.cronograma_pagos
  for each row when (new.estado = 'pagado' and old.estado is distinct from 'pagado')
  execute function private.sellar_cuenta_cuota_pagada();

-- Backfill: el enlace no pudo cambiar hasta hoy, así que la cuenta contractual actual es
-- la cuenta en la que se registró cada pago existente.
insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id)
select cp.id, cp.contrato_id, l.cuenta_bancaria_id
from public.cronograma_pagos cp
join crm.contrato_cuentas_pago l on l.contrato_id = cp.contrato_id
where cp.estado = 'pagado';

create trigger trg_audit_cuotas_cuenta_pagada
  after insert or delete or update on crm.cuotas_cuenta_pagada
  for each row execute function private.log_audit_crm();

-- ── 2. Historial de cambios de cuenta de pago ──────────────────────────────────────────────
create table crm.contrato_cuenta_pago_cambios (
  id                  uuid primary key default gen_random_uuid(),
  solicitud_id        uuid not null,
  contrato_id         uuid not null references public.contratos(id) on delete cascade,
  cliente_id          uuid not null references public.perfiles(id) on delete cascade,
  cuenta_anterior_id  uuid not null references crm.cuentas_bancarias(id) on delete restrict,
  cuenta_nueva_id     uuid not null references crm.cuentas_bancarias(id) on delete restrict,
  motivo              text not null
                      constraint contrato_cuenta_pago_cambios_motivo_valido
                      check (motivo = btrim(motivo) and length(motivo) between 5 and 500),
  respaldo_ruta       text not null
                      constraint contrato_cuenta_pago_cambios_respaldo_valido
                      check (respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$'),
  cambiado_por        uuid references public.perfiles(id) on delete set null,
  cambiado_en         timestamptz not null default now(),
  notificado_en       timestamptz,
  constraint contrato_cuenta_pago_cambios_solicitud_contrato_uq unique (solicitud_id, contrato_id),
  constraint contrato_cuenta_pago_cambios_cuentas_distintas check (cuenta_anterior_id <> cuenta_nueva_id)
);
alter table crm.contrato_cuenta_pago_cambios enable row level security;
revoke all on crm.contrato_cuenta_pago_cambios from public, anon, authenticated;
create index contrato_cuenta_pago_cambios_contrato_idx on crm.contrato_cuenta_pago_cambios (contrato_id, cambiado_en desc);
create index contrato_cuenta_pago_cambios_cliente_idx on crm.contrato_cuenta_pago_cambios (cliente_id, cambiado_en desc);
create index contrato_cuenta_pago_cambios_anterior_idx on crm.contrato_cuenta_pago_cambios (cuenta_anterior_id);
create index contrato_cuenta_pago_cambios_nueva_idx on crm.contrato_cuenta_pago_cambios (cuenta_nueva_id);
create index contrato_cuenta_pago_cambios_por_idx on crm.contrato_cuenta_pago_cambios (cambiado_por)
  where cambiado_por is not null;

create function private.trg_contrato_cuenta_pago_cambios_inmutable()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- Solo el sello del aviso, una vez: NULL → fecha. El resto es historia.
  if row(new.id, new.solicitud_id, new.contrato_id, new.cliente_id, new.cuenta_anterior_id,
         new.cuenta_nueva_id, new.motivo, new.respaldo_ruta, new.cambiado_en)
     is distinct from
     row(old.id, old.solicitud_id, old.contrato_id, old.cliente_id, old.cuenta_anterior_id,
         old.cuenta_nueva_id, old.motivo, old.respaldo_ruta, old.cambiado_en)
     or (old.notificado_en is not null and new.notificado_en is distinct from old.notificado_en)
     or (new.cambiado_por is distinct from old.cambiado_por
         and not (new.cambiado_por is null
                  and not exists (select 1 from public.perfiles p where p.id = old.cambiado_por))) then
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
create trigger trg_audit_contrato_cuenta_pago_cambios
  after insert or delete or update on crm.contrato_cuenta_pago_cambios
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
  -- transacción (cambiado_en = now() de la transacción). Nadie más puede moverla.
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

-- ── 4. Respaldo: bucket privado, solo admin sube y lee; nadie sustituye ni borra ────────────
-- Tolera el bucket si ya existe (una reversa no puede borrarlo: storage.protect_delete),
-- pero exige su configuración privada exacta.
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
  select coalesce((select public.es_admin()), false)
     and coalesce(p_nombre ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false);
$function$;
revoke all on function private.respaldo_cambio_cuenta_permitido(text) from public, anon, authenticated, service_role;
grant execute on function private.respaldo_cambio_cuenta_permitido(text) to authenticated;

create policy respaldo_cambio_cuenta_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'respaldos-cambio-cuenta' and private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_select on storage.objects for select to authenticated
  using (bucket_id = 'respaldos-cambio-cuenta' and private.respaldo_cambio_cuenta_permitido(name));
-- Fronteras RESTRICTIVE (mismo patrón que f4-comprobantes): ninguna política permisiva de
-- otro bucket abre estos respaldos ni permite sustituir o borrar sus bytes.
create policy respaldo_cambio_cuenta_insert_frontera on storage.objects as restrictive for insert to authenticated
  with check (bucket_id <> 'respaldos-cambio-cuenta' or private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_select_frontera on storage.objects as restrictive for select to authenticated
  using (bucket_id <> 'respaldos-cambio-cuenta' or private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_update_frontera on storage.objects as restrictive for update to authenticated
  using (bucket_id <> 'respaldos-cambio-cuenta') with check (bucket_id <> 'respaldos-cambio-cuenta');
create policy respaldo_cambio_cuenta_delete_frontera on storage.objects as restrictive for delete to authenticated
  using (bucket_id <> 'respaldos-cambio-cuenta');

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
  v_enlaces integer := 0;
  v_hechos integer;
begin
  if v_actor is null or not coalesce((select public.es_admin()), false) then
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

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_solicitud_id::text, 0));
  select count(*),
         bool_and(c.cliente_id = p_cliente_id and c.cuenta_nueva_id = p_cuenta_nueva_id),
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

  -- Respaldo: el correo del cliente, ya subido al bucket privado y dentro de su carpeta.
  if p_respaldo_ruta is null
     or pg_catalog.split_part(p_respaldo_ruta, '/', 1) is distinct from p_cliente_id::text
     or not coalesce(private.respaldo_cambio_cuenta_permitido(p_respaldo_ruta), false) then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;
  select * into v_obj from storage.objects
  where bucket_id = 'respaldos-cambio-cuenta' and name = p_respaldo_ruta
  for key share;
  if not found
     or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
     or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;

  -- Cuenta nueva: del cliente y vigente.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_nueva_id for share;
  if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
    raise exception using errcode = '22023', message = 'La cuenta nueva no es de este cliente';
  end if;
  if not v_cuenta.activa then
    raise exception using errcode = '22023', message = 'La cuenta nueva ya no está vigente';
  end if;

  -- Contratos: del cliente, abiertos y en la moneda de la cuenta.
  for v_ct in
    select ct.id, ct.cliente_id, ct.moneda, ct.estado, ct.numero_contrato
    from public.contratos ct
    where ct.id = any(v_ids)
    order by ct.id
    for update
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
    v_enlaces := v_enlaces + 1;
  end loop;
  if v_enlaces <> pg_catalog.cardinality(v_ids) then
    raise exception using errcode = '22023', message = 'Algún contrato no existe';
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
  perform 1 from crm.contrato_cuentas_pago l where l.contrato_id = any(v_ids) order by l.contrato_id for update;

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

-- ── 6. Lecturas para la pantalla (solo admin) ──────────────────────────────────────────────
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
  if not coalesce((select public.es_admin()), false) then
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
                    'numero_cuenta', sb.numero_cuenta, 'cuotas', s.n) order by s.n desc)
           from (select q.cuenta_bancaria_id, count(*) as n
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
  motivo text, respaldo_ruta text, cambiado_por_nombre text, notificado_en timestamptz
)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if not coalesce((select public.es_admin()), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede ver el historial de cuentas de pago';
  end if;
  return query
  select c.id, c.solicitud_id, c.cambiado_en, ct.numero_contrato,
         a.banco, a.numero_cuenta, n.banco, n.numero_cuenta,
         c.motivo, c.respaldo_ruta, pr.nombre_completo, c.notificado_en
  from crm.contrato_cuenta_pago_cambios c
  join public.contratos ct on ct.id = c.contrato_id
  join crm.cuentas_bancarias a on a.id = c.cuenta_anterior_id
  join crm.cuentas_bancarias n on n.id = c.cuenta_nueva_id
  left join public.perfiles pr on pr.id = c.cambiado_por and pr.rol <> 'cliente'
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
  motivo text, respaldo_ruta text, cambiado_por_nombre text, notificado_en timestamptz
)
language sql
stable security invoker
set search_path to ''
as $function$
  select * from private.cambios_cuenta_pago_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.cambios_cuenta_pago_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.cambios_cuenta_pago_cliente_fn(uuid) to authenticated;

-- ── 7. Aviso al cliente: sello atómico, solo para la Edge Function (service_role) ─────────
create function crm.reclamar_aviso_cambio_cuenta(p_solicitud_id uuid, p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_cliente uuid;
  v_reclamadas integer := 0;
  v_datos jsonb;
begin
  select c.cliente_id into v_cliente
  from crm.contrato_cuenta_pago_cambios c
  where c.solicitud_id = p_solicitud_id
  limit 1;
  if v_cliente is null then
    return pg_catalog.jsonb_build_object('encontrada', false);
  end if;
  if not p_dry_run then
    update crm.contrato_cuenta_pago_cambios
       set notificado_en = pg_catalog.clock_timestamp()
     where solicitud_id = p_solicitud_id and notificado_en is null;
    get diagnostics v_reclamadas = row_count;
    if v_reclamadas = 0 then
      return pg_catalog.jsonb_build_object('encontrada', true, 'ya_notificada', true);
    end if;
  end if;
  select pg_catalog.jsonb_build_object(
           'encontrada', true, 'ya_notificada', false, 'dry_run', p_dry_run,
           'cliente_id', p.id, 'nombre_completo', p.nombre_completo, 'nombres', p.nombres,
           'correo', p.correo, 'activo', p.activo,
           'banco_nuevo', n.banco, 'moneda', n.moneda,
           'ultimos_nuevo', pg_catalog.right(n.numero_cuenta, 4),
           'contratos', (select pg_catalog.jsonb_agg(ct.numero_contrato order by ct.numero_contrato)
                         from crm.contrato_cuenta_pago_cambios c2
                         join public.contratos ct on ct.id = c2.contrato_id
                         where c2.solicitud_id = p_solicitud_id))
    into v_datos
  from crm.contrato_cuenta_pago_cambios c
  join public.perfiles p on p.id = c.cliente_id
  join crm.cuentas_bancarias n on n.id = c.cuenta_nueva_id
  where c.solicitud_id = p_solicitud_id
  limit 1;
  return v_datos;
end;
$function$;
revoke all on function crm.reclamar_aviso_cambio_cuenta(uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function crm.reclamar_aviso_cambio_cuenta(uuid, boolean) to service_role;

-- ── 8. Comentarios ─────────────────────────────────────────────────────────────────────────
comment on table crm.cuotas_cuenta_pagada is
  'Sello: cuenta bancaria a la que se registró el pago de cada cuota (vigente al pasar a pagado). Solo vale mientras la cuota esté en estado pagado; si se vuelve a pagar, se re-sella. DATOS SENSIBLES por referencia.';
comment on column crm.cuotas_cuenta_pagada.cuota_id is 'Cuota de public.cronograma_pagos.';
comment on column crm.cuotas_cuenta_pagada.contrato_id is 'Contrato de la cuota (para agrupar sin join).';
comment on column crm.cuotas_cuenta_pagada.cuenta_bancaria_id is 'Cuenta contractual vigente cuando se registró el pago.';
comment on column crm.cuotas_cuenta_pagada.sellada_en is 'Cuándo se selló (backfill: fecha de la migración).';
comment on table crm.contrato_cuenta_pago_cambios is
  'Historial inmutable de cambios de cuenta de pago de contratos por pedido del cliente (F3, 26/09/2026). Solo notificado_en pasa una vez de NULL a fecha. DATOS SENSIBLES: motivo y respaldo (correo del cliente).';
comment on column crm.contrato_cuenta_pago_cambios.solicitud_id is 'Id de la operación (idempotencia): un cambio de varios contratos comparte solicitud.';
comment on column crm.contrato_cuenta_pago_cambios.contrato_id is 'Contrato cuya cuenta de pago cambió.';
comment on column crm.contrato_cuenta_pago_cambios.cliente_id is 'Cliente titular del contrato.';
comment on column crm.contrato_cuenta_pago_cambios.cuenta_anterior_id is 'Cuenta de pago antes del cambio.';
comment on column crm.contrato_cuenta_pago_cambios.cuenta_nueva_id is 'Cuenta de pago desde el cambio.';
comment on column crm.contrato_cuenta_pago_cambios.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';
comment on column crm.contrato_cuenta_pago_cambios.respaldo_ruta is 'Ruta en el bucket privado respaldos-cambio-cuenta del correo del cliente que pide el cambio. DATO SENSIBLE.';
comment on column crm.contrato_cuenta_pago_cambios.cambiado_por is 'Administrador que hizo el cambio.';
comment on column crm.contrato_cuenta_pago_cambios.cambiado_en is 'Momento del cambio (hora de la transacción).';
comment on column crm.contrato_cuenta_pago_cambios.notificado_en is 'Sello único del aviso al cliente (portal + correo).';
comment on function private.sellar_cuenta_cuota_pagada() is 'Trigger AFTER en public.cronograma_pagos: sella la cuenta contractual vigente al pasar una cuota a pagado.';
comment on function private.trg_contrato_cuenta_pago_cambios_inmutable() is 'Candado del historial de cambios de cuenta de pago: solo notificado_en NULL→fecha.';
comment on function private.trg_contrato_cuenta_pago_inmutable() is 'Candado del enlace contrato→cuenta: id, contrato y fecha inmutables; la cuenta solo cambia con un cambio registrado en crm.contrato_cuenta_pago_cambios en la misma transacción (F3).';
comment on function private.respaldo_cambio_cuenta_permitido(text) is 'Storage: solo admin/superadmin sube o lee respaldos, con nombre <cliente_uuid>/<uuid>.(pdf|jpg|jpeg|png).';
comment on function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text) is 'Núcleo del cambio de cuenta de pago: solo es_admin(); por contrato entero; atómico e idempotente por solicitud. SECURITY DEFINER porque authenticated no tiene grants sobre las tablas.';
comment on function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text) is 'Puerta (INVOKER) del cambio de cuenta de pago de contratos por pedido del cliente. La usa la ventana «Cuentas» del portal (solo admin).';
comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes y cuotas pagadas por cuenta. Solo es_admin(). DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago. Solo admin.';
comment on function private.cambios_cuenta_pago_cliente_autorizado(uuid) is 'Historial de cambios de cuenta de pago del cliente. Solo es_admin(). DATOS SENSIBLES.';
comment on function crm.cambios_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) del historial de cambios de cuenta de pago del cliente. Solo admin.';
comment on function crm.reclamar_aviso_cambio_cuenta(uuid, boolean) is 'Sello atómico del aviso al cliente de un cambio de cuenta de pago y datos para redactarlo (cuenta nueva tapada). Solo service_role (Edge notificar-cambio-cuenta).';

-- ── 9. Postflight ──────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_pagadas_con_cuenta bigint;
  v_selladas bigint;
begin
  select count(*) into v_pagadas_con_cuenta
  from public.cronograma_pagos cp join crm.contrato_cuentas_pago l on l.contrato_id = cp.contrato_id
  where cp.estado = 'pagado';
  select count(*) into v_selladas from crm.cuotas_cuenta_pagada;
  if v_selladas <> v_pagadas_con_cuenta then
    raise exception 'CAMBIO_CUENTA: backfill incompleto (% sellos de % pagadas con cuenta)', v_selladas, v_pagadas_con_cuenta;
  end if;
  if pg_catalog.has_table_privilege('authenticated', 'crm.contrato_cuenta_pago_cambios', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'crm.cuotas_cuenta_pagada', 'SELECT')
     or pg_catalog.has_function_privilege('anon', 'crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'crm.reclamar_aviso_cambio_cuenta(uuid,boolean)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', 'crm.reclamar_aviso_cambio_cuenta(uuid,boolean)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)', 'EXECUTE') then
    raise exception 'CAMBIO_CUENTA: permisos inesperados tras aplicar';
  end if;
  if (select count(*) from pg_catalog.pg_trigger
      where tgrelid = 'public.cronograma_pagos'::regclass
        and tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert', 'trg_cronograma_pagos_20_sellar_cuenta_update')) <> 2 then
    raise exception 'CAMBIO_CUENTA: faltan los triggers del sello';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Evidencia del ensayo (banco Docker, datos ficticios, ROLLBACK)
- Catálogo antes/después: solo piezas nuevas + el candado modificado; reversa → catálogo idéntico al base (con el bucket conservado y cerrado).
- Prueba: sello al nacer pagada; permisos (operaciones, analista, cliente 42501; anon 42501); reglas 22023 (respaldo inexistente/de otro cliente/nulo, motivo corto, cuenta ajena/retirada, contrato cerrado/otra moneda/sin cuenta, misma cuenta, repetidos, vacío, todo-o-nada sin efectos); cambio K1,K2→B con 2 filas de historial; doble clic no duplica; solicitud reutilizada con otros datos rechazada; cuota pagada antes sigue sellada en A y la pagada después en B; el enlace no cambia sin historial; el historial no se reescribe; lecturas admin sí / operaciones 42501; aviso: dry_run no sella, primer reclamo trae datos (••••0002), segundo ya_notificada, sello no reescribible, authenticated sin EXECUTE; Storage: admin sube/lee con nombre válido, nombre inválido rechazado, nadie sustituye ni borra, operaciones ni lee ni sube.
- Mutantes CAZADOS: núcleo sin es_admin; candado sin exigir historial; núcleo sin exigir respaldo; sello no-op.

## Edge Function notificar-cambio-cuenta (verify_jwt TRUE al desplegar)
```ts
/**
 * Edge Function: notificar-cambio-cuenta (F3.3, 26/09/2026)
 *
 * Avisa al cliente que su cuenta de pago cambió (por su pedido), por 2 canales:
 *   1) Novedad in-portal (tabla `novedades`) → badge en vivo.
 *   2) Correo (Resend) con la plantilla institucional.
 *
 * Lo invoca el panel admin (ventana «Cuentas») justo después de
 * `crm.cambiar_cuenta_pago_contratos`, con `{ solicitud_id }`.
 *
 * Idempotencia: `crm.reclamar_aviso_cambio_cuenta` sella `notificado_en` de forma atómica
 * ANTES de enviar; un reintento o doble clic devuelve `ya_notificada` y no duplica.
 * `dry_run: true` devuelve el texto que se enviaría, sin sellar ni enviar.
 *
 * verify_jwt: TRUE (la puerta de Supabase exige un JWT válido) y, además, aquí dentro
 * solo pasan admin/superadmin activos.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { plantillaEmail, redactarAviso } from './aviso.ts'

const ALLOWED_ORIGINS = new Set([
  'https://miavance.com',
  'https://www.miavance.com',
])

function corsHeaders(req: Request) {
  const origin = req.headers.get('Origin') || ''
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'https://miavance.com',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

function json(cors: Record<string, string>, payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

Deno.serve(async (req) => {
  const cors = corsHeaders(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json(cors, { error: 'Método no permitido' }, 405)

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    /* ---------- AUTENTICACIÓN: solo admin/superadmin activos ---------- */
    const token = req.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) return json(cors, { error: 'No autorizado' }, 401)
    const { data: { user } } = await supabase.auth.getUser(token)
    if (!user) return json(cors, { error: 'No autorizado' }, 401)
    const { data: perfil } = await supabase
      .from('perfiles').select('rol, activo').eq('id', user.id).single()
    if (!perfil?.activo || !['admin', 'superadmin'].includes(perfil.rol)) {
      return json(cors, { error: 'No autorizado' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    const solicitudId: string = body?.solicitud_id
    const dryRun: boolean = body?.dry_run === true
    if (typeof solicitudId !== 'string' || !UUID.test(solicitudId)) {
      return json(cors, { error: 'solicitud_id inválido' }, 400)
    }

    /* ---------- CLAIM ATÓMICO + DATOS ---------- */
    const { data: datos, error: errClaim } = await supabase.schema('crm')
      .rpc('reclamar_aviso_cambio_cuenta', { p_solicitud_id: solicitudId, p_dry_run: dryRun })
    if (errClaim) throw errClaim
    if (!datos?.encontrada) return json(cors, { error: 'Cambio no encontrado' }, 404)
    if (datos.ya_notificada) return json(cors, { success: true, ya_notificada: true })

    const { titulo, mensaje } = redactarAviso(datos)
    if (dryRun) return json(cors, { success: true, dry_run: true, correo: datos.correo, titulo, mensaje })
    if (!datos.activo) return json(cors, { success: true, novedad: false, correo: false, detalle: 'Cliente inactivo' })

    /* ---------- 1) NOVEDAD EN EL PORTAL ---------- */
    const { error: errNov } = await supabase.from('novedades').insert({
      titulo, mensaje, destinatario_id: datos.cliente_id, enviado_por: null,
    })
    if (errNov) console.warn('[notificar-cambio-cuenta] novedad falló:', errNov.message)

    /* ---------- 2) CORREO ---------- */
    let correo = false
    if (datos.correo) {
      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: 'Avance Corp <info@miavance.com>',
            to: [datos.correo],
            subject: titulo,
            html: plantillaEmail(datos.nombre_completo || 'estimado cliente', titulo, mensaje),
          }),
        })
        correo = res.ok
        if (!res.ok) console.warn('[notificar-cambio-cuenta] Resend respondió', res.status)
      } catch (e) {
        console.warn('[notificar-cambio-cuenta] correo falló:', e)
      }
    }

    return json(cors, { success: true, novedad: !errNov, correo })
  } catch (error) {
    console.error('[notificar-cambio-cuenta] error:', error)
    return json(cors, { error: 'No se pudo enviar el aviso' }, 500)
  }
})
```
```ts
// Texto del aviso al cliente por un cambio de su cuenta de pago (F3.3, 26/09/2026).
// Puro y sin red: lo prueba aviso.test.ts. La cuenta nueva va TAPADA (••••1234).

export type DatosAviso = {
  nombre_completo: string | null
  nombres: string | null
  banco_nuevo: string
  moneda: string
  ultimos_nuevo: string
  contratos: string[]
}

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

export function redactarAviso(d: DatosAviso): { titulo: string; mensaje: string } {
  const nombrePila = (d.nombres || d.nombre_completo || 'estimado cliente').split(' ')[0]
  const moneda = d.moneda === 'USD' ? 'dólares' : 'soles'
  const lista = d.contratos.length === 1
    ? `del contrato ${d.contratos[0]}`
    : `de los contratos ${d.contratos.slice(0, -1).join(', ')} y ${d.contratos[d.contratos.length - 1]}`
  const titulo = 'Cambio de tu cuenta de pago'
  const mensaje = `Hola ${nombrePila}, atendimos tu pedido: desde hoy los pagos ${lista} se depositarán en tu cuenta ${d.banco_nuevo} en ${moneda} terminada en ••••${d.ultimos_nuevo}. Los pagos ya realizados no cambian.\n\nSi tú no solicitaste este cambio, comunícate de inmediato con Avance Corp.`
  return { titulo, mensaje }
}

export function plantillaEmail(nombre: string, titulo: string, mensaje: string): string {
  const nombreEsc = escapeHtml(nombre)
  const tituloEsc = escapeHtml(titulo)
  const mensajeEsc = escapeHtml(mensaje).replace(/\n/g, '<br>')
  const preheader = escapeHtml(mensaje.slice(0, 110).replace(/\s+/g, ' ').trim())
  const etiqueta = 'CAMBIO DE CUENTA DE PAGO'

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="x-apple-disable-message-reformatting">
// … plantillaEmail: copia de la plantilla institucional de notificar-pagos (escapeHtml de nombre, título y mensaje)
```
Tests Deno del aviso: 4/4 (texto, varios contratos, nunca más de 4 dígitos, escape HTML).

## Portal: núcleo puro nuevo (js/admin/cambio-cuenta-core.js)
```js
// Cambio de la cuenta de pago de contratos por pedido del cliente (F3, 26/09/2026).
// Núcleo puro de la ventana «Cuentas»: validaciones, contratos elegibles, ruta del
// respaldo (el correo del cliente) y textos. Sin DOM ni red: lo prueba
// tests/cambio-cuenta-core.test.mjs. La frontera real está en el servidor
// (crm.cambiar_cuenta_pago_contratos): esto solo da buena experiencia.

export const BUCKET_RESPALDOS = 'respaldos-cambio-cuenta'
export const MAX_RESPALDO_BYTES = 10 * 1024 * 1024
const TIPOS = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png' }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function puedeCambiarCuentaPago(rol) {
  return rol === 'admin' || rol === 'superadmin'
}

export function validarRespaldo(archivo) {
  if (!archivo) return 'Adjunta el correo del cliente donde pide el cambio (PDF o imagen).'
  if (!TIPOS[archivo.type]) return 'El respaldo debe ser PDF, JPG o PNG.'
  if (!(archivo.size > 0)) return 'El archivo del respaldo está vacío.'
  if (archivo.size > MAX_RESPALDO_BYTES) return 'El respaldo no puede superar 10 MB.'
  return null
}

// Misma forma que exige el servidor: <cliente_uuid>/<uuid>.(pdf|jpg|png)
export function rutaRespaldo(clienteId, archivoId, archivo) {
  if (!UUID.test(String(clienteId)) || !UUID.test(String(archivoId))) {
    throw new Error('Identificadores inválidos para el respaldo.')
  }
  const extension = TIPOS[archivo?.type]
  if (!extension) throw new Error('El respaldo debe ser PDF, JPG o PNG.')
  return `${String(clienteId).toLowerCase()}/${String(archivoId).toLowerCase()}.${extension}`
}

// Contratos que pueden pasar a la cuenta nueva: misma moneda, con cuenta de pago y que no
// cobren ya en ella. Los demás se muestran pero no se pueden marcar.
export function contratosElegibles(contratos, cuentaNueva) {
  if (!cuentaNueva) return []
  return contratos.filter((c) => c.moneda === cuentaNueva.moneda
    && c.cuenta_bancaria_id
    && c.cuenta_bancaria_id !== cuentaNueva.id)
}

export function motivoNoElegible(contrato, cuentaNueva) {
  if (!contrato.cuenta_bancaria_id) return 'sin cuenta de pago (requiere conciliación)'
  if (!cuentaNueva) return ''
  if (contrato.moneda !== cuentaNueva.moneda) return `es en ${contrato.moneda}`
  if (contrato.cuenta_bancaria_id === cuentaNueva.id) return 'ya cobra en esa cuenta'
  return ''
}

export function validarCambio({ cuentaNueva, contratoIds, motivo, archivo }) {
  if (!cuentaNueva) return 'Elige la cuenta nueva.'
  if (!Array.isArray(contratoIds) || contratoIds.length === 0) return 'Marca al menos un contrato.'
  const texto = String(motivo ?? '').trim()
  if (texto.length < 5 || texto.length > 500) return 'Escribe el motivo del cambio (5 a 500 caracteres).'
  return validarRespaldo(archivo)
}

function fechaLima(valor) {
  if (!valor) return '—'
  const fecha = /^\d{4}-\d{2}-\d{2}$/.test(valor) ? new Date(`${valor}T12:00:00Z`) : new Date(valor)
  return fecha.toLocaleDateString('es-PE', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit'
  })
}

export function textoContrato(c) {
  const moneda = c.moneda === 'USD' ? 'Dólares' : 'Soles'
  const cuenta = c.cuenta_bancaria_id
    ? `cobra en ${c.banco} N° ${c.numero_cuenta}`
    : 'SIN cuenta de pago'
  const pendientes = Number(c.cuotas_pendientes) || 0
  const proximas = pendientes
    ? `${pendientes} cuota${pendientes === 1 ? '' : 's'} pendiente${pendientes === 1 ? '' : 's'} (próxima ${fechaLima(c.proxima_fecha)})`
    : 'sin cuotas pendientes'
  const pagadas = (Array.isArray(c.pagadas_por_cuenta) ? c.pagadas_por_cuenta : [])
    .map((p) => `${p.cuotas} en ${p.banco} N° ${p.numero_cuenta}`)
  const textoPagadas = pagadas.length ? ` · Pagadas: ${pagadas.join('; ')}` : ''
  return `${c.numero_contrato} · ${moneda} · ${cuenta} · ${proximas}${textoPagadas}`
}

export function textoCambio(h) {
  const aviso = h.notificado_en ? 'aviso enviado' : 'aviso PENDIENTE'
  const por = h.cambiado_por_nombre ? ` · por ${h.cambiado_por_nombre}` : ''
  return `${fechaLima(h.cambiado_en)} · ${h.numero_contrato} · ${h.banco_anterior} N° ${h.numero_anterior} → ${h.banco_nuevo} N° ${h.numero_nuevo} · «${h.motivo}»${por} · ${aviso}`
}

// Traduce los errores del servidor sin inventar: sus mensajes ya son para personas.
export function mensajeErrorCambio(error) {
  if (!error) return 'No se pudo cambiar la cuenta de pago.'
  if (error.code === '42501') return 'Solo administración puede cambiar la cuenta de pago.'
  if (error.code === '22023' && error.message) return error.message
  return 'No se pudo cambiar la cuenta de pago. Recarga la ventana y vuelve a intentar.'
}
```

## Portal: diff de clientes.js / clientes.html / cuentas-cliente-core.js
```diff
diff --git a/admin/clientes.html b/admin/clientes.html
index eafe46c..8e265bd 100644
--- a/admin/clientes.html
+++ b/admin/clientes.html
@@ -569,6 +569,39 @@
 
           <button type="button" class="btn btn-secondary" id="btnMostrarNuevaCuenta" style="margin-top: 8px;">+ Añadir cuenta</button>
 
+          <!-- Cuenta de pago de los contratos (F3): solo admin y superadmin -->
+          <div id="cb_pago_group" class="hidden" style="margin-top: 18px; padding-top: 14px; border-top: 1px solid var(--border);">
+            <p style="font-weight: 700; font-size: 14px; margin: 0 0 4px; color: var(--navy);">Cuenta de pago de los contratos</p>
+            <div id="cb_contratos_pago" aria-live="polite" style="font-size: 14px;">Cargando contratos…</div>
+            <button type="button" class="btn btn-secondary" id="btnMostrarCambioPago" style="margin-top: 8px;">Cambiar cuenta de pago</button>
+
+            <div id="cb_cambio_group" class="hidden" style="margin-top: 14px; padding: 12px; border: 1px solid var(--border); border-radius: var(--radius-sm);">
+              <p style="font-weight: 700; font-size: 14px; margin: 0 0 6px; color: var(--navy);">Cambiar la cuenta de pago (por pedido del cliente)</p>
+              <p id="cb_cambio_correo_cliente" class="text-muted" style="font-size: 13px; margin: 0 0 10px;"></p>
+              <div class="input-group">
+                <label class="input-label" for="cb_cambio_cuenta">Cuenta nueva</label>
+                <select class="input" id="cb_cambio_cuenta"></select>
+              </div>
+              <div id="cb_cambio_contratos" style="font-size: 14px; margin-bottom: 10px;"></div>
+              <div class="input-group">
+                <label class="input-label" for="cb_cambio_respaldo">Correo del cliente donde pide el cambio (PDF, JPG o PNG · máx. 10 MB)</label>
+                <input type="file" class="input" id="cb_cambio_respaldo" accept="application/pdf,image/jpeg,image/png">
+              </div>
+              <div class="input-group">
+                <label class="input-label" for="cb_cambio_motivo">Motivo</label>
+                <textarea class="input" id="cb_cambio_motivo" rows="2" maxlength="500" placeholder="Ej.: el cliente lo pidió por correo el 26/09"></textarea>
+              </div>
+              <div id="cb_cambio_error" class="alert alert-danger hidden" role="alert"></div>
+              <div style="display: flex; gap: 8px; flex-wrap: wrap;">
+                <button type="button" class="btn btn-secondary" id="btnCancelarCambioPago">Cancelar</button>
+                <button type="button" class="btn btn-primary" id="btnConfirmarCambioPago">Confirmar cambio</button>
+              </div>
+            </div>
+
+            <p style="font-weight: 700; font-size: 14px; margin: 14px 0 4px; color: var(--navy);">Cambios de cuenta de pago</p>
+            <div id="cb_cambios_pago" aria-live="polite" style="font-size: 14px;">Cargando historial…</div>
+          </div>
+
           <div id="cb_nueva_group" class="hidden" style="margin-top: 14px; padding: 12px; border: 1px solid var(--border); border-radius: var(--radius-sm);">
             <p style="font-weight: 700; font-size: 14px; margin: 0 0 10px; color: var(--navy);">Nueva cuenta</p>
             <p class="text-muted" style="font-size: 13px; margin: 0 0 10px;">
@@ -667,7 +700,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/clientes.js?v=53"></script>
+  <script type="module" src="/js/admin/clientes.js?v=54"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
diff --git a/js/admin/clientes.js b/js/admin/clientes.js
index ff06221..9426b73 100644
--- a/js/admin/clientes.js
+++ b/js/admin/clientes.js
@@ -21,7 +21,12 @@ import { guardarCorreoCliente, validarCorreccionCorreo } from './correo-cliente-
 import {
   cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente,
   cargarHistorialCuentas, pintarCuentasAnteriores
-} from './cuentas-cliente-core.js?v=4'
+} from './cuentas-cliente-core.js?v=5'
+// Cambio de la cuenta de pago de contratos por pedido del cliente (F3): núcleo puro.
+import {
+  BUCKET_RESPALDOS, puedeCambiarCuentaPago, validarRespaldo, rutaRespaldo, contratosElegibles,
+  motivoNoElegible, validarCambio, textoContrato, textoCambio, mensajeErrorCambio
+} from './cambio-cuenta-core.js?v=1'
 
 // CLIENTES_CACHE ahora guarda SOLO la página actual (max PAGE_SIZE filas).
 // El total real está en TOTAL_CLIENTES. Con paginación server-side el cache
@@ -37,6 +42,10 @@ let PUEDE_EDITAR_CORREO_CLIENTE = false
 let CUENTAS_EDITAR_CARGADAS = false
 let CUENTAS_EDITAR_TOKEN = 0
 let CUENTAS_MODAL_TOKEN = 0
+let PUEDE_CAMBIAR_CUENTA_PAGO = false // admin/superadmin; el servidor revalida con es_admin()
+// Estado del cambio de cuenta de pago de la ventana abierta. `solicitudId` se genera al abrir
+// el formulario y se reutiliza en reintentos: el servidor es idempotente por solicitud.
+let CAMBIO_PAGO = { clienteId: null, correo: '', cuentas: [], contratos: [], solicitudId: null, archivoId: null }
 /** Mover un cliente de un analista a otro es decision comercial: el asiento
  *  «Operaciones» no lo hace. El corte de verdad esta en el trigger
  *  `proteger_campos_inmutables`, que responde con un error claro; esto evita
@@ -617,6 +626,7 @@ function cargarCuentasModal(clienteId) {
   anteriores.textContent = 'Cargando cuentas anteriores…'
   void cargarCuentasCliente(supabase, clienteId).then((cuentas) => {
     if (token !== CUENTAS_MODAL_TOKEN) return
+    CAMBIO_PAGO.cuentas = cuentas
     pintarCuentasCliente(pen, cuentas, 'PEN')
     pintarCuentasCliente(usd, cuentas, 'USD')
   }).catch(() => {
@@ -632,6 +642,263 @@ function cargarCuentasModal(clienteId) {
     if (token !== CUENTAS_MODAL_TOKEN) return
     anteriores.textContent = 'No se pudo cargar el historial. Vuelve a abrir la ventana.'
   })
+  cargarPagoModal(clienteId, token)
+}
+
+/* ---------- Cuenta de pago de los contratos (F3, solo admin/superadmin) ---------- */
+
+function cargarPagoModal(clienteId, token) {
+  const grupo = document.getElementById('cb_pago_group')
+  grupo.classList.toggle('hidden', !PUEDE_CAMBIAR_CUENTA_PAGO)
+  if (!PUEDE_CAMBIAR_CUENTA_PAGO) return
+  const lista = document.getElementById('cb_contratos_pago')
+  const cambios = document.getElementById('cb_cambios_pago')
+  lista.textContent = 'Cargando contratos…'
+  cambios.textContent = 'Cargando historial…'
+  void supabase.schema('crm').rpc('contratos_cuenta_pago_cliente_fn', { p_cliente_id: clienteId })
+    .then(({ data, error }) => {
+      if (token !== CUENTAS_MODAL_TOKEN) return
+      if (error || !Array.isArray(data)) {
+        lista.textContent = 'No se pudieron cargar los contratos. Vuelve a abrir la ventana.'
+        CAMBIO_PAGO.contratos = []
+        return
+      }
+      CAMBIO_PAGO.contratos = data
+      pintarLista(lista, data.map(textoContrato), 'Sin contratos abiertos.')
+    })
+  void supabase.schema('crm').rpc('cambios_cuenta_pago_cliente_fn', { p_cliente_id: clienteId })
+    .then(({ data, error }) => {
+      if (token !== CUENTAS_MODAL_TOKEN) return
+      if (error || !Array.isArray(data)) {
+        cambios.textContent = 'No se pudo cargar el historial de cambios.'
+        return
+      }
+      pintarCambiosPago(cambios, data)
+    })
+}
+
+function pintarLista(elemento, textos, vacio) {
+  elemento.replaceChildren()
+  if (textos.length === 0) {
+    elemento.textContent = vacio
+    return
+  }
+  const ul = document.createElement('ul')
+  ul.style.margin = '6px 0 12px'
+  ul.style.paddingLeft = '20px'
+  for (const texto of textos) {
+    const li = document.createElement('li')
+    li.textContent = texto
+    ul.appendChild(li)
+  }
+  elemento.appendChild(ul)
+}
+
+function pintarCambiosPago(elemento, cambios) {
+  elemento.replaceChildren()
+  if (cambios.length === 0) {
+    elemento.textContent = 'Sin cambios de cuenta de pago.'
+    return
+  }
+  const ul = document.createElement('ul')
+  ul.style.margin = '6px 0 12px'
+  ul.style.paddingLeft = '20px'
+  const avisados = new Set()
+  for (const h of cambios) {
+    const li = document.createElement('li')
+    li.appendChild(document.createTextNode(textoCambio(h) + ' '))
+    const ver = document.createElement('button')
+    ver.type = 'button'
+    ver.className = 'btn-icon'
+    ver.textContent = 'Ver correo'
+    ver.addEventListener('click', () => verRespaldo(h.respaldo_ruta))
+    li.appendChild(ver)
+    // Un aviso por solicitud: el botón aparece una vez aunque la solicitud tenga varios contratos.
+    if (!h.notificado_en && !avisados.has(h.solicitud_id)) {
+      avisados.add(h.solicitud_id)
+      const reenviar = document.createElement('button')
+      reenviar.type = 'button'
+      reenviar.className = 'btn-icon'
+      reenviar.textContent = 'Enviar aviso'
+      reenviar.addEventListener('click', () => void avisarCliente(h.solicitud_id, reenviar))
+      li.appendChild(document.createTextNode(' '))
+      li.appendChild(reenviar)
+    }
+    ul.appendChild(li)
+  }
+  elemento.appendChild(ul)
+}
+
+async function verRespaldo(ruta) {
+  const { data, error } = await supabase.storage.from(BUCKET_RESPALDOS).createSignedUrl(ruta, 300)
+  if (error || !data?.signedUrl) {
+    mostrarError('No se pudo abrir el correo del cliente.')
+    return
+  }
+  window.open(data.signedUrl, '_blank', 'noopener')
+}
+
+function abrirCambioPago() {
+  const errEl = document.getElementById('cb_cambio_error')
+  errEl.classList.add('hidden')
+  CAMBIO_PAGO.solicitudId = crypto.randomUUID()
+  CAMBIO_PAGO.archivoId = crypto.randomUUID()
+  document.getElementById('cb_cambio_correo_cliente').textContent = CAMBIO_PAGO.correo
+    ? `Correo registrado del cliente: ${CAMBIO_PAGO.correo}. Verifica que la solicitud venga de esa dirección.`
+    : 'El cliente no tiene correo registrado: verifica bien el origen de la solicitud.'
+  const select = document.getElementById('cb_cambio_cuenta')
+  select.replaceChildren()
+  const vacia = document.createElement('option')
+  vacia.value = ''
+  vacia.textContent = '— Elegir la cuenta nueva —'
+  select.appendChild(vacia)
+  for (const c of CAMBIO_PAGO.cuentas) {
+    const opt = document.createElement('option')
+    opt.value = c.id
+    opt.textContent = `${c.moneda === 'USD' ? 'Dólares' : 'Soles'} · ${c.banco} · N° ${c.numero}`
+    select.appendChild(opt)
+  }
+  document.getElementById('cb_cambio_respaldo').value = ''
+  document.getElementById('cb_cambio_motivo').value = ''
+  pintarContratosCambio()
+  document.getElementById('cb_cambio_group').classList.remove('hidden')
+  document.getElementById('btnMostrarCambioPago').classList.add('hidden')
+}
+
+function cerrarCambioPago() {
+  document.getElementById('cb_cambio_group').classList.add('hidden')
+  document.getElementById('btnMostrarCambioPago').classList.remove('hidden')
+}
+
+function cuentaNuevaElegida() {
+  const id = document.getElementById('cb_cambio_cuenta').value
+  return CAMBIO_PAGO.cuentas.find((c) => c.id === id) || null
+}
+
+// Por defecto quedan marcados todos los contratos elegibles; los demás se ven con su motivo.
+function pintarContratosCambio() {
+  const cont = document.getElementById('cb_cambio_contratos')
+  cont.replaceChildren()
+  const cuenta = cuentaNuevaElegida()
+  if (!cuenta) {
+    cont.textContent = 'Elige la cuenta nueva para ver qué contratos pueden pasar a ella.'
+    return
+  }
+  const elegibles = new Set(contratosElegibles(CAMBIO_PAGO.contratos, cuenta).map((c) => c.contrato_id))
+  if (elegibles.size === 0) {
+    cont.textContent = 'Ningún contrato abierto puede pasar a esta cuenta.'
+  }
+  for (const c of CAMBIO_PAGO.contratos) {
+    const label = document.createElement('label')
+    label.style.display = 'flex'
+    label.style.gap = '8px'
+    label.style.alignItems = 'center'
+    label.style.margin = '4px 0'
+    const chk = document.createElement('input')
+    chk.type = 'checkbox'
+    chk.value = c.contrato_id
+    chk.dataset.contratoCambio = '1'
+    chk.style.width = 'auto'
+    chk.style.margin = '0'
+    const ok = elegibles.has(c.contrato_id)
+    chk.checked = ok
+    chk.disabled = !ok
+    label.appendChild(chk)
+    const motivo = ok ? '' : ` — no aplica: ${motivoNoElegible(c, cuenta)}`
+    label.appendChild(document.createTextNode(`${textoContrato(c)}${motivo}`))
+    cont.appendChild(label)
+  }
+}
+
+async function confirmarCambioPago() {
+  const errEl = document.getElementById('cb_cambio_error')
+  errEl.classList.add('hidden')
+  const btn = document.getElementById('btnConfirmarCambioPago')
+  if (btn.disabled) return
+  const clienteId = CAMBIO_PAGO.clienteId
+  const cuenta = cuentaNuevaElegida()
+  const contratoIds = [...document.querySelectorAll('#cb_cambio_contratos input[data-contrato-cambio]:checked')]
+    .map((chk) => chk.value)
+  const motivo = document.getElementById('cb_cambio_motivo').value.trim()
+  const archivo = document.getElementById('cb_cambio_respaldo').files?.[0] || null
+  const falta = validarCambio({ cuentaNueva: cuenta, contratoIds, motivo, archivo })
+  if (falta) {
+    errEl.textContent = falta
+    errEl.classList.remove('hidden')
+    return
+  }
+  const sigueEnEsteCliente = () =>
+    !document.getElementById('modalCuentas').classList.contains('hidden')
+    && document.getElementById('cb_clienteId').value === clienteId
+  btn.disabled = true
+  btn.textContent = 'Guardando…'
+  try {
+    // 1) Respaldo al bucket privado. Si ya se subió en un intento anterior, se reutiliza.
+    const ruta = rutaRespaldo(clienteId, CAMBIO_PAGO.archivoId, archivo)
+    const subida = await supabase.storage.from(BUCKET_RESPALDOS)
+      .upload(ruta, archivo, { contentType: archivo.type, upsert: false })
+    if (subida.error && !/exist/i.test(subida.error.message || '')) {
+      throw new Error('No se pudo subir el correo del cliente. Vuelve a intentar.')
+    }
+    // 2) El cambio (todo o nada, idempotente por solicitud).
+    const { data, error } = await supabase.schema('crm').rpc('cambiar_cuenta_pago_contratos', {
+      p_solicitud_id: CAMBIO_PAGO.solicitudId,
+      p_cliente_id: clienteId,
+      p_cuenta_nueva_id: cuenta.id,
+      p_contrato_ids: contratoIds,
+      p_motivo: motivo,
+      p_respaldo_ruta: ruta,
+    })
+    if (error) throw new Error(mensajeErrorCambio(error))
+    // 3) Aviso al cliente (portal + correo). El cambio ya está hecho aunque el aviso falle.
+    const aviso = await avisarCliente(CAMBIO_PAGO.solicitudId, null)
+    const n = Number(data?.contratos) || contratoIds.length
+    mostrarExito(`Cuenta de pago cambiada en ${n} contrato${n === 1 ? '' : 's'}. ${aviso}`)
+    if (!sigueEnEsteCliente()) return
+    cerrarCambioPago()
+    cargarPagoModal(clienteId, CUENTAS_MODAL_TOKEN)
+  } catch (error) {
+    const mensaje = error?.message || 'No se pudo cambiar la cuenta de pago.'
+    if (!sigueEnEsteCliente()) {
+      mostrarError(mensaje)
+      return
+    }
+    errEl.textContent = mensaje
+    errEl.classList.remove('hidden')
+  } finally {
+    btn.disabled = false
+    btn.textContent = 'Confirmar cambio'
+  }
+}
+
+// Devuelve un texto para el aviso de éxito; con botón (reenvío) refresca el historial.
+async function avisarCliente(solicitudId, boton) {
+  if (boton) {
+    boton.disabled = true
+    boton.textContent = 'Enviando…'
+  }
+  let texto
+  try {
+    const { data, error } = await supabase.functions.invoke('notificar-cambio-cuenta', {
+      body: { solicitud_id: solicitudId },
+    })
+    if (error || !data?.success) {
+      texto = 'No se pudo avisar al cliente: usa «Enviar aviso» en el historial.'
+    } else if (data.ya_notificada) {
+      texto = 'El cliente ya había sido avisado.'
+    } else {
+      texto = data.correo
+        ? 'Se avisó al cliente en su portal y por correo.'
+        : 'Se avisó al cliente en su portal; el correo no se pudo enviar.'
+    }
+  } catch {
+    texto = 'No se pudo avisar al cliente: usa «Enviar aviso» en el historial.'
+  }
+  if (boton) {
+    mostrarExito(texto)
+    if (CAMBIO_PAGO.clienteId) cargarPagoModal(CAMBIO_PAGO.clienteId, CUENTAS_MODAL_TOKEN)
+  }
+  return texto
 }
 
 function limpiarFormNuevaCuenta() {
@@ -651,6 +918,8 @@ function mostrarFormNuevaCuenta(visible) {
 }
 
 function abrirModalCuentas(cliente) {
+  CAMBIO_PAGO = { clienteId: cliente.id, correo: cliente.correo || '', cuentas: [], contratos: [], solicitudId: null, archivoId: null }
+  cerrarCambioPago()
   document.getElementById('cb_clienteId').value = cliente.id
   document.getElementById('cb_clienteNombre').textContent = cliente.nombre_completo
   document.getElementById('modalCuentasError').classList.add('hidden')
@@ -1829,6 +2098,7 @@ async function recargar() {
   PUEDE_ELIMINAR_CLIENTES = perfil?.rol === 'superadmin' || perfil?.rol === 'admin'
   PUEDE_EDITAR_DOCUMENTO_CLIENTE = PUEDE_ELIMINAR_CLIENTES
   PUEDE_EDITAR_CORREO_CLIENTE = PUEDE_ELIMINAR_CLIENTES
+  PUEDE_CAMBIAR_CUENTA_PAGO = puedeCambiarCuentaPago(perfil?.rol)
   PUEDE_ASIGNAR_ANALISTA = perfil?.rol !== 'operaciones'
   // Cargar clientes a granel desde un Excel es una decision de Gloria, no
   // trabajo de cartera: el asiento «Operaciones» da de alta uno a uno.
@@ -1919,6 +2189,18 @@ async function recargar() {
   document.getElementById('btnMostrarNuevaCuenta')?.addEventListener('click', () => mostrarFormNuevaCuenta(true))
   document.getElementById('formCuentas')?.addEventListener('submit', guardarCuentaNueva)
   document.getElementById('cb_titular_distinto')?.addEventListener('change', () => toggleBeneficiario('cb'))
+  document.getElementById('btnMostrarCambioPago')?.addEventListener('click', abrirCambioPago)
+  document.getElementById('btnCancelarCambioPago')?.addEventListener('click', cerrarCambioPago)
+  document.getElementById('btnConfirmarCambioPago')?.addEventListener('click', () => void confirmarCambioPago())
+  document.getElementById('cb_cambio_cuenta')?.addEventListener('change', pintarContratosCambio)
+  // Otro archivo = otra ruta: el respaldo subido nunca se sustituye.
+  document.getElementById('cb_cambio_respaldo')?.addEventListener('change', (e) => {
+    CAMBIO_PAGO.archivoId = crypto.randomUUID()
+    const falta = validarRespaldo(e.target.files?.[0] || null)
+    const errEl = document.getElementById('cb_cambio_error')
+    errEl.textContent = falta || ''
+    errEl.classList.toggle('hidden', !falta)
+  })
 
   // Mini-modal asignar asesor (acción rápida desde la fila)
   document.getElementById('modalCloseAsignar')?.addEventListener('click', cerrarModalAsignar)
diff --git a/js/admin/cuentas-cliente-core.js b/js/admin/cuentas-cliente-core.js
index d2aa181..08a4b9c 100644
--- a/js/admin/cuentas-cliente-core.js
+++ b/js/admin/cuentas-cliente-core.js
@@ -25,6 +25,7 @@ function resumirCuenta(cuenta) {
     perfil: 'Perfil migrado', contrato: 'CRM / contrato', portal: 'Ficha de cliente'
   }[cuenta.origen] || 'Origen no disponible'
   const resumen = {
+    id: cuenta.cuenta_id,
     moneda: cuenta.moneda,
     banco: cuenta.banco || 'Banco no disponible',
     tipo: cuenta.tipo_cuenta || 'Tipo no disponible',
```
Tests del portal: 148/148 (7 nuevos del núcleo de cambio).
