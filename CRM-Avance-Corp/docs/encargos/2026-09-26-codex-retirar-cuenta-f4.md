ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: Cuentas de Gloria · F4 — retirar una cuenta bancaria del cliente (LEVEL 3: datos bancarios y permisos)

Tu trabajo es REFUTAR: busca fallos reales en el SQL (autorización, P04, carreras con el alta de
contratos, con el cambio de cuenta de pago de F3 y con el registro de pagos, idempotencia, respaldo,
fugas entre roles o clientes, candados) y en la pantalla (estados, reintentos, subidas, textos
engañosos, XSS). Sin hallazgo sin evidencia. Es la única ronda.

## Decisiones de Miguel (dueño, NO son hallazgos)
- Solo admin/superadmin con la membresía CRM vigente (P04).
- Si la cuenta todavía es la cuenta de pago de contratos abiertos ('activo'/'vencido'), NO se retira:
  se rechaza listando esos contratos y la pantalla ofrece ir a «Cambiar cuenta de pago» (F3). No hay
  flujo combinado.
- Motivo obligatorio (5-500); el correo del cliente es OPCIONAL (a veces el banco cerró la cuenta).
- Sin aviso al cliente (no cambia ningún pago).
- Nunca se borra nada: la cuenta pasa a activa=false y queda en «Cuentas anteriores» con fecha,
  quién y motivo. «Retirar» no prohíbe volver a registrar a propósito los mismos datos (el
  versionado del proyecto crea entonces una cuenta vigente nueva).
- Todo el que ya ve las cuentas del cliente (admin, operaciones, analista de su cartera, roles CRM)
  ve el motivo; la ruta del respaldo solo el admin vigente (solo él puede abrir el bucket).

## Contexto verificado en el código (producción)
- `crm.cuentas_bancarias`: versiones; `private.trg_cuentas_bancarias_version_inmutable`
  (20260803221622:137-160) permite activa true→false con desactivada_en y PROHÍBE reactivar
  («Una version bancaria historica no se reactiva; registra una cuenta nueva»). La migración exige su
  md5 como precondición.
- Lecturas de cuentas vigentes (20260925153226): `private.cuentas_cliente_vigentes` =
  `crm.cuentas_bancarias where activa is true`; la usan `crm.cuentas_bancarias_cliente_fn` (selector
  del CRM, ventana «Cuentas» del portal, «Cambiar cuenta de pago») y `mis_cuentas_bancarias_fn` (vista
  del cliente).
- Alta de contrato con cuenta existente (20260925210000:499-516):
  `select … where id = … and cliente_id = … and moneda = … and activa = true for share` → si no,
  «La cuenta bancaria no esta disponible». Modos 'perfil'/'nueva' re-registran por CCI con candado
  consultivo y `… and activa = true for update` (si no hay vigente con ese CCI, insertan una nueva).
- F3 (en producción): el cambio exige cuenta nueva `activa` y la bloquea FOR SHARE; sus sellos por
  cuota y su historial leen la cuenta por id (vigente o no).
- Registrar un pago: trigger 00 bloquea el CONTRATO FOR UPDATE; trigger 10 lee enlace+contrato FOR
  SHARE y acepta enlaces a cuentas inactivas («La cuenta vinculada puede haber sido versionada y estar
  inactiva: sigue siendo la instrucción contractual»).
- `private.puede_gestionar_cuentas_cliente` (20260821222348): P04 + gestor de cartera, analista de su
  cartera o rol CRM con visibilidad; exige cliente activo.
- Bucket `respaldos-cambio-cuenta` (F3): políticas solo para admin vigente con nombre
  `<cliente_uuid>/<uuid>.(pdf|jpg|jpeg|png)`, fronteras RESTRICTIVE.

## Evidencia de ejecución
- Banco Docker con el esquema de producción: F3 (prerrequisito) + F4 aplicadas → 15 comprobaciones
  con 8 mutantes cazados (ver abajo) → la prueba de F3 sigue en verde con F4 aplicada → registro con
  huella de 5 funciones ensayado → la reversa se niega con retiros registrados (ensayado) → reversas
  → catálogo idéntico (2052 líneas).
- Portal: 158/158 tests. Navegador local con Supabase simulado: botones «Retirar» solo para admin;
  motivo obligatorio; rechazo por contratos abiertos con lista y atajo a F3; retiro correcto → sale de
  las vigentes y aparece en «Cuentas anteriores» con motivo; adjunto con ruta correcta; «Ver correo»
  con URL firmada de 5 min; el analista no ve «Retirar».


### Casos del test (avisos emitidos)
```
OK permisos: operaciones, analista, cliente y admin revocado (P04) → 42501
OK reglas: motivo, cuenta ajena/inexistente/ya retirada, contrato activo o vencido (con su lista), respaldo ajeno/inexistente/inválido/de otro admin; ningún rechazo cambia nada
OK retiro: la cuenta queda retirada con fecha, quién, motivo y respaldo; doble clic no duplica; otra vez da un mensaje claro; deja de ofrecerse y no se reactiva
OK constancias: lo pagado y el historial de cambios siguen nombrando la cuenta retirada; «Cambiar cuenta de pago» no la acepta
OK lectura: admin ve motivos y respaldo; analista de la cartera y operaciones ven motivos sin respaldo; cliente, admin revocado y anon 42501
OK candados: el registro del retiro no se modifica ni se borra
OK anon: 42501
OK mutante 1 cazado (sin compuerta, Operaciones retiraría cuentas)
OK mutante 1b cazado (sin P04, un admin revocado retiraría cuentas)
OK mutante 2 cazado (sin mirar contratos abiertos, se retiraría una cuenta que cobra)
OK mutante 3 cazado (sin exigir vigente, una cuenta ya retirada no daría su mensaje claro)
OK mutante 4 cazado (sin idempotencia, el doble clic fallaría)
OK mutante 5 cazado (sin comprobar quién subió el respaldo, valdría el de otro admin)
OK mutante 6 cazado (sin reservar la ruta, el analista vería el correo del cliente)
OK mutante 7 cazado (sin candado, el motivo del retiro se podría reescribir)
```

## Migración (texto íntegro) — CRM-Avance-Corp/supabase/migrations/20260927012948_crm_retirar_cuenta_cliente.sql
```sql
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
--      VIGENTE del cliente indicado; si todavía es la cuenta de pago de algún contrato abierto
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
                check (motivo = btrim(motivo) and length(motivo) between 5 and 500),
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
  v_motivo text := pg_catalog.btrim(coalesce(p_motivo, ''));
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
  if pg_catalog.length(v_motivo) not between 5 and 500 then
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
    raise exception using errcode = '22023',
      message = pg_catalog.format('La cuenta ya estaba retirada desde el %s%s',
        pg_catalog.to_char(v_cuenta.desactivada_en at time zone 'America/Lima', 'DD/MM/YYYY'),
        case when v_quien is not null then ' por ' || v_quien else '' end);
  end if;

  -- Contratos abiertos que todavía cobran en ella: primero se cambia su cuenta de pago (F3).
  select pg_catalog.array_agg(ct.numero_contrato order by ct.numero_contrato) into v_abiertos
  from crm.contrato_cuentas_pago l
  join public.contratos ct on ct.id = l.contrato_id
  where l.cuenta_bancaria_id = p_cuenta_id
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
comment on column crm.cuentas_bancarias_retiros.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';
comment on column crm.cuentas_bancarias_retiros.respaldo_ruta is 'Opcional: ruta en el bucket privado respaldos-cambio-cuenta del correo del cliente. DATO SENSIBLE.';
comment on column crm.cuentas_bancarias_retiros.retirado_por is 'Administrador que retiró la cuenta (id de perfil, sin FK).';
comment on column crm.cuentas_bancarias_retiros.retirado_en is 'Momento del retiro (hora de la transacción; igual a desactivada_en de la cuenta).';
comment on function private.trg_retiro_cuenta_inmutable() is 'Candado de crm.cuentas_bancarias_retiros: ni UPDATE ni DELETE. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text) is 'Núcleo del retiro de una cuenta bancaria: solo admin vigente (P04); solo cuentas vigentes del cliente; rechaza (22023, detail contratos_abiertos) si cobra contratos activo/vencido; motivo obligatorio y respaldo opcional (propio del admin); idempotente por solicitud; todo o nada. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias, el enlace, el registro ni storage.objects.';
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
      where tgrelid = 'crm.cuentas_bancarias_retiros'::regclass and not tgisinternal) <> 2 then
    raise exception 'RETIRO_CUENTA: faltan los triggers del registro';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Test (texto íntegro) — CRM-Avance-Corp/supabase/scripts/cuentas-gloria/test-retirar-cuenta-cliente.sql
```sql
-- PRUEBA de 20260927012948_crm_retirar_cuenta_cliente (F4) — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra usuarios, contratos, cuentas y archivos FICTICIOS en UNA
-- transacción que termina en ROLLBACK. Requiere aplicadas la F3 (20260926204051) y la F4.
--
-- Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-retirar-cuenta-cliente.sql
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

-- Paridad con producción: la exigencia de cuenta al registrar un pago (P-0XX S3).
select to_regprocedure('private.exigir_cuenta_pago_cronograma()') is null as falta_exigir \gset
\if :falta_exigir
\ir ../../migrations/20260925194026_p0xx_pagos_solo_cuenta_contractual.sql
\endif

-- ── Siembra ficticia ─────────────────────────────────────────────────────────────────────────
-- 01 admin · 02 operaciones · 03 analista (asesor de C) · 04 superadmin · 05 cliente C ·
-- 06 cliente D · 07 admin con la membresía CRM revocada · 08 otro admin.
insert into auth.users (id, email, aud, role) values
  ('e7b40000-0000-4000-8000-000000000001', 'f4.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000002', 'f4.oper@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000003', 'f4.analista@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000004', 'f4.super@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000005', 'f4.cliente.c@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000006', 'f4.cliente.d@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000007', 'f4.revocada@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000008', 'f4.admin2@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, nombres, dni, correo, rol, activo, asesor_perfil_id) values
  ('e7b40000-0000-4000-8000-000000000001', 'F4 ADMIN PRUEBA', null, '77740001', 'f4.admin@prueba.invalid', 'admin', true, null),
  ('e7b40000-0000-4000-8000-000000000002', 'F4 OPERACIONES PRUEBA', null, '77740002', 'f4.oper@prueba.invalid', 'operaciones', true, null),
  ('e7b40000-0000-4000-8000-000000000003', 'F4 ANALISTA PRUEBA', null, '77740003', 'f4.analista@prueba.invalid', 'analista', true, null),
  ('e7b40000-0000-4000-8000-000000000004', 'F4 SUPERADMIN PRUEBA', null, '77740004', 'f4.super@prueba.invalid', 'superadmin', true, null),
  ('e7b40000-0000-4000-8000-000000000005', 'PRUEBA CLIENTE CE', 'CLIENTE', '77740005', 'f4.cliente.c@prueba.invalid', 'cliente', true, 'e7b40000-0000-4000-8000-000000000003'),
  ('e7b40000-0000-4000-8000-000000000006', 'PRUEBA CLIENTE DE', 'CLIENTE', '77740006', 'f4.cliente.d@prueba.invalid', 'cliente', true, 'e7b40000-0000-4000-8000-000000000003'),
  ('e7b40000-0000-4000-8000-000000000007', 'F4 ADMIN REVOCADA', null, '77740007', 'f4.revocada@prueba.invalid', 'admin', true, null),
  ('e7b40000-0000-4000-8000-000000000008', 'F4 ADMIN DOS', null, '77740008', 'f4.admin2@prueba.invalid', 'admin', true, null);
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('e7b40000-0000-4000-8000-000000000007', 'gerencia', false);

-- Cuentas del cliente C: A (cobra K1 activo), A2 (cobra K2 vencido), B (solo K4 renovado),
-- C2 (cobra K6 activo, con una cuota pagada), X (ya retirada), U (USD, libre), T (libre).
-- Z es del cliente D.
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, activa, origen, creado_en, desactivada_por, desactivada_en) values
  ('e7b4c000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros', '19100000000001', '00219100000000000001', false, true, 'contrato', '2026-01-01', null, null),
  ('e7b4c000-0000-4000-8000-000000000002', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'BBVA', 'ahorros', '01100000000002', '01110000000000000002', false, true, 'contrato', '2026-01-02', null, null),
  ('e7b4c000-0000-4000-8000-000000000003', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros', '89830000000003', '00389800000000000003', false, true, 'contrato', '2026-01-03', null, null),
  ('e7b4c000-0000-4000-8000-000000000004', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Scotiabank', 'ahorros', '00070000000004', '00907000000000000004', false, true, 'contrato', '2026-01-04', null, null),
  ('e7b4c000-0000-4000-8000-000000000005', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'BanBif', 'ahorros', '70000000000005', '03870000000000000005', false, false, 'contrato', '2025-01-01', 'e7b40000-0000-4000-8000-000000000001', '2026-06-01 15:00-05'),
  ('e7b4c000-0000-4000-8000-000000000006', 'e7b40000-0000-4000-8000-000000000005', 'USD', 'BCP', 'ahorros', '19100000000006', '00219100000000000006', false, true, 'contrato', '2026-01-06', null, null),
  ('e7b4c000-0000-4000-8000-000000000007', 'e7b40000-0000-4000-8000-000000000006', 'PEN', 'BCP', 'ahorros', '19100000000007', '00219100000000000007', false, true, 'contrato', '2026-01-07', null, null),
  ('e7b4c000-0000-4000-8000-000000000008', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Pichincha', 'ahorros', '27000000000008', '03527000000000000008', false, true, 'contrato', '2026-01-08', null, null);

alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial) values
  ('e7b4d000-0000-4000-8000-000000000001', 'F4-K1', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b4d000-0000-4000-8000-000000000002', 'F4-K2', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'vencido',  '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b4d000-0000-4000-8000-000000000004', 'F4-K4', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'renovado', '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b4d000-0000-4000-8000-000000000006', 'F4-K6', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01');
alter table public.contratos enable trigger user;

insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values
  ('e7b4d000-0000-4000-8000-000000000001', 'e7b4c000-0000-4000-8000-000000000001'),
  ('e7b4d000-0000-4000-8000-000000000002', 'e7b4c000-0000-4000-8000-000000000002'),
  ('e7b4d000-0000-4000-8000-000000000004', 'e7b4c000-0000-4000-8000-000000000003'),
  ('e7b4d000-0000-4000-8000-000000000006', 'e7b4c000-0000-4000-8000-000000000004');

-- K6 #1 nace pagada: el sello de la F3 la anota en C2.
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado) values
  ('e7b4e000-0000-4000-8000-000000000061', 'e7b4d000-0000-4000-8000-000000000006', 1, '2026-02-01', 100, 'pagado');

-- Respaldos (como postgres), con quién los subió.
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000001.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f401\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000006/e7b4f000-0000-4000-8000-000000000002.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f402\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000003.pdf',
   'e7b40000-0000-4000-8000-000000000008', 'e7b40000-0000-4000-8000-000000000008', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f403\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000004.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "text/plain", "eTag": "\"f404\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000005.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f405\""}');

-- ── Utilidades ───────────────────────────────────────────────────────────────────────────────
-- Intenta retirar como un usuario; devuelve 'OK:<json>' o 'ERR:<sqlstate>:<mensaje>|<detail>'.
create function pg_temp.retirar(p_uid uuid, p_sol uuid, p_cuenta uuid, p_mot text, p_ruta text default null,
  p_cli uuid default 'e7b40000-0000-4000-8000-000000000005') returns text
language plpgsql as $f$
declare r jsonb; e text; m text; d text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.retirar_cuenta_cliente(p_sol, p_cli, p_cuenta, p_mot, p_ruta);
    execute 'reset role';
    return 'OK:' || r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text, d = pg_exception_detail;
    execute 'reset role';
    return 'ERR:' || e || ':' || m || '|' || coalesce(d, '');
  end;
end;
$f$;
-- Cambio de cuenta de pago de la F3 (para el caso «lo pagado sigue nombrando la cuenta retirada»).
create function pg_temp.cambio(p_uid uuid, p_sol uuid, p_cta uuid, p_ids uuid[], p_mot text, p_ruta text,
  p_cli uuid default 'e7b40000-0000-4000-8000-000000000005') returns text
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.cambiar_cuenta_pago_contratos(p_sol, p_cli, p_cta, p_ids, p_mot, p_ruta);
    execute 'reset role';
    return 'OK:' || r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR:' || e || ':' || m;
  end;
end;
$f$;
-- Lee los retiros como un usuario; devuelve el JSON de filas o 'ERR:<sqlstate>'.
create function pg_temp.leer_retiros(p_uid uuid, p_rol text default 'authenticated') returns text
language plpgsql as $f$
declare r jsonb; e text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_rol) else json_build_object('sub', p_uid, 'role', p_rol) end::text, true);
  execute format('set local role %I', p_rol);
  begin
    select coalesce(jsonb_agg(to_jsonb(x) order by x.retirado_en, x.cuenta_id), '[]'::jsonb) into r
    from crm.retiros_cuentas_cliente_fn('e7b40000-0000-4000-8000-000000000005') x;
    execute 'reset role';
    return r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate;
    execute 'reset role';
    return 'ERR:' || e;
  end;
end;
$f$;
create function pg_temp.espera(p_resultado text, p_prefijo text, p_caso text) returns void
language plpgsql as $f$
begin
  if p_resultado is null or p_resultado not like p_prefijo || '%' then
    raise exception 'FALLO [%]: esperaba «%…», vino «%»', p_caso, p_prefijo, p_resultado;
  end if;
end;
$f$;
create function pg_temp.activa(p_cuenta uuid) returns boolean language sql as $f$
  select activa from crm.cuentas_bancarias where id = p_cuenta;
$f$;
create function pg_temp.mutar(p_firma text, p_de text, p_a text) returns void
language plpgsql as $f$
declare s text; t text;
begin
  s := pg_get_functiondef(p_firma::regprocedure);
  t := replace(s, p_de, p_a);
  if t = s then raise exception 'MUTANTE MAL ESCRITO: no se encontró el fragmento en %', p_firma; end if;
  execute t;
end;
$f$;

-- ── A. Permisos y reglas ─────────────────────────────────────────────────────────────────────
do $reglas$
declare
  A constant uuid := 'e7b4c000-0000-4000-8000-000000000001';
  A2 constant uuid := 'e7b4c000-0000-4000-8000-000000000002';
  B constant uuid := 'e7b4c000-0000-4000-8000-000000000003';
  X constant uuid := 'e7b4c000-0000-4000-8000-000000000005';
  Z constant uuid := 'e7b4c000-0000-4000-8000-000000000007';
  T constant uuid := 'e7b4c000-0000-4000-8000-000000000008';
  ADMIN constant uuid := 'e7b40000-0000-4000-8000-000000000001';
  S constant uuid := 'e7b4a000-0000-4000-8000-000000000099';
  MOT constant text := 'El cliente cerró esa cuenta';
  u uuid;
begin
  foreach u in array array['e7b40000-0000-4000-8000-000000000002', 'e7b40000-0000-4000-8000-000000000003',
                           'e7b40000-0000-4000-8000-000000000005', 'e7b40000-0000-4000-8000-000000000007']::uuid[] loop
    perform pg_temp.espera(pg_temp.retirar(u, S, T, MOT), 'ERR:42501', 'permiso ' || u);
  end loop;
  raise notice 'OK permisos: operaciones, analista, cliente y admin revocado (P04) → 42501';

  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, 'x'), 'ERR:22023:Escribe el motivo', 'motivo corto');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, '     '), 'ERR:22023:Escribe el motivo', 'motivo en blanco');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, Z, MOT), 'ERR:22023:La cuenta no es de este cliente', 'cuenta ajena');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, gen_random_uuid(), MOT), 'ERR:22023:La cuenta no es de este cliente', 'cuenta inexistente');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, X, MOT), 'ERR:22023:La cuenta ya estaba retirada desde el 01/06/2026 por F4 ADMIN PRUEBA', 'ya retirada');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, A, MOT),
    'ERR:22023:La cuenta todavía cobra el contrato F4-K1. Primero cambia su cuenta de pago|contratos_abiertos', 'contrato activo');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, A2, MOT),
    'ERR:22023:La cuenta todavía cobra el contrato F4-K2. Primero cambia su cuenta de pago|contratos_abiertos', 'contrato vencido');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000006/e7b4f000-0000-4000-8000-000000000002.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo de otro cliente');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-0000000000ff.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo inexistente');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/libre.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo con nombre inválido');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000004.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo que no es PDF/imagen');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000003.pdf'),
    'ERR:22023:El respaldo debe subirlo quien retira la cuenta', 'respaldo de otro admin');
  if exists (select 1 from crm.cuentas_bancarias_retiros)
     or not pg_temp.activa(A) or not pg_temp.activa(A2) or not pg_temp.activa(B) or not pg_temp.activa(T) then
    raise exception 'FALLO: un rechazo dejó cambios';
  end if;
  raise notice 'OK reglas: motivo, cuenta ajena/inexistente/ya retirada, contrato activo o vencido (con su lista), respaldo ajeno/inexistente/inválido/de otro admin; ningún rechazo cambia nada';
end;
$reglas$;

-- ── B. Retiro correcto, idempotencia, respaldo y la cuenta desaparece de las vigentes ────────
do $retiro$
declare
  v text; n integer;
  B constant uuid := 'e7b4c000-0000-4000-8000-000000000003';
  U constant uuid := 'e7b4c000-0000-4000-8000-000000000006';
  ADMIN constant uuid := 'e7b40000-0000-4000-8000-000000000001';
  S1 constant uuid := 'e7b4a000-0000-4000-8000-000000000001';
  S2 constant uuid := 'e7b4a000-0000-4000-8000-000000000002';
  R1 constant text := 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000001.pdf';
begin
  -- B solo cobraba un contrato ya renovado: se puede retirar (sin respaldo).
  v := pg_temp.retirar(ADMIN, S1, B, 'El cliente cerró su cuenta Interbank');
  perform pg_temp.espera(v, 'OK:', 'retiro de B');
  if pg_temp.activa(B)
     or (select desactivada_por from crm.cuentas_bancarias where id = B) is distinct from ADMIN
     or (select desactivada_en from crm.cuentas_bancarias where id = B) is distinct from now()
     or (select count(*) from crm.cuentas_bancarias_retiros
         where cuenta_id = B and solicitud_id = S1 and motivo = 'El cliente cerró su cuenta Interbank'
           and respaldo_ruta is null and retirado_por = ADMIN and moneda = 'PEN') <> 1 then
    raise exception 'FALLO: el retiro de B no dejó la cuenta retirada con su constancia: %', v;
  end if;
  -- Idempotencia y mensajes claros.
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S1, B, 'El cliente cerró su cuenta Interbank'), 'OK:{"cuenta_id": "e7b4c000-0000-4000-8000-000000000003", "ya_aplicada": true', 'doble clic');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S1, B, 'Otro motivo distinto'), 'ERR:22023:Esta solicitud ya se usó con otros datos', 'solicitud con otros datos');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S2, B, 'El cliente cerró su cuenta Interbank'),
    'ERR:22023:La cuenta ya estaba retirada desde el ' || to_char(now() at time zone 'America/Lima', 'DD/MM/YYYY') || ' por F4 ADMIN PRUEBA', 'retirar otra vez');
  -- Con respaldo (el correo del cliente, subido por el mismo admin).
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S2, U, 'El cliente pidió dejar de usar su cuenta en dólares', R1), 'OK:', 'retiro con respaldo');
  if (select respaldo_ruta from crm.cuentas_bancarias_retiros where cuenta_id = U) is distinct from R1 then
    raise exception 'FALLO: el retiro de U debía guardar su respaldo';
  end if;
  -- Ya no se ofrecen: la lectura de vigentes (la que usan el CRM y la ventana «Cuentas») no las trae.
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  select count(*) into n from crm.cuentas_bancarias_cliente_fn('e7b40000-0000-4000-8000-000000000005', 'PEN') c where c.cuenta_id = B;
  if n <> 0 then raise exception 'FALLO: la cuenta retirada B sigue entre las vigentes'; end if;
  select count(*) into n from crm.cuentas_bancarias_cliente_fn('e7b40000-0000-4000-8000-000000000005', 'USD') c where c.cuenta_id = U;
  if n <> 0 then raise exception 'FALLO: la cuenta retirada U sigue entre las vigentes'; end if;
  -- Nunca se reactiva (candado de versiones).
  begin
    update crm.cuentas_bancarias set activa = true, desactivada_por = null, desactivada_en = null where id = B;
    raise exception 'FALLO: una cuenta retirada se pudo reactivar';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK retiro: la cuenta queda retirada con fecha, quién, motivo y respaldo; doble clic no duplica; otra vez da un mensaje claro; deja de ofrecerse y no se reactiva';
end;
$retiro$;

-- ── C. Lo pagado y el historial siguen nombrando la cuenta retirada; F3 ya no la ofrece ──────
do $constancias$
declare
  r record; v_json jsonb; v_banco text;
  A constant uuid := 'e7b4c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b4c000-0000-4000-8000-000000000003';
  C2 constant uuid := 'e7b4c000-0000-4000-8000-000000000004';
  ADMIN constant uuid := 'e7b40000-0000-4000-8000-000000000001';
begin
  -- K6 cobraba en C2 (con una cuota pagada allí): se cambia a A con la F3 y después se retira C2.
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b4a000-0000-4000-8000-000000000031', A,
    array['e7b4d000-0000-4000-8000-000000000006'::uuid], 'El cliente pidió cobrar en su cuenta BCP',
    'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000005.pdf'), 'OK:', 'cambio F3 de K6');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, 'e7b4a000-0000-4000-8000-000000000003', C2,
    'El cliente cerró su cuenta Scotiabank'), 'OK:', 'retiro de C2 tras el cambio');
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  select * into r from crm.contratos_cuenta_pago_cliente_fn('e7b40000-0000-4000-8000-000000000005') where numero_contrato = 'F4-K6';
  if r.cuenta_bancaria_id is distinct from A
     or not exists (select 1 from jsonb_array_elements(r.pagadas_por_cuenta) p
                    where p->>'cuenta_bancaria_id' = C2::text and p->>'banco' = 'Scotiabank' and (p->>'cuotas')::int = 1) then
    raise exception 'FALLO: la cuota pagada en C2 debía seguir mostrando C2 tras retirarla: %', row_to_json(r);
  end if;
  select h.banco_anterior into v_banco from crm.cambios_cuenta_pago_cliente_fn('e7b40000-0000-4000-8000-000000000005') h
  where h.numero_contrato = 'F4-K6';
  if v_banco is distinct from 'Scotiabank' then
    raise exception 'FALLO: el historial de cambios debía seguir nombrando la cuenta retirada, mostró %', v_banco;
  end if;
  -- «Cambiar cuenta de pago» no ofrece ni acepta una cuenta retirada.
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b4a000-0000-4000-8000-000000000032', B,
    array['e7b4d000-0000-4000-8000-000000000001'::uuid], 'Prueba de cuenta retirada',
    'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000001.pdf'), 'ERR:22023:La cuenta nueva ya no está vigente', 'F3 con cuenta retirada');
  raise notice 'OK constancias: lo pagado y el historial de cambios siguen nombrando la cuenta retirada; «Cambiar cuenta de pago» no la acepta';
end;
$constancias$;

-- ── D. Lectura de motivos para «Cuentas anteriores» ─────────────────────────────────────────
do $lectura$
declare v text; j jsonb;
begin
  v := pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000001');
  j := v::jsonb;
  if jsonb_array_length(j) <> 3
     or (select count(*) from jsonb_array_elements(j) x where x->>'respaldo_ruta' is not null) <> 1
     or (select count(*) from jsonb_array_elements(j) x where x->>'retirado_por_nombre' = 'F4 ADMIN PRUEBA') <> 3 then
    raise exception 'FALLO: el admin debía ver los 3 retiros con quién y el respaldo del de U: %', v;
  end if;
  foreach v in array array[pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000003'),
                           pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000002')] loop
    j := v::jsonb;
    if jsonb_array_length(j) <> 3
       or exists (select 1 from jsonb_array_elements(j) x where x->>'respaldo_ruta' is not null)
       or not exists (select 1 from jsonb_array_elements(j) x where x->>'motivo' = 'El cliente cerró su cuenta Interbank') then
      raise exception 'FALLO: analista y operaciones debían ver los motivos sin la ruta del respaldo: %', v;
    end if;
  end loop;
  perform pg_temp.espera(pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000005'), 'ERR:42501', 'cliente');
  perform pg_temp.espera(pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000007'), 'ERR:42501', 'admin revocado');
  perform pg_temp.espera(pg_temp.leer_retiros(null, 'anon'), 'ERR:42501', 'anon');
  raise notice 'OK lectura: admin ve motivos y respaldo; analista de la cartera y operaciones ven motivos sin respaldo; cliente, admin revocado y anon 42501';
end;
$lectura$;

-- ── E. El registro no se modifica ni se borra; anon no retira ───────────────────────────────
do $candados$
begin
  begin
    update crm.cuentas_bancarias_retiros set motivo = 'reescrito por prueba';
    raise exception 'FALLO: el retiro se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    delete from crm.cuentas_bancarias_retiros;
    raise exception 'FALLO: el retiro se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK candados: el registro del retiro no se modifica ni se borra';
end;
$candados$;
set local role anon;
do $anon$
begin
  begin
    perform crm.retirar_cuenta_cliente(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo largo');
    raise exception 'FALLO: anon pudo retirar';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK anon: 42501';
end;
$anon$;
reset role;

-- ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
-- M1: el núcleo sin compuerta → Operaciones retiraría cuentas.
savepoint m1;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  'if not coalesce(private.admin_banca_vigente(v_actor), false) then', 'if false then');
do $m1$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000002', 'e7b4a000-0000-4000-8000-0000000000a1',
    'e7b4c000-0000-4000-8000-000000000008', 'El cliente la cerró'), 'OK:', 'MUTANTE 1 NO CAZADO');
  raise notice 'OK mutante 1 cazado (sin compuerta, Operaciones retiraría cuentas)';
end $m1$;
rollback to savepoint m1;

-- M1b: la compuerta sin P04 → un admin revocado retiraría cuentas.
savepoint m1b;
select pg_temp.mutar('private.admin_banca_vigente(uuid)', 'e.perfil_id = p_uid and e.activo is false', 'false');
do $m1b$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000007', 'e7b4a000-0000-4000-8000-0000000000b1',
    'e7b4c000-0000-4000-8000-000000000008', 'El cliente la cerró'), 'OK:', 'MUTANTE 1b NO CAZADO');
  raise notice 'OK mutante 1b cazado (sin P04, un admin revocado retiraría cuentas)';
end $m1b$;
rollback to savepoint m1b;

-- M2: el núcleo sin mirar contratos abiertos → se retiraría la cuenta que cobra F4-K1.
savepoint m2;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  'if coalesce(pg_catalog.cardinality(v_abiertos), 0) > 0 then', 'if false then');
do $m2$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a2',
    'e7b4c000-0000-4000-8000-000000000001', 'El cliente la cerró'), 'OK:', 'MUTANTE 2 NO CAZADO');
  raise notice 'OK mutante 2 cazado (sin mirar contratos abiertos, se retiraría una cuenta que cobra)';
end $m2$;
rollback to savepoint m2;

-- M3: el núcleo sin exigir cuenta vigente → retirar una ya retirada no diría con claridad que ya lo estaba.
savepoint m3;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  '  if not v_cuenta.activa then', '  if false then');
do $m3$ begin
  if pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a3',
       'e7b4c000-0000-4000-8000-000000000005', 'El cliente la cerró') like 'ERR:22023:La cuenta ya estaba retirada%' then
    raise exception 'MUTANTE 3 NO CAZADO';
  end if;
  raise notice 'OK mutante 3 cazado (sin exigir vigente, una cuenta ya retirada no daría su mensaje claro)';
end $m3$;
rollback to savepoint m3;

-- M4: el núcleo sin idempotencia → el doble clic fallaría en vez de confirmar.
savepoint m4;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  '  if found then
    if v_previo.cuenta_id = p_cuenta_id', '  if false then
    if v_previo.cuenta_id = p_cuenta_id');
do $m4$ begin
  if pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-000000000001',
       'e7b4c000-0000-4000-8000-000000000003', 'El cliente cerró su cuenta Interbank') like 'OK:%"ya_aplicada": true%' then
    raise exception 'MUTANTE 4 NO CAZADO';
  end if;
  raise notice 'OK mutante 4 cazado (sin idempotencia, el doble clic fallaría)';
end $m4$;
rollback to savepoint m4;

-- M5: el núcleo sin comprobar quién subió el respaldo → valdría el archivo de otro admin.
savepoint m5;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  'if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then', 'if false then');
do $m5$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a5',
    'e7b4c000-0000-4000-8000-000000000008', 'El cliente la cerró',
    'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000003.pdf'), 'OK:', 'MUTANTE 5 NO CAZADO');
  raise notice 'OK mutante 5 cazado (sin comprobar quién subió el respaldo, valdría el de otro admin)';
end $m5$;
rollback to savepoint m5;

-- M6: la lectura sin reservar la ruta al admin → el analista vería la ruta del correo.
savepoint m6;
select pg_temp.mutar('private.retiros_cuentas_cliente_autorizado(uuid)',
  'case when v_admin then r.respaldo_ruta end', 'r.respaldo_ruta');
do $m6$ begin
  if not exists (select 1 from jsonb_array_elements(pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000003')::jsonb) x
                 where x->>'respaldo_ruta' is not null) then
    raise exception 'MUTANTE 6 NO CAZADO';
  end if;
  raise notice 'OK mutante 6 cazado (sin reservar la ruta, el analista vería el correo del cliente)';
end $m6$;
rollback to savepoint m6;

-- M7: sin el candado del registro → el motivo se podría reescribir.
savepoint m7;
drop trigger trg_cuentas_bancarias_retiros_00_inmutable on crm.cuentas_bancarias_retiros;
do $m7$ declare n integer; begin
  update crm.cuentas_bancarias_retiros set motivo = 'reescrito por prueba';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'MUTANTE 7 NO CAZADO'; end if;
  raise notice 'OK mutante 7 cazado (sin candado, el motivo del retiro se podría reescribir)';
end $m7$;
rollback to savepoint m7;

select 'RETIRO_CUENTA_OK' as veredicto;
rollback;
```

## Reversa — CRM-Avance-Corp/supabase/scripts/cuentas-gloria/reversa-retirar-cuenta-cliente.sql
```sql
-- REVERSA de 20260927012948_crm_retirar_cuenta_cliente (F4).
-- Se NIEGA si ya hay retiros registrados (una cuenta retirada no se reactiva: revertir solo
-- borraría su constancia) o si las piezas vivas no son las ensayadas (huella completa de las 5
-- funciones: cuerpo, DEFINER, search_path, comentario y EXECUTE sin el dueño). No toca la F3.
begin;
set local lock_timeout = '5s';
do $pre$
declare
  v_funciones integer;
  v_huella text;
begin
  if to_regclass('crm.cuentas_bancarias_retiros') is null then
    raise exception 'REVERSA: la F4 no está aplicada';
  end if;
  if exists (select 1 from crm.cuentas_bancarias_retiros) then
    raise exception 'REVERSA: ya hay retiros de cuentas registrados; revertir borraría su constancia';
  end if;
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
        'private.trg_retiro_cuenta_inmutable()',
        'private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
        'crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)',
        'private.retiros_cuentas_cliente_autorizado(uuid)',
        'crm.retiros_cuentas_cliente_fn(uuid)']) f)
  ) s;
  if v_funciones <> 5 or v_huella is distinct from '241b9b5d33a0b01e57475e253edeaeb7' then
    raise exception 'REVERSA: las piezas vivas no son las de la F4 ensayada (% funciones, huella %); no se toca',
      v_funciones, v_huella;
  end if;
end $pre$;

drop function crm.retiros_cuentas_cliente_fn(uuid);
drop function private.retiros_cuentas_cliente_autorizado(uuid);
drop function crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text);
drop function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text);
drop table crm.cuentas_bancarias_retiros;
drop function private.trg_retiro_cuenta_inmutable();

do $chk$
begin
  if to_regclass('crm.cuentas_bancarias_retiros') is not null
     or to_regprocedure('crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)') is not null
     or to_regprocedure('private.trg_retiro_cuenta_inmutable()') is not null then
    raise exception 'REVERSA: quedaron piezas de la F4';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;
```

## Pantalla — public_html/js/admin/retiro-cuenta-core.js (íntegro)
```js
// Retirar una cuenta bancaria del cliente (F4, 26/09/2026). Núcleo puro de la ventana
// «Cuentas»: validación, textos y motivos para «Cuentas anteriores». Sin DOM ni red: lo prueba
// tests/retiro-cuenta-core.test.mjs. La frontera real está en el servidor
// (crm.retirar_cuenta_cliente): esto solo da buena experiencia.
import { validarRespaldo } from './cambio-cuenta-core.js?v=1'

// Motivo obligatorio (5 a 500); el correo del cliente es opcional, pero si se adjunta debe ser válido.
export function validarRetiro({ motivo, archivo }) {
  const texto = String(motivo ?? '').trim()
  if (texto.length < 5 || texto.length > 500) return 'Escribe el motivo del retiro (5 a 500 caracteres).'
  return archivo ? validarRespaldo(archivo) : null
}

// El servidor marca con detail = 'contratos_abiertos' el rechazo por contratos que aún cobran ahí.
export function esPorContratosAbiertos(error) {
  return error?.details === 'contratos_abiertos'
}

// Traduce los errores del servidor sin inventar: sus mensajes ya son para personas.
export function mensajeErrorRetiro(error) {
  if (!error) return 'No se pudo retirar la cuenta.'
  if (error.code === '42501') return 'Solo administración puede retirar cuentas.'
  if (error.code === '22023' && error.message) return error.message
  return 'No se pudo retirar la cuenta. Recarga la ventana y vuelve a intentar.'
}

export function textoExitoRetiro(data) {
  const cuenta = data?.banco ? `${data.banco} ••••${data.ultimos || ''}` : 'La cuenta'
  if (data?.ya_aplicada) return `${cuenta} ya estaba retirada con esta misma solicitud.`
  return `${cuenta} retirada. Ya no se ofrece y queda en «Cuentas anteriores».`
}

// Suma el motivo de cada retiro al texto de «Cuentas anteriores». Si el retiro no pasó por esta
// operación (p. ej., una versión reemplazada al editar la cuenta), no hay motivo y queda igual.
export function unirMotivos(anteriores, retiros) {
  const porCuenta = new Map((Array.isArray(retiros) ? retiros : []).map((r) => [r.cuenta_id, r]))
  return anteriores.map((c) => {
    const r = porCuenta.get(c.id)
    if (!r?.motivo) return c
    return { ...c, retiro: `${c.retiro} · Motivo: «${r.motivo}»`, respaldo_ruta: r.respaldo_ruta || null }
  })
}
```

## Pantalla — funciones nuevas de public_html/js/admin/clientes.js
```js
/* ---------- Retirar una cuenta (F4, solo admin/superadmin; nunca se borra) ---------- */

// Un botón «Retirar» junto a cada cuenta vigente. pintarCuentasCliente pinta un <li> por cuenta
// de esa moneda y en el mismo orden; si no coincide, no se añade nada (mejor sin botón que en
// la cuenta equivocada).
function agregarBotonesRetiro(elemento, cuentas, moneda) {
  const filtradas = cuentas.filter((c) => c.moneda === moneda)
  const items = elemento.querySelectorAll('li')
  if (items.length !== filtradas.length) return
  items.forEach((li, i) => {
    const cuenta = filtradas[i]
    if (!cuenta?.id) return
    const btn = document.createElement('button')
    btn.type = 'button'
    btn.className = 'btn btn-secondary'
    btn.style.cssText = 'margin-left: 8px; padding: 2px 10px; font-size: 13px;'
    btn.textContent = 'Retirar'
    btn.addEventListener('click', () => abrirRetiro(cuenta))
    li.appendChild(btn)
  })
}

// «Ver correo» en las cuentas anteriores cuyo retiro trae respaldo (la ruta solo llega al admin).
function agregarVerCorreoAnteriores(elemento, cuentas) {
  const items = elemento.querySelectorAll('li')
  if (items.length !== cuentas.length) return
  items.forEach((li, i) => {
    const ruta = cuentas[i]?.respaldo_ruta
    if (!ruta) return
    const ver = document.createElement('button')
    ver.type = 'button'
    ver.className = 'btn btn-secondary'
    ver.style.cssText = 'margin-left: 8px; padding: 2px 10px; font-size: 13px;'
    ver.textContent = 'Ver correo'
    ver.addEventListener('click', () => void verRespaldo(ruta))
    li.appendChild(ver)
  })
}

function abrirRetiro(cuenta) {
  if (RETIRO_GUARDANDO) return
  RETIRO = {
    clienteId: document.getElementById('cb_clienteId').value,
    cuenta,
    solicitudId: crypto.randomUUID(),
    archivoId: crypto.randomUUID(),
    apertura: RETIRO.apertura + 1,
  }
  const moneda = cuenta.moneda === 'USD' ? 'Dólares' : 'Soles'
  document.getElementById('cb_retiro_cuenta').textContent = `${moneda} · ${textoCuenta(cuenta)}`
  document.getElementById('cb_retiro_motivo').value = ''
  document.getElementById('cb_retiro_respaldo').value = ''
  document.getElementById('cb_retiro_error').classList.add('hidden')
  document.getElementById('btnRetiroIrCambio').classList.add('hidden')
  const grupo = document.getElementById('cb_retiro_group')
  grupo.classList.remove('hidden')
  grupo.scrollIntoView({ block: 'nearest' })
  document.getElementById('cb_retiro_motivo').focus()
}

function cerrarRetiro() {
  if (RETIRO_GUARDANDO) return
  RETIRO = { ...RETIRO, cuenta: null }
  document.getElementById('cb_retiro_group').classList.add('hidden')
}

async function confirmarRetiro() {
  const errEl = document.getElementById('cb_retiro_error')
  errEl.classList.add('hidden')
  const btn = document.getElementById('btnConfirmarRetiro')
  if (btn.disabled || RETIRO_GUARDANDO || !RETIRO.cuenta) return
  // Todo lo de esta operación se fija AHORA: los await siguientes no leen estado global.
  const { clienteId, solicitudId, archivoId, apertura, cuenta } = RETIRO
  const motivo = document.getElementById('cb_retiro_motivo').value.trim()
  const archivo = document.getElementById('cb_retiro_respaldo').files?.[0] || null
  const falta = validarRetiro({ motivo, archivo })
  if (falta) {
    errEl.textContent = falta
    errEl.classList.remove('hidden')
    return
  }
  const sigueEnEsteCliente = () =>
    !document.getElementById('modalCuentas').classList.contains('hidden')
    && document.getElementById('cb_clienteId').value === clienteId
    && RETIRO.apertura === apertura
  RETIRO_GUARDANDO = true
  btn.disabled = true
  btn.textContent = 'Retirando…'
  document.getElementById('btnCancelarRetiro').disabled = true
  let hecho = false
  try {
    // Respaldo opcional: si se adjunta, va al bucket privado (una ruta por archivo, nunca se sustituye).
    let ruta = null
    if (archivo) {
      ruta = rutaRespaldo(clienteId, archivoId, archivo)
      const subida = await supabase.storage.from(BUCKET_RESPALDOS)
        .upload(ruta, archivo, { contentType: archivo.type, upsert: false })
      if (subida.error && !/exist/i.test(subida.error.message || '')) {
        throw new Error('No se pudo subir el correo del cliente. Vuelve a intentar.')
      }
    }
    const { data, error } = await supabase.schema('crm').rpc('retirar_cuenta_cliente', {
      p_solicitud_id: solicitudId,
      p_cliente_id: clienteId,
      p_cuenta_id: cuenta.id,
      p_motivo: motivo,
      p_respaldo_ruta: ruta,
    })
    if (error) {
      if (esPorContratosAbiertos(error) && sigueEnEsteCliente()) {
        document.getElementById('btnRetiroIrCambio').classList.remove('hidden')
      }
      throw new Error(mensajeErrorRetiro(error))
    }
    mostrarExito(textoExitoRetiro(data))
    hecho = true
  } catch (error) {
    const mensaje = error?.message || 'No se pudo retirar la cuenta.'
    if (!sigueEnEsteCliente()) {
      mostrarError(mensaje)
      return
    }
    errEl.textContent = mensaje
    errEl.classList.remove('hidden')
  } finally {
    RETIRO_GUARDANDO = false
    btn.disabled = false
    btn.textContent = 'Retirar cuenta'
    document.getElementById('btnCancelarRetiro').disabled = false
  }
  if (hecho && sigueEnEsteCliente()) {
    cerrarRetiro()
    cargarCuentasModal(clienteId)
  }
}

// La cuenta todavía cobra contratos abiertos: se cambia primero su cuenta de pago (F3).
function irDeRetiroACambio() {
  cerrarRetiro()
  abrirCambioPago()
  document.getElementById('cb_pago_group')?.scrollIntoView({ block: 'nearest' })
}

```

## Pantalla — diff de clientes.js y clientes.html
```diff
diff --git a/admin/clientes.html b/admin/clientes.html
index 8e265bd..1f6cd4f 100644
--- a/admin/clientes.html
+++ b/admin/clientes.html
@@ -567,6 +567,27 @@
           <p style="font-weight: 700; font-size: 14px; margin: 8px 0 4px; color: var(--navy);">Cuentas anteriores</p>
           <div id="cb_cuentas_anteriores" aria-live="polite" style="font-size: 14px; color: var(--text-secondary);">Cargando cuentas anteriores…</div>
 
+          <!-- Retirar una cuenta (F4): solo admin y superadmin; nunca se borra -->
+          <div id="cb_retiro_group" class="hidden" style="margin-top: 12px; padding: 12px; border: 1px solid var(--border); border-radius: var(--radius-sm);">
+            <p style="font-weight: 700; font-size: 14px; margin: 0 0 6px; color: var(--navy);">Retirar cuenta</p>
+            <p id="cb_retiro_cuenta" style="font-size: 14px; margin: 0 0 6px;"></p>
+            <p class="text-muted" style="font-size: 13px; margin: 0 0 10px;">Deja de ofrecerse en el portal y en el CRM, pero no se borra: queda en «Cuentas anteriores» con la fecha, quién la retiró y el motivo. No se avisa al cliente.</p>
+            <div class="input-group">
+              <label class="input-label" for="cb_retiro_motivo">Motivo</label>
+              <textarea class="input" id="cb_retiro_motivo" rows="2" maxlength="500" placeholder="Ej.: el cliente cerró esa cuenta"></textarea>
+            </div>
+            <div class="input-group">
+              <label class="input-label" for="cb_retiro_respaldo">Correo del cliente (opcional · PDF, JPG o PNG · máx. 10 MB)</label>
+              <input type="file" class="input" id="cb_retiro_respaldo" accept="application/pdf,image/jpeg,image/png">
+            </div>
+            <div id="cb_retiro_error" class="alert alert-danger hidden" role="alert"></div>
+            <div style="display: flex; gap: 8px; flex-wrap: wrap;">
+              <button type="button" class="btn btn-secondary" id="btnCancelarRetiro">Cancelar</button>
+              <button type="button" class="btn btn-primary" id="btnConfirmarRetiro">Retirar cuenta</button>
+              <button type="button" class="btn btn-secondary hidden" id="btnRetiroIrCambio">Ir a «Cambiar cuenta de pago»</button>
+            </div>
+          </div>
+
           <button type="button" class="btn btn-secondary" id="btnMostrarNuevaCuenta" style="margin-top: 8px;">+ Añadir cuenta</button>
 
           <!-- Cuenta de pago de los contratos (F3): solo admin y superadmin -->
@@ -700,7 +721,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/clientes.js?v=54"></script>
+  <script type="module" src="/js/admin/clientes.js?v=55"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
diff --git a/js/admin/clientes.js b/js/admin/clientes.js
index bc676c3..1472c0b 100644
--- a/js/admin/clientes.js
+++ b/js/admin/clientes.js
@@ -20,7 +20,7 @@ import { mensajeErrorGuardarCliente } from './clientes-errores-core.js?v=2'
 import { guardarCorreoCliente, validarCorreccionCorreo } from './correo-cliente-core.js?v=1'
 import {
   cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente,
-  cargarHistorialCuentas, pintarCuentasAnteriores
+  cargarHistorialCuentas, pintarCuentasAnteriores, textoCuenta
 } from './cuentas-cliente-core.js?v=5'
 // Cambio de la cuenta de pago de contratos por pedido del cliente (F3): núcleo puro.
 import {
@@ -28,6 +28,10 @@ import {
   motivoNoElegible, validarCambio, textoContrato, textoCambio, mensajeErrorCambio, textoExitoCambio,
   avisoPendiente, textoResultadoAviso
 } from './cambio-cuenta-core.js?v=1'
+// Retirar una cuenta bancaria (F4): núcleo puro.
+import {
+  validarRetiro, esPorContratosAbiertos, mensajeErrorRetiro, textoExitoRetiro, unirMotivos
+} from './retiro-cuenta-core.js?v=1'
 
 // CLIENTES_CACHE ahora guarda SOLO la página actual (max PAGE_SIZE filas).
 // El total real está en TOTAL_CLIENTES. Con paginación server-side el cache
@@ -48,6 +52,9 @@ let PUEDE_CAMBIAR_CUENTA_PAGO = false // admin/superadmin; el servidor revalida
 // el formulario y se reutiliza en reintentos: el servidor es idempotente por solicitud.
 let CAMBIO_PAGO = nuevoEstadoCambio(null, '')
 let CAMBIO_GUARDANDO = false
+// Retiro de una cuenta (F4) de la ventana abierta: ids fijados al abrir el formulario.
+let RETIRO = { clienteId: null, cuenta: null, solicitudId: null, archivoId: null, apertura: 0 }
+let RETIRO_GUARDANDO = false
 
 function nuevoEstadoCambio(clienteId, correo) {
   return {
@@ -646,15 +653,26 @@ function cargarCuentasModal(clienteId) {
     actualizarBotonCambio()
     pintarCuentasCliente(pen, cuentas, 'PEN')
     pintarCuentasCliente(usd, cuentas, 'USD')
+    if (PUEDE_CAMBIAR_CUENTA_PAGO) {
+      agregarBotonesRetiro(pen, cuentas, 'PEN')
+      agregarBotonesRetiro(usd, cuentas, 'USD')
+    }
   }).catch(() => {
     if (token !== CUENTAS_MODAL_TOKEN) return
     pen.textContent = 'No se pudieron cargar las cuentas. Vuelve a abrir la ventana.'
     usd.textContent = ''
   })
-  // El historial va aparte: si falla, las cuentas vigentes se siguen viendo.
-  void cargarHistorialCuentas(supabase, clienteId).then((cuentas) => {
+  // El historial va aparte: si falla, las cuentas vigentes se siguen viendo. Los motivos de
+  // retiro (F4) son un extra: si su lectura falla, el historial se muestra sin ellos.
+  void Promise.all([
+    cargarHistorialCuentas(supabase, clienteId),
+    supabase.schema('crm').rpc('retiros_cuentas_cliente_fn', { p_cliente_id: clienteId })
+      .then(({ data, error }) => (error || !Array.isArray(data) ? [] : data), () => []),
+  ]).then(([cuentas, retiros]) => {
     if (token !== CUENTAS_MODAL_TOKEN) return
-    pintarCuentasAnteriores(anteriores, cuentas)
+    const unidas = unirMotivos(cuentas, retiros)
+    pintarCuentasAnteriores(anteriores, unidas)
+    if (PUEDE_CAMBIAR_CUENTA_PAGO) agregarVerCorreoAnteriores(anteriores, unidas)
   }).catch(() => {
     if (token !== CUENTAS_MODAL_TOKEN) return
     anteriores.textContent = 'No se pudo cargar el historial. Vuelve a abrir la ventana.'
@@ -662,6 +680,149 @@ function cargarCuentasModal(clienteId) {
   cargarPagoModal(clienteId, token)
 }
 
+/* ---------- Retirar una cuenta (F4, solo admin/superadmin; nunca se borra) ---------- */
+
+// Un botón «Retirar» junto a cada cuenta vigente. pintarCuentasCliente pinta un <li> por cuenta
+// de esa moneda y en el mismo orden; si no coincide, no se añade nada (mejor sin botón que en
+// la cuenta equivocada).
+function agregarBotonesRetiro(elemento, cuentas, moneda) {
+  const filtradas = cuentas.filter((c) => c.moneda === moneda)
+  const items = elemento.querySelectorAll('li')
+  if (items.length !== filtradas.length) return
+  items.forEach((li, i) => {
+    const cuenta = filtradas[i]
+    if (!cuenta?.id) return
+    const btn = document.createElement('button')
+    btn.type = 'button'
+    btn.className = 'btn btn-secondary'
+    btn.style.cssText = 'margin-left: 8px; padding: 2px 10px; font-size: 13px;'
+    btn.textContent = 'Retirar'
+    btn.addEventListener('click', () => abrirRetiro(cuenta))
+    li.appendChild(btn)
+  })
+}
+
+// «Ver correo» en las cuentas anteriores cuyo retiro trae respaldo (la ruta solo llega al admin).
+function agregarVerCorreoAnteriores(elemento, cuentas) {
+  const items = elemento.querySelectorAll('li')
+  if (items.length !== cuentas.length) return
+  items.forEach((li, i) => {
+    const ruta = cuentas[i]?.respaldo_ruta
+    if (!ruta) return
+    const ver = document.createElement('button')
+    ver.type = 'button'
+    ver.className = 'btn btn-secondary'
+    ver.style.cssText = 'margin-left: 8px; padding: 2px 10px; font-size: 13px;'
+    ver.textContent = 'Ver correo'
+    ver.addEventListener('click', () => void verRespaldo(ruta))
+    li.appendChild(ver)
+  })
+}
+
+function abrirRetiro(cuenta) {
+  if (RETIRO_GUARDANDO) return
+  RETIRO = {
+    clienteId: document.getElementById('cb_clienteId').value,
+    cuenta,
+    solicitudId: crypto.randomUUID(),
+    archivoId: crypto.randomUUID(),
+    apertura: RETIRO.apertura + 1,
+  }
+  const moneda = cuenta.moneda === 'USD' ? 'Dólares' : 'Soles'
+  document.getElementById('cb_retiro_cuenta').textContent = `${moneda} · ${textoCuenta(cuenta)}`
+  document.getElementById('cb_retiro_motivo').value = ''
+  document.getElementById('cb_retiro_respaldo').value = ''
+  document.getElementById('cb_retiro_error').classList.add('hidden')
+  document.getElementById('btnRetiroIrCambio').classList.add('hidden')
+  const grupo = document.getElementById('cb_retiro_group')
+  grupo.classList.remove('hidden')
+  grupo.scrollIntoView({ block: 'nearest' })
+  document.getElementById('cb_retiro_motivo').focus()
+}
+
+function cerrarRetiro() {
+  if (RETIRO_GUARDANDO) return
+  RETIRO = { ...RETIRO, cuenta: null }
+  document.getElementById('cb_retiro_group').classList.add('hidden')
+}
+
+async function confirmarRetiro() {
+  const errEl = document.getElementById('cb_retiro_error')
+  errEl.classList.add('hidden')
+  const btn = document.getElementById('btnConfirmarRetiro')
+  if (btn.disabled || RETIRO_GUARDANDO || !RETIRO.cuenta) return
+  // Todo lo de esta operación se fija AHORA: los await siguientes no leen estado global.
+  const { clienteId, solicitudId, archivoId, apertura, cuenta } = RETIRO
+  const motivo = document.getElementById('cb_retiro_motivo').value.trim()
+  const archivo = document.getElementById('cb_retiro_respaldo').files?.[0] || null
+  const falta = validarRetiro({ motivo, archivo })
+  if (falta) {
+    errEl.textContent = falta
+    errEl.classList.remove('hidden')
+    return
+  }
+  const sigueEnEsteCliente = () =>
+    !document.getElementById('modalCuentas').classList.contains('hidden')
+    && document.getElementById('cb_clienteId').value === clienteId
+    && RETIRO.apertura === apertura
+  RETIRO_GUARDANDO = true
+  btn.disabled = true
+  btn.textContent = 'Retirando…'
+  document.getElementById('btnCancelarRetiro').disabled = true
+  let hecho = false
+  try {
+    // Respaldo opcional: si se adjunta, va al bucket privado (una ruta por archivo, nunca se sustituye).
+    let ruta = null
+    if (archivo) {
+      ruta = rutaRespaldo(clienteId, archivoId, archivo)
+      const subida = await supabase.storage.from(BUCKET_RESPALDOS)
+        .upload(ruta, archivo, { contentType: archivo.type, upsert: false })
+      if (subida.error && !/exist/i.test(subida.error.message || '')) {
+        throw new Error('No se pudo subir el correo del cliente. Vuelve a intentar.')
+      }
+    }
+    const { data, error } = await supabase.schema('crm').rpc('retirar_cuenta_cliente', {
+      p_solicitud_id: solicitudId,
+      p_cliente_id: clienteId,
+      p_cuenta_id: cuenta.id,
+      p_motivo: motivo,
+      p_respaldo_ruta: ruta,
+    })
+    if (error) {
+      if (esPorContratosAbiertos(error) && sigueEnEsteCliente()) {
+        document.getElementById('btnRetiroIrCambio').classList.remove('hidden')
+      }
+      throw new Error(mensajeErrorRetiro(error))
+    }
+    mostrarExito(textoExitoRetiro(data))
+    hecho = true
+  } catch (error) {
+    const mensaje = error?.message || 'No se pudo retirar la cuenta.'
+    if (!sigueEnEsteCliente()) {
+      mostrarError(mensaje)
+      return
+    }
+    errEl.textContent = mensaje
+    errEl.classList.remove('hidden')
+  } finally {
+    RETIRO_GUARDANDO = false
+    btn.disabled = false
+    btn.textContent = 'Retirar cuenta'
+    document.getElementById('btnCancelarRetiro').disabled = false
+  }
+  if (hecho && sigueEnEsteCliente()) {
+    cerrarRetiro()
+    cargarCuentasModal(clienteId)
+  }
+}
+
+// La cuenta todavía cobra contratos abiertos: se cambia primero su cuenta de pago (F3).
+function irDeRetiroACambio() {
+  cerrarRetiro()
+  abrirCambioPago()
+  document.getElementById('cb_pago_group')?.scrollIntoView({ block: 'nearest' })
+}
+
 /* ---------- Cuenta de pago de los contratos (F3, solo admin/superadmin) ---------- */
 
 // «Cambiar cuenta de pago» solo se habilita con cuentas y contratos ya cargados.
@@ -965,8 +1126,13 @@ function abrirModalCuentas(cliente) {
     mostrarError('Espera a que termine el cambio de cuenta de pago en curso.')
     return
   }
+  if (RETIRO_GUARDANDO) {
+    mostrarError('Espera a que termine el retiro de la cuenta en curso.')
+    return
+  }
   CAMBIO_PAGO = nuevoEstadoCambio(cliente.id, cliente.correo || '')
   cerrarCambioPago()
+  cerrarRetiro()
   document.getElementById('cb_clienteId').value = cliente.id
   document.getElementById('cb_clienteNombre').textContent = cliente.nombre_completo
   document.getElementById('modalCuentasError').classList.add('hidden')
@@ -2236,6 +2402,20 @@ async function recargar() {
   document.getElementById('btnMostrarNuevaCuenta')?.addEventListener('click', () => mostrarFormNuevaCuenta(true))
   document.getElementById('formCuentas')?.addEventListener('submit', guardarCuentaNueva)
   document.getElementById('cb_titular_distinto')?.addEventListener('change', () => toggleBeneficiario('cb'))
+  document.getElementById('btnCancelarRetiro')?.addEventListener('click', cerrarRetiro)
+  document.getElementById('btnConfirmarRetiro')?.addEventListener('click', () => void confirmarRetiro())
+  document.getElementById('btnRetiroIrCambio')?.addEventListener('click', irDeRetiroACambio)
+  // Cualquier dato nuevo = otra operación (el servidor rechaza reutilizar una solicitud con otros datos).
+  document.getElementById('cb_retiro_motivo')?.addEventListener('input', () => { RETIRO.solicitudId = crypto.randomUUID() })
+  document.getElementById('cb_retiro_respaldo')?.addEventListener('change', (e) => {
+    RETIRO.archivoId = crypto.randomUUID()
+    RETIRO.solicitudId = crypto.randomUUID()
+    const falta = validarRespaldo(e.target.files?.[0] || null)
+    const errEl = document.getElementById('cb_retiro_error')
+    const hay = Boolean(e.target.files?.[0])
+    errEl.textContent = hay && falta ? falta : ''
+    errEl.classList.toggle('hidden', !(hay && falta))
+  })
   document.getElementById('btnMostrarCambioPago')?.addEventListener('click', abrirCambioPago)
   document.getElementById('btnCancelarCambioPago')?.addEventListener('click', cerrarCambioPago)
   document.getElementById('btnConfirmarCambioPago')?.addEventListener('click', () => void confirmarCambioPago())
```

## Qué te pido
1. ¿Algún camino deja retirar sin ser admin vigente, retirar una cuenta de otro cliente, o dejar un
   contrato abierto cobrando en una cuenta retirada (carreras con el alta de contrato, F3 o pagos)?
2. ¿La idempotencia y los mensajes (ya retirada, solicitud con otros datos) son correctos? ¿El mensaje
   de «ya estaba retirada» filtra algo que no debería?
3. ¿La lectura de motivos respeta roles y cartera? ¿La ruta del respaldo llega solo al admin vigente?
4. ¿La pantalla puede retirar la cuenta equivocada (botones por posición), dejar estados colgados o
   mostrar éxito falso?
5. ¿Riesgos residuales bien acotados? ¿Falta algún test o mutante crítico?
Termina con VERDICT (PASS/BLOCK).
