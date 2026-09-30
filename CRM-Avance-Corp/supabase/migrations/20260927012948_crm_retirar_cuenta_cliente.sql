-- Cuentas de Gloria · F4: retirar una cuenta bancaria del cliente (nunca se borra).
--
-- Qué hace:
--   1. crm.cuentas_bancarias_retiros: registro inmutable de cada retiro (cuenta, cliente, moneda,
--      motivo, respaldo opcional, quién y cuándo). Sin claves foráneas, como los registros de F3:
--      es una constancia que sobrevive a cuentas, clientes y personas, y no interfiere con las
--      eliminaciones auditadas (que fallan cerradas ante dependencias nuevas). No se modifica ni
--      se borra.
--   2. crm.retirar_cuenta_cliente (puerta INVOKER → núcleo DEFINER): solo admin/superadmin activo
--      con la membresía CRM NO revocada (P04, private.admin_banca_vigente de F3); solo una cuenta
--      VIGENTE del cliente indicado; si esa cuenta física (mismo cliente, moneda y CCI, en
--      cualquiera de sus versiones) todavía es la cuenta de pago de algún contrato abierto
--      ('activo'/'vencido') se rechaza y dice cuáles (primero se cambia su cuenta de pago, F3);
--      motivo obligatorio (5 a 500); respaldo opcional (el correo del cliente, en el bucket
--      privado de F3, subido por el mismo admin); idempotente por solicitud; todo o nada. La
--      cuenta pasa a activa = false con desactivada_por y desactivada_en: el candado de versiones
--      (private.trg_cuentas_bancarias_version_inmutable) admite ese paso y prohíbe reactivarla.
--   3. crm.retiros_cuentas_cliente_fn: los motivos de retiro del cliente para «Cuentas
--      anteriores», con la misma compuerta que el historial (private.puede_gestionar_cuentas_cliente,
--      que ya incluye P04). La ruta del respaldo solo la ve el admin vigente (solo él puede abrirlo).
--
-- Decisiones de Miguel (26/09/2026, al arrancar F4): si la cuenta cobra contratos abiertos se
-- bloquea y se cambia primero con F3; motivo obligatorio y correo opcional; sin aviso al cliente;
-- solo admin y superadmin. No toca objetos de public ni de storage (lee public.contratos y
-- storage.objects; el bucket y sus políticas son los de F3).
--
-- Efectos en el resto del sistema (sin tocarlo): todas las lecturas de cuentas vigentes salen de
-- crm.cuentas_bancarias con activa is true (private.cuentas_cliente_vigentes: selector del CRM,
-- ventana «Cuentas», vista del cliente; «Cambiar cuenta de pago» exige cuenta nueva vigente), así
-- que la cuenta retirada deja de ofrecerse en todas. Las cuotas pagadas (sellos de F3) y el
-- historial de cambios la siguen nombrando: leen la cuenta por id, vigente o no.
--
-- Bloqueos: el núcleo bloquea la cuenta FOR UPDATE antes de mirar sus enlaces. El alta de un
-- contrato con cuenta existente la lee «activa = true ... for share» y el cambio de F3 bloquea la
-- cuenta nueva FOR SHARE: los dos esperan a este retiro y después la ven retirada; y si llegaron
-- antes, su enlace ya está confirmado cuando el núcleo lo busca. Un cambio de F3 que saca un
-- contrato de esta cuenta y aún no confirma deja el enlace viejo a la vista: el retiro falla
-- cerrado (se reintenta).
--
-- Reversión: ../scripts/cuentas-gloria/reversa-retirar-cuenta-cliente.sql (se niega si ya hay
-- retiros registrados: una cuenta retirada no se reactiva y su constancia se perdería).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.admin_banca_vigente(uuid)') is null
     or to_regprocedure('private.respaldo_cambio_cuenta_permitido(text)') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regprocedure('private.log_audit_crm()') is null
     or to_regprocedure('auth.uid()') is null
     or to_regclass('crm.cuentas_bancarias') is null or to_regclass('crm.contrato_cuentas_pago') is null
     or to_regclass('public.contratos') is null or to_regclass('public.perfiles') is null
     or to_regclass('storage.objects') is null then
    raise exception 'RETIRO_CUENTA: faltan dependencias (¿está aplicada la F3 20260926204051?)';
  end if;
  if not exists (select 1 from storage.buckets b where b.id = 'respaldos-cambio-cuenta' and b.public is false) then
    raise exception 'RETIRO_CUENTA: falta el bucket privado respaldos-cambio-cuenta de la F3';
  end if;
  -- El retiro se apoya en el candado de versiones tal como está: activa true → false con fecha,
  -- y nunca al revés. Si alguien lo cambió, no se sigue a ciegas.
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = to_regprocedure('private.trg_cuentas_bancarias_version_inmutable()'))
     is distinct from '7e1a56ca0153f5b810e2b2783069ac00'
     or not exists (select 1 from pg_catalog.pg_trigger
                    where tgrelid = 'crm.cuentas_bancarias'::regclass
                      and tgname = 'trg_cuentas_bancarias_version_inmutable' and tgenabled = 'O') then
    raise exception 'RETIRO_CUENTA: el candado de versiones de cuentas no es el esperado; no se toca';
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint
                 where conrelid = 'crm.cuentas_bancarias'::regclass
                   and conname = 'cuentas_bancarias_desactivacion_coherente') then
    raise exception 'RETIRO_CUENTA: falta la regla de coherencia de desactivación de cuentas';
  end if;
  if to_regclass('crm.cuentas_bancarias_retiros') is not null then
    raise exception 'RETIRO_CUENTA: los objetos ya existen; no se sobrescriben';
  end if;
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false)
     or not pg_catalog.has_table_privilege(current_user, 'storage.objects', 'SELECT') then
    raise exception 'RETIRO_CUENTA: el dueño de las funciones no puede leer storage.objects sin RLS';
  end if;
end;
$precondicion$;

-- ── 1. Registro inmutable del retiro ──────────────────────────────────────────────────────
create table crm.cuentas_bancarias_retiros (
  id            uuid primary key default gen_random_uuid(),
  solicitud_id  uuid not null constraint cuentas_bancarias_retiros_solicitud_uq unique,
  cuenta_id     uuid not null constraint cuentas_bancarias_retiros_cuenta_uq unique,
  cliente_id    uuid not null,
  moneda        text not null
                constraint cuentas_bancarias_retiros_moneda_valida check (moneda in ('PEN', 'USD')),
  motivo        text not null
                constraint cuentas_bancarias_retiros_motivo_valido
                -- Sin espacios en los bordes (también tabuladores, saltos y espacios Unicode) y con
                -- al menos 5 caracteres visibles: un motivo de solo espacios no es un motivo.
                check (motivo = regexp_replace(motivo, '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g')
                       and length(regexp_replace(motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) >= 5
                       and length(motivo) <= 500),
  respaldo_ruta text
                constraint cuentas_bancarias_retiros_respaldo_valido
                check (respaldo_ruta is null
                       or respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$'),
  retirado_por  uuid not null,
  retirado_en   timestamptz not null default now()
);
alter table crm.cuentas_bancarias_retiros enable row level security;
revoke all on crm.cuentas_bancarias_retiros from public, anon, authenticated, service_role;
create index cuentas_bancarias_retiros_cliente_idx on crm.cuentas_bancarias_retiros (cliente_id, retirado_en desc);

create function private.trg_retiro_cuenta_inmutable()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using errcode = '22023',
    message = 'El retiro de una cuenta es un registro inmutable: no se modifica ni se borra';
end;
$function$;
revoke all on function private.trg_retiro_cuenta_inmutable() from public, anon, authenticated, service_role;
create trigger trg_cuentas_bancarias_retiros_00_inmutable
  before update or delete on crm.cuentas_bancarias_retiros
  for each row execute function private.trg_retiro_cuenta_inmutable();
create trigger trg_cuentas_bancarias_retiros_00_sin_vaciar
  before truncate on crm.cuentas_bancarias_retiros
  for each statement execute function private.trg_retiro_cuenta_inmutable();
create trigger trg_audit_cuentas_bancarias_retiros
  after insert or delete or update on crm.cuentas_bancarias_retiros
  for each row execute function private.log_audit_crm();

-- ── 2. Operación: retirar una cuenta (núcleo DEFINER + puerta INVOKER) ──────────────────────
create function private.retirar_cuenta_cliente_autorizado(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_id uuid, p_motivo text, p_respaldo_ruta text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_motivo text := pg_catalog.regexp_replace(coalesce(p_motivo, ''), '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g');
  v_ruta text := nullif(pg_catalog.btrim(coalesce(p_respaldo_ruta, '')), '');
  v_previo crm.cuentas_bancarias_retiros%rowtype;
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_obj storage.objects%rowtype;
  v_abiertos text[];
  v_quien text;
begin
  if not coalesce(private.admin_banca_vigente(v_actor), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede retirar cuentas bancarias';
  end if;
  if p_solicitud_id is null or p_cliente_id is null or p_cuenta_id is null then
    raise exception using errcode = '22023', message = 'Faltan datos del retiro';
  end if;
  if pg_catalog.length(pg_catalog.regexp_replace(v_motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) < 5
     or pg_catalog.length(v_motivo) > 500 then
    raise exception using errcode = '22023', message = 'Escribe el motivo del retiro (5 a 500 caracteres)';
  end if;

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con otros
  -- datos se rechaza. Va antes de mirar la cuenta, que tras el primer intento ya está retirada.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('retiro-cuenta:' || p_solicitud_id::text, 0));
  select * into v_previo from crm.cuentas_bancarias_retiros where solicitud_id = p_solicitud_id;
  if found then
    if v_previo.cuenta_id = p_cuenta_id and v_previo.cliente_id = p_cliente_id
       and v_previo.motivo = v_motivo and v_previo.respaldo_ruta is not distinct from v_ruta then
      return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true,
        'cuenta_id', p_cuenta_id);
    end if;
    raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  end if;

  -- La cuenta: del cliente y vigente. Bloqueo exclusivo: un alta de contrato o un cambio de F3
  -- que la elijan esperan a este retiro y después la ven retirada.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_id for update;
  if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
    raise exception using errcode = '22023', message = 'La cuenta no es de este cliente';
  end if;
  if not v_cuenta.activa then
    select pr.nombre_completo into v_quien
    from public.perfiles pr
    where pr.id = v_cuenta.desactivada_por and pr.rol <> 'cliente';
    if exists (select 1 from crm.cuentas_bancarias_retiros r where r.cuenta_id = p_cuenta_id) then
      raise exception using errcode = '22023',
        message = pg_catalog.format('La cuenta ya fue retirada el %s%s',
          pg_catalog.to_char(v_cuenta.desactivada_en at time zone 'America/Lima', 'DD/MM/YYYY'),
          case when v_quien is not null then ' por ' || v_quien else '' end);
    end if;
    -- Desactivada por una corrección de datos (nueva versión) u otra vía: no fue un «retiro».
    raise exception using errcode = '22023',
      message = pg_catalog.format('La cuenta ya no está vigente desde el %s: se reemplazó por una versión corregida',
        pg_catalog.to_char(v_cuenta.desactivada_en at time zone 'America/Lima', 'DD/MM/YYYY'));
  end if;

  -- Contratos abiertos que todavía cobran en esta cuenta FÍSICA (mismo cliente, moneda y CCI): una
  -- cuenta corregida deja versiones viejas, inactivas pero todavía enlazadas a sus contratos, y el
  -- registro de pagos las acepta como instrucción contractual. Primero se cambia su cuenta de pago
  -- (F3). Ninguna vía crea enlaces hacia versiones inactivas (alta y F3 exigen activa bajo bloqueo):
  -- los enlaces viejos solo pueden irse, y eso falla cerrado.
  select pg_catalog.array_agg(ct.numero_contrato order by ct.numero_contrato) into v_abiertos
  from crm.contrato_cuentas_pago l
  join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  join public.contratos ct on ct.id = l.contrato_id
  where cb.cliente_id = v_cuenta.cliente_id
    and cb.moneda = v_cuenta.moneda
    and cb.cci = v_cuenta.cci
    and ct.estado in ('activo', 'vencido');
  if coalesce(pg_catalog.cardinality(v_abiertos), 0) > 0 then
    raise exception using errcode = '22023', detail = 'contratos_abiertos',
      message = pg_catalog.format('La cuenta todavía cobra %s %s. Primero cambia su cuenta de pago',
        case when pg_catalog.cardinality(v_abiertos) = 1 then 'el contrato' else 'los contratos' end,
        pg_catalog.array_to_string(v_abiertos, ', '));
  end if;

  -- Respaldo opcional: si viene, el correo del cliente en su carpeta, subido por este mismo admin.
  -- Puede ser el mismo correo de un cambio de F3 («cambien mi cuenta y retiren la vieja»).
  if v_ruta is not null then
    if pg_catalog.split_part(v_ruta, '/', 1) is distinct from p_cliente_id::text
       or not coalesce(v_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false) then
      raise exception using errcode = '22023', message = 'El respaldo no es un archivo válido de este cliente';
    end if;
    select * into v_obj from storage.objects
    where bucket_id = 'respaldos-cambio-cuenta' and name = v_ruta;
    if not found
       or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
       or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
      raise exception using errcode = '22023', message = 'El respaldo no es un archivo válido de este cliente';
    end if;
    if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then
      raise exception using errcode = '22023', message = 'El respaldo debe subirlo quien retira la cuenta';
    end if;
  end if;

  update crm.cuentas_bancarias
     set activa = false,
         desactivada_por = v_actor,
         desactivada_en = pg_catalog.now()
   where id = p_cuenta_id;
  insert into crm.cuentas_bancarias_retiros
    (solicitud_id, cuenta_id, cliente_id, moneda, motivo, respaldo_ruta, retirado_por, retirado_en)
  values
    (p_solicitud_id, p_cuenta_id, p_cliente_id, v_cuenta.moneda, v_motivo, v_ruta, v_actor, pg_catalog.now());

  return pg_catalog.jsonb_build_object(
    'solicitud_id', p_solicitud_id, 'ya_aplicada', false, 'cuenta_id', p_cuenta_id,
    'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda,
    'ultimos', pg_catalog.right(v_cuenta.numero_cuenta, 4));
end;
$function$;
revoke all on function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)
  from public, anon, authenticated, service_role;
grant execute on function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text) to authenticated;

create function crm.retirar_cuenta_cliente(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_id uuid, p_motivo text, p_respaldo_ruta text default null)
returns jsonb
language sql
volatile security invoker
set search_path to ''
as $function$
  select private.retirar_cuenta_cliente_autorizado(
    p_solicitud_id, p_cliente_id, p_cuenta_id, p_motivo, p_respaldo_ruta);
$function$;
revoke all on function crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text) to authenticated;

-- ── 3. Lectura: motivos de retiro para «Cuentas anteriores» ─────────────────────────────────
create function private.retiros_cuentas_cliente_autorizado(p_cliente_id uuid)
returns table (
  cuenta_id uuid, motivo text, respaldo_ruta text, retirado_por_nombre text, retirado_en timestamptz
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_admin boolean;
begin
  if not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501', message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  v_admin := coalesce(private.admin_banca_vigente((select auth.uid())), false);
  return query
  select r.cuenta_id, r.motivo,
         case when v_admin then r.respaldo_ruta end,
         pr.nombre_completo, r.retirado_en
  from crm.cuentas_bancarias_retiros r
  left join public.perfiles pr on pr.id = r.retirado_por and pr.rol <> 'cliente'
  where r.cliente_id = p_cliente_id
  order by r.retirado_en desc, r.cuenta_id;
end;
$function$;
revoke all on function private.retiros_cuentas_cliente_autorizado(uuid) from public, anon, authenticated, service_role;
grant execute on function private.retiros_cuentas_cliente_autorizado(uuid) to authenticated;

create function crm.retiros_cuentas_cliente_fn(p_cliente_id uuid)
returns table (
  cuenta_id uuid, motivo text, respaldo_ruta text, retirado_por_nombre text, retirado_en timestamptz
)
language sql
stable security invoker
set search_path to ''
as $function$
  select * from private.retiros_cuentas_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.retiros_cuentas_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.retiros_cuentas_cliente_fn(uuid) to authenticated;

-- ── 4. Comentarios ─────────────────────────────────────────────────────────────────────────
comment on table crm.cuentas_bancarias_retiros is
  'Constancia inmutable de cada retiro de una cuenta bancaria del cliente (F4, 26/09/2026): la cuenta pasa a activa = false y aquí queda el motivo, el respaldo opcional, quién y cuándo. Sin claves foráneas a propósito: sobrevive a cuentas, clientes y personas. No se modifica ni se borra. DATOS SENSIBLES: motivo y respaldo (correo del cliente).';
comment on column crm.cuentas_bancarias_retiros.id is 'Identificador del retiro.';
comment on column crm.cuentas_bancarias_retiros.solicitud_id is 'Id de la operación (idempotencia ante doble clic).';
comment on column crm.cuentas_bancarias_retiros.cuenta_id is 'Cuenta de crm.cuentas_bancarias retirada (sin FK). Una versión se retira una sola vez.';
comment on column crm.cuentas_bancarias_retiros.cliente_id is 'Cliente dueño de la cuenta (sin FK).';
comment on column crm.cuentas_bancarias_retiros.moneda is 'Moneda de la cuenta retirada.';
comment on column crm.cuentas_bancarias_retiros.motivo is 'Motivo escrito por administración: hasta 500 caracteres, al menos 5 visibles, sin espacios de ningún tipo en los bordes.';
comment on column crm.cuentas_bancarias_retiros.respaldo_ruta is 'Opcional: ruta en el bucket privado respaldos-cambio-cuenta del correo del cliente. DATO SENSIBLE.';
comment on column crm.cuentas_bancarias_retiros.retirado_por is 'Administrador que retiró la cuenta (id de perfil, sin FK).';
comment on column crm.cuentas_bancarias_retiros.retirado_en is 'Momento del retiro (hora de la transacción; igual a desactivada_en de la cuenta).';
comment on function private.trg_retiro_cuenta_inmutable() is 'Candado de crm.cuentas_bancarias_retiros: ni UPDATE ni DELETE (por fila) ni TRUNCATE (por sentencia). SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text) is 'Núcleo del retiro de una cuenta bancaria: solo admin vigente (P04); solo cuentas vigentes del cliente; rechaza (22023, detail contratos_abiertos) si la cuenta física (cliente, moneda, CCI; cualquier versión) cobra contratos activo/vencido; motivo obligatorio y respaldo opcional (propio del admin); idempotente por solicitud; todo o nada. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias, el enlace, el registro ni storage.objects.';
comment on function crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text) is 'Puerta (INVOKER) del retiro de una cuenta bancaria del cliente. La usa la ventana «Cuentas» del portal (solo admin).';
comment on function private.retiros_cuentas_cliente_autorizado(uuid) is 'Motivos de retiro de las cuentas del cliente para «Cuentas anteriores». Compuerta private.puede_gestionar_cuentas_cliente (la del historial, con P04); la ruta del respaldo solo para admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre el registro. DATOS SENSIBLES.';
comment on function crm.retiros_cuentas_cliente_fn(uuid) is 'Puerta (INVOKER) de los motivos de retiro de cuentas del cliente.';

-- ── 5. Postflight ──────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f'
               and (c.conrelid = 'crm.cuentas_bancarias_retiros'::regclass
                    or c.confrelid = 'crm.cuentas_bancarias_retiros'::regclass)) then
    raise exception 'RETIRO_CUENTA: el registro no debe tener claves foráneas';
  end if;
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
             where pg_catalog.has_table_privilege(r.rol, 'crm.cuentas_bancarias_retiros',
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'))
     or not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'crm.cuentas_bancarias_retiros'::regclass) then
    raise exception 'RETIRO_CUENTA: el registro quedó accesible desde la API o sin RLS';
  end if;
  for v_f in
    select * from (values
      ('private.trg_retiro_cuenta_inmutable()', null),
      ('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)', 'authenticated'),
      ('crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)', 'authenticated'),
      ('private.retiros_cuentas_cliente_autorizado(uuid)', 'authenticated'),
      ('crm.retiros_cuentas_cliente_fn(uuid)', 'authenticated')
    ) as f(firma, rol)
  loop
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'RETIRO_CUENTA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'RETIRO_CUENTA: search_path inesperado en %', v_f.firma;
    end if;
  end loop;
  if (select count(*) from pg_catalog.pg_trigger
      where tgrelid = 'crm.cuentas_bancarias_retiros'::regclass and not tgisinternal) <> 3 then
    raise exception 'RETIRO_CUENTA: faltan los triggers del registro';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
