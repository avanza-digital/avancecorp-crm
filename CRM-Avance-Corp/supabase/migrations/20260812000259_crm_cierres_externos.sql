-- ============================================================================
-- 20260812000259_crm_cierres_externos — Cierres en cooperativas (Qorilazo/Prodelco)
-- ============================================================================
-- FASE 1 del plan «Cierres en cooperativas Qorilazo y Prodelco» (vault, OK de
-- Miguel 2026-08-11). El problema: los vendedores también cierran inversiones
-- en COOPAC Qorilazo y COOPAC Prodelco; esas personas NO entran al portal ni
-- reciben correo, pero el cierre SÍ debe contarle al vendedor en su cuota
-- mensual y en su % de conversión (base de comisiones).
--
-- La ruta elegida es barata a propósito:
--   · La conversión mensual NO mira contratos ni portal: cuenta episodios del
--     ledger `crm.lead_asignaciones` con resultado='convertido'. Esta RPC
--     cierra el lead EXACTAMENTE igual que la conversión Avance (etapa =
--     'convertido' bajo la válvula `crm.op_privilegiada`; el AFTER
--     `trg_leads_asignaciones` cierra el episodio) → `conversion_mensual_fn`
--     NO SE TOCA y el cierre externo cuenta solo, con su peso (referido 0,15).
--   · Lo único que lo bloqueaba: (a) el invariante P4 «convertido ⇒ perfil_id
--     no nulo» del BEFORE trigger, que aquí se RELAJA a «…o existe cierre
--     externo del lead»; (b) que el único camino a convertido era la edge del
--     portal (Auth + perfiles + Resend), que estos inversionistas no deben
--     pisar (regla «CRM y portal separados»).
--   · La cuota (`crm.cumplimiento_metas_fn`) hoy solo suma `public.contratos`;
--     gana un UNION ALL con los cierres externos, SOLO en los valores: ni una
--     clave nueva ni un token distinto en el payload, porque el front
--     desplegado lo valida con `v.strictObject` y una clave nueva lo rompería
--     (por eso `fuentes_reales.capital_y_contratos` conserva su literal).
--
-- Qué crea:
--   1. Tabla `crm.cierres_externos` (RLS ON, cero policies, cero grants:
--      deny-by-default absoluto, precedente `crm.conversion_pesos`).
--   1-ter. Tabla `crm.depositos_reclamados` — memoria histórica append-only de
--      números de operación: corregir un cierre liberaba el número anterior y
--      permitía cobrar el mismo depósito dos veces.
--   1-bis. Tabla `crm.conversion_reservas` + `crm.reservar_conversion_lead(...)`
--      — la reserva DURABLE que serializa los dos caminos de conversión (ver
--      la nota «la carrera del usuario huérfano» en esa sección).
--   2. `crm.convertir_lead_externo(...)` — mismos gates que `convertir_lead`.
--   3. `private.leads_before_update()` — cuerpo íntegro de producción
--      (anclado por md5 en el preflight) con P4 relajada.
--   4. `crm.corregir_cierre_externo(...)` — solo gerencia; la conversión en sí
--      no se deshace (igual que hoy con Avance).
--   4-bis. `crm.anular_cierre_externo(...)` — el freno de emergencia de gerencia
--      contra un cierre falso o mal digitado: deja de contar en la cuota Y en la
--      conversión, sin borrar la fila ni reabrir el lead.
--   5. `crm.cierres_externos_fn(p_periodo)` — lectura para Mi cartera y el
--      desglose por empresa de supervisor/gerencia.
--   6. `crm.cumplimiento_metas_fn(date)` — cuerpo de producción (anclado por
--      md5) + UNION ALL de externos en la CTE `reales`.
--   6-bis. `private.conversion_mensual_por_vendedor(...)` — cuerpo de producción
--      (anclado por md5) + exclusión de los cierres ANULADOS del numerador.
--
-- NO toca objetos de `public` (el FK a `public.perfiles` referencia, no
-- modifica — mismo idioma que `crm.leads.creado_por` y el ledger).
-- NO escribe ni una fila en `crm.lead_asignaciones` (el postflight lo mide).
-- ============================================================================

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
-- 0.1 Sin sesión: el postflight fabrica un lead en cola global y los guards de
--     tenencia/disponibilidad rechazarían a un actor con sesión (lección de la
--     migración D del origen).
-- 0.2 Anclas md5: este fichero REEMPLAZA los cuerpos de
--     `private.leads_before_update`, `crm.cumplimiento_metas_fn` y
--     `private.conversion_mensual_por_vendedor`, copiados de producción el
--     2026-08-12. Si producción cambió después de esa copia, el REPLACE pisaría
--     en silencio un comportamiento que este fichero no conoce: mejor morir
--     aquí con un mensaje que lo nombra.
do $preflight$
begin
  if (select auth.uid()) is not null then
    raise exception 'Esta migracion se aplica sin sesion (auth.uid() debe ser NULL): el postflight fabrica un lead en cola global y los guards lo rechazarian';
  end if;

  if md5(pg_get_functiondef('private.leads_before_update()'::regprocedure))
     <> 'c287f7f3cd31e10f4df8678486b7a574' then
    raise exception 'private.leads_before_update en esta base NO es el cuerpo que este fichero copio de produccion (2026-08-12). Regenerar la seccion 3 desde pg_get_functiondef antes de aplicar.';
  end if;

  if md5(pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure))
     <> 'b66732fe4b0d86852c739de099d1a35c' then
    raise exception 'crm.cumplimiento_metas_fn en esta base NO es el cuerpo que este fichero copio de produccion (2026-08-12). Regenerar la seccion 6 desde pg_get_functiondef antes de aplicar.';
  end if;

  if md5(pg_get_functiondef('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'::regprocedure))
     <> '8aa9663cc6817c3c22cb1127511dd26d' then
    raise exception 'private.conversion_mensual_por_vendedor en esta base NO es el cuerpo que este fichero copio de produccion (2026-08-12). Regenerar la seccion 6-bis desde pg_get_functiondef antes de aplicar.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La tabla: crm.cierres_externos
-- ---------------------------------------------------------------------------
-- Un cierre por lead (UNIQUE): casa con el índice «una conversión por lead»
-- del ledger. `vendedor_id` es FOTO de quién cobró el cierre — editar el lead
-- o reasignar después no mueve una comisión ya devengada. Identidad
-- (documento/nombre) también es foto: es lo que la cooperativa registró en SU
-- contrato, no un espejo del lead (el lead ni siquiera admite CE/Pasaporte).
create table crm.cierres_externos (
  id                 uuid primary key default gen_random_uuid(),
  lead_id            uuid not null references crm.leads(id) on delete restrict,
  cooperativa        text not null
    check (cooperativa in ('qorilazo', 'prodelco')),
  -- ⚠️ `monto <> 'NaN'` NO es redundante con `> 0`. Postgres admite el numeric
  -- NaN y lo considera MAYOR que cualquier número, así que `NaN > 0` es TRUE y
  -- el CHECK lo dejaba pasar. Un vendedor autenticado podía mandar
  -- `{"p_monto": "NaN"}` por la Data API y envenenar `sum(monto)` —la cuota del
  -- mes de todo el equipo pasaba a ser NaN—. Comprobado en PG17.
  monto              numeric(14,2) not null
    check (monto <> 'NaN'::numeric and monto > 0),
  -- SOLO SOLES (decisión de Miguel 2026-08-12: en cooperativas no se invierte en
  -- dólares). La columna se queda —todo lo de abajo agrupa por moneda y la meta
  -- operativa vive normalizada en `nuevo/PEN`— pero el único valor legal es PEN,
  -- y lo dice la BD, no solo la pantalla.
  moneda             text not null check (moneda = 'PEN'),
  documento_tipo     text not null
    check (documento_tipo in ('DNI', 'CE', 'PASAPORTE')),
  documento          text not null,
  nombre_completo    text not null check (btrim(nombre_completo) <> ''),
  -- LA PRUEBA del cierre: obligatoria y única por cooperativa (ver el índice más
  -- abajo). Un número de certificado se inventa; un número de operación apunta a
  -- plata que se movió y que un tercero también registró.
  numero_transaccion text not null
    check (btrim(numero_transaccion) <> '' and length(btrim(numero_transaccion)) <= 64),
  -- El certificado de la cooperativa: opcional, para papeleo. NO es la prueba.
  referencia_externa text check (referencia_externa is null
    or (btrim(referencia_externa) <> '' and length(btrim(referencia_externa)) <= 64)),
  vence_en           date,
  nota               text,
  vendedor_id        uuid not null references crm.equipo(perfil_id) on delete restrict,
  creado_por         uuid not null references public.perfiles(id) on delete restrict,
  creado_en          timestamptz not null default now(),
  -- Anulación (freno de emergencia de gerencia): la fila NO se borra —el lead
  -- quedó convertido y borrarla lo dejaría ilegal (P4)—, deja de contar.
  anulado_en         timestamptz,
  anulado_por        uuid references public.perfiles(id) on delete restrict,
  motivo_anulacion   text,

  constraint cierres_externos_un_cierre_por_lead unique (lead_id),
  -- Los tres campos de la anulación viajan juntos o no viajan: una fila con
  -- fecha y sin autor (o sin motivo) sería un cierre que dejó de pagar sin que
  -- nadie responda por ello.
  -- ⚠️ `motivo_anulacion is not null` explícito y NO solo `btrim(...) <> ''`:
  -- un CHECK únicamente rechaza cuando da FALSE, y con el motivo en NULL el
  -- `btrim(null) <> ''` da NULL — la rama entera daba NULL y el candado dejaba
  -- pasar la fila. Comprobado en vivo: sin esta línea, un cierre anulado sin
  -- motivo entra. Misma trampa que ya costó cara en el ledger.
  constraint cierres_externos_anulacion_completa check (
    (anulado_en is null and anulado_por is null and motivo_anulacion is null)
    or (anulado_en is not null and anulado_por is not null
        and motivo_anulacion is not null
        and btrim(motivo_anulacion) <> ''
        and length(btrim(motivo_anulacion)) <= 300)
  ),
  -- Espejo EXACTO de src/lib/documento.ts (la fuente canónica del portal):
  -- DNI 8 dígitos · CE 9-12 dígitos · Pasaporte 6-12 letras/números en
  -- mayúsculas (la RPC normaliza con upper(btrim(...)) antes de insertar).
  constraint cierres_externos_documento_formato check (
    case documento_tipo
      when 'DNI' then documento ~ '^[0-9]{8}$'
      when 'CE'  then documento ~ '^[0-9]{9,12}$'
      else            documento ~ '^[A-Z0-9]{6,12}$'
    end
  )
);

comment on table crm.cierres_externos is
  'Cierres de inversion en cooperativas (COOPAC Qorilazo / COOPAC Prodelco). El inversionista NO existe en el portal (sin perfil, sin correo): vive como lead convertido + esta fila. RLS ON, cero policies y cero grants (deny-by-default absoluto); se escribe SOLO via crm.convertir_lead_externo / crm.corregir_cierre_externo y se lee SOLO via crm.cierres_externos_fn.';
comment on column crm.cierres_externos.lead_id is
  'Lead convertido que respalda este cierre. UNIQUE: un cierre externo por lead, en linea con el indice «una conversion por lead» del ledger.';
comment on column crm.cierres_externos.cooperativa is
  'Donde invirtio: qorilazo | prodelco. Es el distintivo que ve el vendedor en Mi cartera.';
comment on column crm.cierres_externos.monto is
  'Monto REAL invertido (no el estimado del lead). Es lo que suma a la cuota del mes via cumplimiento_metas_fn.';
comment on column crm.cierres_externos.moneda is
  'Siempre PEN: en cooperativas solo se invierte en soles (Miguel, 2026-08-12). La columna se conserva porque la lectura y la cuota agrupan por moneda, y porque la meta operativa vive normalizada en nuevo/PEN.';
comment on column crm.cierres_externos.numero_transaccion is
  'Numero de operacion del deposito del inversionista. OBLIGATORIO y UNICO EN TODA LA TABLA (no por cooperativa: la cooperativa la elige el mismo vendedor, asi que no sirve de namespace): es la unica prueba de que se movio plata de verdad, y lo que impide cobrar dos veces un mismo cierre. Solo gerencia lo corrige.';
comment on column crm.cierres_externos.documento_tipo is
  'DNI | CE | PASAPORTE — mismas reglas que public.perfiles.tipo_documento.';
comment on column crm.cierres_externos.documento is
  'Numero de documento, FOTO de lo que la cooperativa registro. No es espejo del lead: crm.leads.dni solo admite DNI de 8 digitos.';
comment on column crm.cierres_externos.nombre_completo is
  'Nombre al momento del cierre (foto, editable solo hasta confirmar).';
comment on column crm.cierres_externos.referencia_externa is
  'Numero/codigo del contrato o certificado que emitio la cooperativa. OPCIONAL, para papeleo: la prueba del cierre es numero_transaccion, no esto (un codigo de certificado no lo contrasta nadie).';
comment on column crm.cierres_externos.vence_en is
  'Vencimiento de la inversion en la coop. Opcional; insumo del futuro recordatorio de renovacion.';
comment on column crm.cierres_externos.vendedor_id is
  'FOTO de quien cobro el cierre (el vendedor asignado del lead al convertir). Reasignaciones posteriores no mueven la comision.';
comment on column crm.cierres_externos.creado_en is
  'Fecha del cierre. Automatica (now()), sin retro-datar: el mes de la cuota y de la conversion es el mes real del cierre.';
comment on column crm.cierres_externos.anulado_en is
  'Anulado por gerencia (fraude o error). Un cierre anulado NO cuenta ni en la cuota (cumplimiento_metas_fn) ni en la conversion mensual (private.conversion_mensual_por_vendedor), pero la fila SIGUE existiendo: el lead quedo convertido y esta fila es su ancla de legalidad (P4). Es de una sola direccion: no se des-anula.';
comment on column crm.cierres_externos.motivo_anulacion is
  'Por que se anulo, en palabras de gerencia. Obligatorio: un cierre deja de pagarle a una persona y esa persona merece una razon.';

alter table crm.cierres_externos enable row level security;

-- RLS ON con CERO policies y CERO grants: deny-by-default absoluto para la
-- Data API (precedente aceptado: crm.conversion_pesos, crm.lead_asignaciones,
-- crm.cuentas_bancarias). Dispara el advisor INFO `rls_enabled_no_policy`, de
-- la clase ya aceptada en la casa.
revoke all privileges on table crm.cierres_externos
  from public, anon, authenticated, service_role;

-- Índices de lectura: la lista de Mi cartera pide por vendedor (más reciente
-- primero) y la cuota/desglose piden por ventana de mes. El de creado_por
-- cubre su FK (advisor unindexed_foreign_keys; mismo criterio que 20260801092924).
create index idx_cierres_externos_vendedor_creado
  on crm.cierres_externos (vendedor_id, creado_en desc);
create index idx_cierres_externos_creado_en
  on crm.cierres_externos (creado_en);
create index idx_cierres_externos_creado_por
  on crm.cierres_externos (creado_por);
-- Igual que creado_por: cubre su FK (advisor unindexed_foreign_keys).
create index idx_cierres_externos_anulado_por
  on crm.cierres_externos (anulado_por);

-- UN depósito, UN cierre. El UNIQUE(lead_id) solo impedía dos cierres del MISMO
-- lead; nada impedía fabricar un lead nuevo (el índice de teléfono no vigila a
-- los convertidos) y volver a declarar el mismo depósito, con lo que un solo
-- cierre real pagaba cuota y conversión dos veces.
-- La clave se normaliza a mayúsculas sin espacios: «OP-123», «op-123 » y
-- «Op-123» son la misma operación.
--
-- ⚠️ GLOBAL, no por cooperativa. La primera versión lo hizo por cooperativa
-- para no castigar códigos de operación que chocan entre bancos, y eso dejaba
-- abierto el fraude entero: la cooperativa la ELIGE el mismo vendedor cuya
-- declaración se está deduplicando, así que bastaba declarar el mismo voucher
-- una vez en Qorilazo y otra en Prodelco para cobrarlo dos veces. Un namespace
-- que controla el sospechoso no es un namespace.
-- El precio es una colisión legítima ocasional; para eso gerencia corrige o
-- anula. Cobrar dos veces no tiene ese remedio.
create unique index ux_cierres_externos_transaccion
  on crm.cierres_externos (upper(btrim(numero_transaccion)));

-- MEMORIA HISTÓRICA DE DEPÓSITOS RECLAMADOS.
--
-- El índice único de `cierres_externos` vigila los números VIVOS. Pero gerencia
-- puede corregir el número de un cierre (el vendedor lo tipeó mal), y al
-- corregir de A a B el número A DESAPARECE del índice y vuelve a estar libre:
-- otro lead lo declara y el mismo depósito se cobra dos veces. El rastro queda
-- en la auditoría, pero la auditoría no la consulta nadie al insertar.
--
-- Esta tabla nunca olvida: cada número reclamado entra una vez y no sale jamás,
-- ni al corregir ni al anular. Es append-only de verdad —sin UPDATE ni DELETE,
-- ni siquiera bajo la válvula— porque su único valor es que no se pueda borrar.
create table crm.depositos_reclamados (
  id            uuid primary key default gen_random_uuid(),
  /** Normalizado igual que el índice de cierres: mayúsculas sin espacios. */
  numero_norm   text not null unique,
  /** Dónde se reclamó por primera vez. Informativo: la clave es el número. */
  cierre_id     uuid not null references crm.cierres_externos(id) on delete restrict,
  reclamado_por uuid not null references public.perfiles(id) on delete restrict,
  reclamado_en  timestamptz not null default now()
);

comment on table crm.depositos_reclamados is
  'Memoria historica de numeros de operacion ya declarados. Append-only absoluto: corregir el numero de un cierre liberaba el anterior del indice vivo y permitia cobrarlo otra vez en otro lead. Aqui no se libera nunca.';

alter table crm.depositos_reclamados enable row level security;
revoke all privileges on table crm.depositos_reclamados
  from public, anon, authenticated, service_role;

create index idx_depositos_reclamados_cierre on crm.depositos_reclamados (cierre_id);
create index idx_depositos_reclamados_por on crm.depositos_reclamados (reclamado_por);

create trigger trg_audit_depositos_reclamados
after insert or delete or update on crm.depositos_reclamados
for each row execute function private.log_audit_crm();

create or replace function private.trg_depositos_reclamados_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception using
    errcode = 'P0409',
    message = 'Un numero de operacion reclamado no se edita ni se borra',
    hint    = 'Esta tabla existe para no olvidar: si se pudiera limpiar, el mismo deposito se podria cobrar dos veces.';
end;
$function$;

create trigger trg_depositos_reclamados_00_append_only
before update or delete on crm.depositos_reclamados
for each row execute function private.trg_depositos_reclamados_append_only();

-- «¿Este lead tiene un cierre en cooperativa ANULADO?» — UNA sola definición.
--
-- La usan los DOS numeradores de conversión que existen en la casa:
-- `private.conversion_mensual_por_vendedor` (la definición oficial) y la CTE
-- `conversiones` de `crm.cumplimiento_metas_fn` (la que pintan el resumen de
-- gerencia, inteligencia comercial y las alertas). Escrita dos veces a mano,
-- las dos acabarían divergiendo — que es exactamente lo que pasó en la primera
-- versión de esta migración: una descontaba el cierre anulado y la otra no, y
-- el mismo vendedor salía con 0 % en una pantalla y 100 % en la de al lado.
--
-- INVOKER a propósito (no DEFINER): las dos que la llaman ya son DEFINER y
-- corren como el dueño, así que ven la tabla; llamada por su cuenta desde la
-- Data API muere en el permiso de la tabla, que es lo correcto.
create or replace function private.cierre_externo_anulado(p_lead_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id
      and ce.anulado_en is not null
  )
$$;

comment on function private.cierre_externo_anulado(uuid) is
  'TRUE si el lead tiene un cierre en cooperativa anulado por gerencia. Definicion UNICA de «anulado» para los dos numeradores de conversion (private.conversion_mensual_por_vendedor y la CTE conversiones de crm.cumplimiento_metas_fn): escrita dos veces, divergen.';

revoke all on function private.cierre_externo_anulado(uuid)
  from public, anon, authenticated, service_role;

-- Auditoría: LEEME.md exige trigger de audit sobre TODA tabla crm.*, y esta
-- tabla es dinero de comisiones. Tiene `id`, así que fila_id resuelve.
create trigger trg_audit_cierres_externos
after insert or delete or update on crm.cierres_externos
for each row execute function private.log_audit_crm();

-- Inmutabilidad: nadie edita ni borra un cierre por fuera de la RPC de
-- corrección (que enciende la válvula). Y aun con la válvula, la IDENTIDAD del
-- cierre (lead, vendedor que cobró, documento, nombre, autoría, fecha) no se
-- reescribe jamás: la corrección de gerencia alcanza monto/moneda/cooperativa/
-- referencia/vencimiento/nota y nada más. SECURITY DEFINER como todo trigger
-- de guardia de la casa (leads_before_update); search_path vacío.
create or replace function private.trg_cierres_externos_inmutables()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo no se elimina: gerencia lo corrige via crm.corregir_cierre_externo',
      hint    = 'El cierre respalda una conversion ya contada; borrar la fila dejaria un convertido sin perfil ni cierre (invariante P4).';
  end if;

  if not v_priv then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo solo se corrige via crm.corregir_cierre_externo',
      detail  = pg_catalog.format('cierre %s (lead %s)', old.id, old.lead_id);
  end if;

  -- Con la válvula encendida, las columnas de identidad se restauran en
  -- silencio (no con excepción): la RPC de corrección no las manda, así que
  -- esto es un cinturón contra bugs futuros de rutas DEFINER, no una rama que
  -- un usuario pueda pisar.
  new.id := old.id;
  new.lead_id := old.lead_id;
  new.vendedor_id := old.vendedor_id;
  new.documento_tipo := old.documento_tipo;
  new.documento := old.documento;
  new.nombre_completo := old.nombre_completo;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;

  -- La anulación es de UNA SOLA DIRECCIÓN. Des-anular sería volver a pagar un
  -- cierre que ya se declaró falso, y eso no se hace en silencio desde una ruta
  -- DEFINER: aquí se restaura y punto. (Aquí SÍ con excepción y no en silencio:
  -- si una RPC futura intentara resucitar un cierre anulado, el error tiene que
  -- salir a la superficie, no perderse en un 200 mudo.)
  if old.anulado_en is not null
     and (new.anulado_en is null
          or new.anulado_por is distinct from old.anulado_por
          or new.anulado_en is distinct from old.anulado_en) then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo anulado no se restablece',
      detail  = pg_catalog.format('cierre %s (lead %s), anulado el %s',
                                  old.id, old.lead_id, old.anulado_en);
  end if;
  return new;
end;
$function$;

create trigger trg_cierres_externos_00_inmutables
before update or delete on crm.cierres_externos
for each row execute function private.trg_cierres_externos_inmutables();

-- ---------------------------------------------------------------------------
-- 1-bis. La reserva durable: crm.conversion_reservas
-- ---------------------------------------------------------------------------
-- LA CARRERA DEL USUARIO HUÉRFANO. La conversión Avance no es una transacción:
-- la edge `crm-convertir-lead` lee el lead (sin lock), crea el usuario de Auth,
-- inserta el perfil y MANDA EL CORREO DE BIENVENIDA, y solo al final llama a
-- `crm.convertir_lead`, que es la única que toma el `FOR UPDATE`. Si en esa
-- ventana —segundos, con Resend de por medio— se confirma un cierre en
-- cooperativa sobre el mismo lead, `convertir_lead` muere con «El lead ya está
-- cerrado» pero el inversionista de la coop YA tiene cuenta de portal,
-- contraseña y correo enviado. Eso viola la condición central del diseño
-- («cierre en cooperativa ⇒ NUNCA portal») y no hay forma de retirar un correo.
--
-- El `FOR UPDATE` no puede arreglarlo: un lock de fila no sobrevive entre las
-- llamadas HTTP de la edge. Hace falta una reserva DURABLE que ambos caminos
-- respeten y que la edge tome ANTES de su primer efecto secundario.
--
-- DOS ESTADOS, y la diferencia es la que salva el correo:
--
--   · RESERVADA (solo `expira_en`): la edge dijo «voy a convertir» pero aún no
--     ha hecho NADA irreversible. Caduca sola a los pocos minutos, porque si la
--     edge muere aquí no ha pasado nada y una reserva eterna dejaría el lead
--     incerrable para siempre.
--
--   · CON EFECTOS INICIADOS (`efectos_iniciados_en` no nulo): la edge ya creó
--     —o está creando— el usuario de Auth y el perfil. Esta reserva **NO
--     CADUCA**. Si caducara, una edge muerta a mitad devolvería el lead al
--     cierre en cooperativa a los cinco minutos y tendríamos exactamente lo que
--     esta tabla vino a impedir: un inversionista de cooperativa con cuenta de
--     portal. Es el defecto que la primera versión de esta reserva NO cerraba y
--     que la segunda revisión de Codex encontró.
--
-- Consecuencia asumida a propósito: un lead cuya conversión Avance murió a
-- medias queda BLOQUEADO para cerrarse en cooperativa hasta que alguien termine
-- esa conversión. Es lo correcto: ya existe una cuenta de portal a su nombre, y
-- el camino honesto es completar Avance (el dedup de la edge reengancha el
-- perfil existente), no fingir que nunca pasó.
--
-- Una fila por lead como máximo (upsert sobre `lead_id`, que es UNIQUE): la que
-- queda tras una conversión consumada es el rastro de quién la inició.
-- `id` propio y `lead_id` UNIQUE (en vez de `lead_id` como PK): el trigger de
-- auditoría de la casa resuelve `fila_id` con `coalesce(id, perfil_id)`, así que
-- sin columna `id` cada reserva quedaría en `public.audit_log` sin fila
-- identificable. El UNIQUE sigue sirviendo igual al `on conflict (lead_id)`.
create table crm.conversion_reservas (
  id            uuid primary key default gen_random_uuid(),
  lead_id       uuid not null unique references crm.leads(id) on delete restrict,
  reservado_por uuid not null references public.perfiles(id) on delete restrict,
  reservado_en  timestamptz not null default now(),
  expira_en     timestamptz not null,
  /** Sellado por la edge JUSTO ANTES de crear el usuario de Auth. Desde ese
   *  instante la reserva deja de caducar (ver la nota de arriba). */
  efectos_iniciados_en timestamptz,
  /** Tope ABSOLUTO desde el alta, no renovable. Sin él, quien reserva puede
   *  renovarse a sí mismo cada cuatro minutos y tener un lead secuestrado sin
   *  límite, bloqueando el cierre en cooperativa de su propio equipo. */
  vence_absoluto_en timestamptz not null
);

comment on table crm.conversion_reservas is
  'Reserva DURABLE de la conversion de un lead. La toma la edge crm-convertir-lead ANTES de crear Auth/perfil/correo; crm.convertir_lead_externo rechaza mientras siga viva. Existe porque la conversion Avance no es transaccional y sin esto una carrera dejaba un inversionista de cooperativa con cuenta de portal. RLS ON, cero policies, cero grants.';
comment on column crm.conversion_reservas.expira_en is
  'La reserva caduca sola (la edge puede morir a medias). Mientras no caduque, el cierre en cooperativa se rechaza indicando cuando reintentar.';

alter table crm.conversion_reservas enable row level security;

revoke all privileges on table crm.conversion_reservas
  from public, anon, authenticated, service_role;

create index idx_conversion_reservas_reservado_por
  on crm.conversion_reservas (reservado_por);

create trigger trg_audit_conversion_reservas
after insert or delete or update on crm.conversion_reservas
for each row execute function private.log_audit_crm();

-- crm.reservar_conversion_lead — mismos gates de rol y ámbito que las dos
-- conversiones, para que reservar no sea una puerta más ancha que cerrar.
-- Idempotente para el MISMO actor (un reintento del analista renueva su propia
-- reserva); un actor distinto choca mientras la reserva siga viva.
create or replace function crm.reservar_conversion_lead(p_lead_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_lead     crm.leads%rowtype;
  v_expira   timestamptz;
  v_ahora    timestamptz := now();
  v_ventana  interval := interval '5 minutes';
  -- Tope absoluto: más allá de esto, ni el propio dueño renueva. Holgado para
  -- cualquier conversión real (que tarda segundos) y corto para un secuestro.
  v_tope     interval := interval '30 minutes';
begin
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- El FOR UPDATE serializa contra el cierre externo DENTRO de esta
  -- transacción: si el externo va ganando, aquí se espera y luego se ve el lead
  -- ya convertido → la edge se entera ANTES de crear nada.
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;

  -- Alias explícito `r`: en el WHERE del DO UPDATE hay que nombrar la fila que
  -- YA existe, y `crm.conversion_reservas.expira_en` ahí se lee peor de lo que
  -- se ejecuta. Si el WHERE no se cumple no se actualiza nada y el RETURNING no
  -- devuelve fila: eso es la señal de «hay una conversión en vuelo».
  --
  -- Se puede tomar/renovar SOLO si la anterior está caducada, o si es del mismo
  -- actor Y no ha pasado su tope absoluto. Las dos condiciones exigen además
  -- que NADIE haya iniciado efectos: una vez creada la cuenta de Auth, esa
  -- reserva es definitiva y ni su propio dueño la reinicia.
  -- Quién puede tomar o retomar la reserva:
  --   · nadie, si hay efectos iniciados y la reserva es DE OTRO (esa conversión
  --     ya creó una cuenta: solo su dueño puede terminarla);
  --   · SU DUEÑO, siempre que no se haya pasado el tope absoluto — incluso con
  --     efectos ya iniciados. Esto es lo que hace posible el REINTENTO: si la
  --     conversión Avance falla en el último paso, la pantalla dice «reintenta»
  --     y ese reintento tiene que poder entrar. Sin esta rama, un fallo de red
  --     en la última llamada dejaba el lead trabado PARA SIEMPRE.
  --   · cualquiera, si la reserva caducó y nunca hubo efectos.
  -- `efectos_iniciados_en` NO se limpia al retomar: el cierre en cooperativa
  -- sigue vetado, que es la garantía que importa.
  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         -- El tope absoluto MANDA sobre la ventana: sin este `least`, renovar a
         -- los 29 minutos daba 5 más y el tope no era un tope.
         expira_en     = least(excluded.expira_en,
                               case when r.reservado_por = v_uid
                                    then r.vence_absoluto_en
                                    else excluded.vence_absoluto_en end),
         vence_absoluto_en = case
           -- Retomar la propia reserva NO reinicia el tope.
           when r.reservado_por = v_uid then r.vence_absoluto_en
           else excluded.vence_absoluto_en
         end
   where (r.reservado_por = v_uid and r.vence_absoluto_en > v_ahora)
      or (r.efectos_iniciados_en is null and r.expira_en <= v_ahora)
  returning r.expira_en into v_expira;

  if v_expira is null then
    -- Distinguir los motivos importa: uno se resuelve esperando y el otro no.
    if exists (select 1 from crm.conversion_reservas r2
               where r2.lead_id = p_lead_id and r2.efectos_iniciados_en is not null) then
      raise exception using
        errcode = 'P0409',
        message = 'Este lead ya tiene una conversion a cliente de Avance empezada por otra persona',
        hint    = 'Ya existe una cuenta de portal a su nombre: quien la empezo tiene que terminarla.';
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Otra persona esta convirtiendo este lead en este momento',
      hint    = 'Espera unos minutos y vuelve a intentarlo.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira);
end;
$$;

-- crm.marcar_efectos_conversion — el punto de no retorno.
--
-- La edge la llama JUSTO ANTES de crear el usuario de Auth. A partir de aquí la
-- reserva deja de caducar, porque a partir de aquí existe —o va a existir en
-- milisegundos— una cuenta de portal a nombre de esta persona, y dejar que el
-- cierre en cooperativa entre después sería crear el huérfano que toda esta
-- tabla existe para impedir.
--
-- Exige reserva VIVA y DEL MISMO ACTOR: sellar la reserva de otro sería regalar
-- un bloqueo permanente sobre un lead ajeno.
create or replace function crm.marcar_efectos_conversion(p_lead_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_ok  boolean;
begin
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- El tope absoluto también manda AQUÍ: si ya pasó, esta reserva no vale para
  -- sellar nada, y la edge muere antes de crear la cuenta.
  update crm.conversion_reservas r
     set efectos_iniciados_en = coalesce(r.efectos_iniciados_en, now())
   where r.lead_id = p_lead_id
     and r.reservado_por = v_uid
     and r.vence_absoluto_en > now()
     and (r.expira_en > now() or r.efectos_iniciados_en is not null)
  returning true into v_ok;

  if not coalesce(v_ok, false) then
    raise exception using
      errcode = 'P0409',
      message = 'La reserva de esta conversion ya no esta viva',
      hint    = 'Vuelve a empezar la conversion desde la ficha del lead.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id);
end;
$$;

comment on function crm.marcar_efectos_conversion(uuid) is
  'Sella la reserva de conversion como «ya hay efectos irreversibles» (usuario de Auth y perfil). Desde ese momento la reserva NO caduca y crm.convertir_lead_externo rechaza para siempre: si caducara, una edge muerta a medias devolveria el lead al cierre en cooperativa y quedaria un inversionista de coop con cuenta de portal. Exige reserva viva del MISMO actor.';

revoke all on function crm.marcar_efectos_conversion(uuid)
  from public, anon, service_role;
grant execute on function crm.marcar_efectos_conversion(uuid) to authenticated;

comment on function crm.reservar_conversion_lead(uuid) is
  'Reserva la conversion de un lead por unos minutos. La edge crm-convertir-lead la toma ANTES de crear el usuario de Auth, el perfil y el correo; crm.convertir_lead_externo rechaza mientras siga viva. Caduca sola para que una edge caida no deje el lead incerrable.';

revoke all on function crm.reservar_conversion_lead(uuid)
  from public, anon, service_role;
grant execute on function crm.reservar_conversion_lead(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. crm.convertir_lead_externo — el cierre en cooperativa
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER con la MISMA justificación que crm.convertir_lead: escribe
-- en una tabla sin grants y mueve el lead a una etapa que el BEFORE trigger
-- prohíbe sin válvula. Gates idénticos (rol, ámbito, lead activo/no cerrado/
-- con analista) para que «convertir» signifique lo mismo se cierre donde se
-- cierre. NO valida el documento contra crm.leads.dni a propósito: el dato del
-- lead es lo que se tipeó al alta; el del cierre es lo que la cooperativa
-- registró en su contrato, y ÉSE es el que queda de foto.
create or replace function crm.convertir_lead_externo(
  p_lead_id uuid,
  p_cooperativa text,
  p_monto numeric,
  p_moneda text,
  p_documento_tipo text,
  p_documento text,
  p_nombre text,
  p_numero_transaccion text,
  p_referencia text default null,
  p_vence_en date default null,
  p_nota text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_lead        crm.leads%rowtype;
  v_documento   text := upper(btrim(p_documento));
  v_nombre      text := btrim(p_nombre);
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
  v_reserva     timestamptz;
  v_efectos     timestamptz;
  v_cierre_id   uuid;
begin
  -- ALLOWLIST con coalesce, NO el `not in` de convertir_lead: con rol_crm NULL
  -- (un cliente del portal, un directorio puro) `v_rol not in (...)` da NULL y
  -- el gate no dispara — el actor moriría después en el ámbito, denegado pero
  -- con el error equivocado (P0001 en vez de 42501). Es la misma trampa que
  -- conversion_mensual_fn documenta; el gate RLS la cazó aquí en vivo.
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- Validaciones de entrada ANTES de tocar el lead: un payload inválido no
  -- debe dejar ni un lock tomado.
  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    -- numeric(14,2) redondearía en silencio; con dinero, mejor rechazar.
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  -- En cooperativas solo se invierte en soles. Se valida en vez de forzar: un
  -- bundle viejo que mande USD merece un rechazo claro, no que le cambiemos la
  -- moneda por debajo y le contemos el monto como si fueran soles.
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if p_documento_tipo is null
     or p_documento_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido: DNI, CE o PASAPORTE'
      using errcode = '22023';
  end if;
  -- Mismas reglas que src/lib/documento.ts y el CHECK de la tabla; el error
  -- aquí habla el idioma del formulario, no el del constraint.
  if (p_documento_tipo = 'DNI'       and v_documento !~ '^[0-9]{8}$')
     or (p_documento_tipo = 'CE'        and v_documento !~ '^[0-9]{9,12}$')
     or (p_documento_tipo = 'PASAPORTE' and v_documento !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo %', p_documento_tipo
      using errcode = '22023';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'El nombre completo es obligatorio'
      using errcode = '22023';
  end if;
  -- El número de operación es OBLIGATORIO (y único por cooperativa, ver el
  -- índice): es lo único que impide cobrar dos veces un mismo cierre real.
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  -- La fecha del cierre es HOY (automática): el vencimiento de una inversión
  -- recién cerrada solo puede ser futuro. En corregir_cierre_externo este
  -- check NO existe a propósito: una corrección tardía de otro campo debe
  -- poder reenviar un vencimiento que ya pasó.
  if p_vence_en is not null and p_vence_en <= (now() at time zone 'America/Lima')::date then
    raise exception 'El vencimiento de la inversion debe ser una fecha futura'
      using errcode = '22023';
  end if;

  -- Ámbito y lock: copiados VERBATIM de crm.convertir_lead para que los dos
  -- caminos de conversión signifiquen lo mismo.
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- LA CARRERA (ver sección 1-bis): si hay una conversión Avance en vuelo, sus
  -- efectos irreversibles —usuario de Auth, perfil, correo de bienvenida— ya
  -- pueden haber ocurrido, y cerrar aquí dejaría a un inversionista de
  -- cooperativa con cuenta de portal. Se rechaza SIN MIRAR QUIÉN reservó: lo que
  -- importa no es el actor, es que el correo quizá ya salió.
  -- Dos casos, y solo uno se cura esperando.
  --
  -- ⚠️ `for update` y NO una lectura suelta. En READ COMMITTED un SELECT normal
  -- ve la última versión CONFIRMADA: si la edge está sellando la reserva en ese
  -- mismo instante (su UPDATE aún sin confirmar), este cierre vería la versión
  -- vieja —caducada y sin efectos—, entraría, y acto seguido la edge crearía la
  -- cuenta de portal. Ventana de milisegundos, pero es EXACTAMENTE el fallo que
  -- toda esta tabla existe para impedir. Con el lock, este cierre espera al
  -- sellado y decide DESPUÉS, sobre el estado real.
  --
  -- El orden de bloqueo es el mismo en los dos caminos —primero `crm.leads`
  -- (arriba), luego `crm.conversion_reservas`— para que no puedan abrazarse.
  -- Sin `and (expira_en > now() …)` en el WHERE: primero se toma la fila, y la
  -- vigencia se juzga con lo que haya tras esperar.
  select r.expira_en, r.efectos_iniciados_en into v_reserva, v_efectos
  from crm.conversion_reservas r
  where r.lead_id = p_lead_id
  for update;
  if v_efectos is null and coalesce(v_reserva, '-infinity'::timestamptz) <= now() then
    -- Caducada y sin efectos: no manda.
    v_reserva := null;
  end if;
  if v_efectos is not null then
    -- Ya existe una cuenta de portal a nombre de esta persona. Este cierre NO
    -- puede entrar nunca: sería justo el inversionista de cooperativa con
    -- portal que toda esta función existe para impedir.
    raise exception using
      errcode = 'P0409',
      message = 'Esta persona ya tiene una cuenta de cliente de Avance en proceso',
      hint    = 'Se le creo (o se le esta creando) su acceso al portal. Termina esa conversion; este lead ya no se puede cerrar en una cooperativa.';
  end if;
  if v_reserva is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Hay una conversion a cliente de Avance en curso para este lead',
      hint    = pg_catalog.format(
        'Vuelve a intentarlo despues de las %s (hora de Lima). Si esa conversion no debia hacerse, avisa antes de cerrar en la cooperativa.',
        pg_catalog.to_char(v_reserva at time zone 'America/Lima', 'HH24:MI'));
  end if;

  -- La FOTO primero: así, cuando el UPDATE de etapa dispare el BEFORE trigger,
  -- la P4 relajada ya encuentra el cierre y deja pasar el convertido sin
  -- perfil. El UNIQUE(lead_id) es el cinturón contra un doble cierre que el
  -- gate de etapa no haya visto (el FOR UPDATE ya serializa el camino normal).
  begin
    insert into crm.cierres_externos (
      lead_id, cooperativa, monto, moneda,
      documento_tipo, documento, nombre_completo,
      numero_transaccion, referencia_externa, vence_en, nota,
      vendedor_id, creado_por
    ) values (
      p_lead_id, p_cooperativa, p_monto, p_moneda,
      p_documento_tipo, v_documento, v_nombre,
      v_transaccion, v_referencia, p_vence_en, nullif(btrim(p_nota), ''),
      v_lead.vendedor_id, v_uid
    )
    returning id into v_cierre_id;

    -- La reclamación es PARTE del mismo insert: si el número ya se declaró
    -- alguna vez —aunque su cierre se haya corregido después y el índice vivo
    -- lo haya soltado— este insert choca y el cierre entero se deshace.
    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
    values (upper(v_transaccion), v_cierre_id, v_uid);
  exception when unique_violation then
    -- El índice habla en idioma de constraint; el vendedor merece saber QUÉ
    -- pasó. El UNIQUE del lead ya lo cazó el gate de etapa más arriba, así que
    -- aquí el choque es el del depósito (vivo o histórico).
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes, aqui o en la otra cooperativa. Si lo escribiste mal, corrigelo; si es otro cierre, usa su propio numero de operacion.';
  end;

  -- El cierre del lead, IDÉNTICO al de convertir_lead salvo que perfil_id
  -- queda NULL (no hay portal). El AFTER trg_leads_asignaciones cierra el
  -- episodio con resultado='convertido' — por eso la conversión mensual cuenta
  -- este cierre sin tocar su fórmula.
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         convertido_en = now()
   where id = p_lead_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido en ' || case p_cooperativa
      when 'qorilazo' then 'COOPAC Qorilazo'
      else 'COOPAC Prodelco'
    end,
    jsonb_build_object(
      'cooperativa', p_cooperativa,
      'monto', p_monto,
      'moneda', p_moneda,
      'cierre_externo_id', v_cierre_id
    ),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'cierre_id', v_cierre_id,
    'cooperativa', p_cooperativa
  );
end;
$$;

comment on function crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text) is
  'Cierra un lead como convertido en una cooperativa (Qorilazo/Prodelco): inserta la foto en crm.cierres_externos y mueve etapa bajo la valvula, SIN crear usuario de portal ni enviar correo. El episodio del ledger se cierra igual que en la conversion Avance, asi que la conversion mensual lo cuenta sin cambios de formula; la cuota lo suma via cumplimiento_metas_fn.';

revoke all on function crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text)
  from public, anon, service_role;
grant execute on function crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. private.leads_before_update — cuerpo ÍNTEGRO de producción + P4 relajada
-- ---------------------------------------------------------------------------
-- Todo lo que sigue es el cuerpo real (pg_get_functiondef, 2026-08-12; el
-- preflight 0.2 lo ancla por md5) salvo el bloque marcado «P4 RELAJADA». Las
-- protecciones existentes quedan en el MISMO ORDEN: (P1) inmutables, (P2/P3)
-- sin válvula ni conversión ni enlaces, (P3-bis) sello del origen, (P4)
-- invariante del convertido.
create or replace function private.leads_before_update()
returns trigger
language plpgsql
security definer
set search_path to 'crm', 'public'
as $function$
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

    -- ── SELLO DEL ORIGEN (migración D, 2026-08-11) ────────────────────────
    -- El origen se elige al ALTA y no se vuelve a mover. Lo que esto protege
    -- NO es un mes ya contado —el snapshot `lead_asignaciones.origen` ya era
    -- inmutable por `trg_lead_asignaciones_00_inmutables`— sino dos cosas del
    -- presente y del futuro:
    --   · el origen que copiará `private.trg_leads_asignaciones` al abrir el
    --     PRÓXIMO episodio de este lead (y ése sí sale del divisor del mes en
    --     curso si dice 'referido');
    --   · el bloque `referidos.dados_de_alta`, único número del payload que
    --     lee esta columna viva, agrupado por el mes de ALTA del lead.
    -- Se avisa con EXCEPCIÓN en vez de restaurar en silencio porque el store
    -- del front es optimista: un 200 mudo dejaría al usuario convencido de
    -- que corrigió.
    -- Va DENTRO de `if not v_priv`, a propósito: encima del gate el dato
    -- quedaría incorregible para siempre y el único remedio sería
    -- `disable trigger` en producción, que CLAUDE.md prohíbe.
    -- `is distinct from` (y no `<>`) hace que un UPDATE de payload completo que
    -- reenvía el MISMO valor no lance nada: es el caso de seed-demo.mjs y de
    -- test-rls.mjs, los dos únicos escritores que mandan `origen` en un UPDATE.
    if new.origen is distinct from old.origen then
      raise exception using
        errcode = 'P0409',
        message = 'El origen de un lead no se cambia despues del alta',
        detail  = pg_catalog.format(
          'lead %s: origen actual %L, intento %L',
          old.id, old.origen, new.origen),
        hint    = 'El origen se elige al crear el lead (crm.crear_lead_si_disponible). '
                  'La conversion mensual lee la FOTO del episodio, que ya es inmutable: '
                  'cambiar la ficha no mueve ningun mes ya contado, pero si moveria el '
                  'origen de los episodios FUTUROS de este lead y el bloque de referidos '
                  'dados de alta de su mes de creacion.';
    end if;
  end if;

  -- ── P4 RELAJADA (migración cierres externos, 2026-08-12) ────────────────
  -- Invariante de negocio en la transición (no como CHECK de tabla). Antes:
  -- «convertido ⇒ perfil_id no nulo». Ahora un convertido puede carecer de
  -- perfil SI Y SOLO SI tiene cierre externo (invirtió en una cooperativa y
  -- el portal no lo conoce). El EXISTS corre solo en la rama rara (convertido
  -- sin perfil) y lo sirve el UNIQUE de lead_id. Nótese que P2 sigue intacta:
  -- sin válvula no hay transición a convertido, con o sin cierre.
  if new.etapa = 'convertido' and new.perfil_id is null
     and not exists (
       select 1 from crm.cierres_externos ce where ce.lead_id = new.id
     ) then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. crm.corregir_cierre_externo — solo gerencia
-- ---------------------------------------------------------------------------
-- La conversión en sí NO se deshace (para eso está crm.anular_cierre_externo,
-- que la deja sin efecto sin reabrir el lead). Lo corregible: monto, moneda,
-- cooperativa, número de operación, certificado, vencimiento y nota. La
-- identidad (documento/nombre/vendedor que cobró) es foto y el trigger de
-- inmutabilidad la restaura aunque una RPC futura la mandara.
-- El número de operación entra aquí y NO en manos del vendedor (decisión de
-- Miguel 2026-08-12): es la prueba del cierre, y quien cobra no reescribe su
-- propia prueba.
-- Semántica de parámetros: el front manda el ESTADO COMPLETO de los campos
-- corregibles (formulario precargado); null en certificado/vencimiento/nota
-- LIMPIA el campo — por eso no hay defaults que distingan «omitido» de «null».
create or replace function crm.corregir_cierre_externo(
  p_cierre_id uuid,
  p_monto numeric,
  p_moneda text,
  p_cooperativa text,
  p_numero_transaccion text,
  p_referencia text,
  p_vence_en date,
  p_nota text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_cierre      crm.cierres_externos%rowtype;
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia corrige cierres externos'
      using errcode = '42501';
  end if;

  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;

  select * into v_cierre
  from crm.cierres_externos
  where id = p_cierre_id
  for update;
  if not found then
    raise exception 'Cierre externo no encontrado';
  end if;
  -- Un cierre anulado no se retoca: corregirlo daría a entender que vuelve a
  -- contar, y no vuelve. Si el monto anulado estaba mal, da igual: no paga.
  if v_cierre.anulado_en is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre esta anulado: ya no cuenta y no se corrige',
      detail  = pg_catalog.format('cierre %s, anulado el %s', v_cierre.id, v_cierre.anulado_en);
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  begin
    update crm.cierres_externos
       set monto = p_monto,
           moneda = p_moneda,
           cooperativa = p_cooperativa,
           numero_transaccion = v_transaccion,
           referencia_externa = v_referencia,
           vence_en = p_vence_en,
           nota = nullif(btrim(p_nota), '')
     where id = p_cierre_id;

    -- Si gerencia cambia el número, el NUEVO se reclama para siempre. El
    -- ANTERIOR no se libera: sigue en la memoria histórica, que es justo lo que
    -- impide que otro lead lo declare y el mismo depósito se cobre dos veces.
    if upper(v_transaccion) is distinct from upper(v_cierre.numero_transaccion) then
      insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
      values (upper(v_transaccion), p_cierre_id, v_uid);
    end if;
  exception when unique_violation then
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes (aunque su cierre se haya corregido despues): no se puede reusar.';
  end;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Rastro de negocio en la línea de tiempo del lead. Tipo 'nota' porque el
  -- CHECK de actividades no tiene 'correccion' y ampliarlo por esto no paga:
  -- el QUÉ cambió va en metadata (y el audit trigger guarda la fila entera).
  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    v_cierre.lead_id,
    'nota',
    'Gerencia corrigio el cierre externo',
    jsonb_build_object(
      'accion', 'correccion_cierre_externo',
      'cierre_externo_id', p_cierre_id,
      'antes', jsonb_build_object(
        'monto', v_cierre.monto, 'moneda', v_cierre.moneda,
        'cooperativa', v_cierre.cooperativa,
        'numero_transaccion', v_cierre.numero_transaccion,
        'referencia_externa', v_cierre.referencia_externa,
        'vence_en', v_cierre.vence_en, 'nota', v_cierre.nota),
      'despues', jsonb_build_object(
        'monto', p_monto, 'moneda', p_moneda,
        'cooperativa', p_cooperativa,
        'numero_transaccion', v_transaccion,
        'referencia_externa', v_referencia,
        'vence_en', p_vence_en, 'nota', nullif(btrim(p_nota), ''))
    ),
    v_uid
  );

  return jsonb_build_object('ok', true, 'cierre_id', p_cierre_id);
end;
$$;

comment on function crm.corregir_cierre_externo(uuid, numeric, text, text, text, text, date, text) is
  'Correccion de un cierre externo, SOLO gerencia: monto/moneda/cooperativa/numero de operacion/certificado/vencimiento/nota. El numero de operacion se corrige AQUI y no desde el vendedor: es la prueba del cierre. La conversion no se deshace (para eso esta crm.anular_cierre_externo) y la identidad del cierre (documento, nombre, vendedor que cobro) es inmutable. Un cierre anulado no se corrige. Deja actividad tipo nota con antes/despues.';

revoke all on function crm.corregir_cierre_externo(uuid, numeric, text, text, text, text, date, text)
  from public, anon, service_role;
grant execute on function crm.corregir_cierre_externo(uuid, numeric, text, text, text, text, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4-bis. crm.anular_cierre_externo — el freno de emergencia de gerencia
-- ---------------------------------------------------------------------------
-- QUÉ PROBLEMA RESUELVE: la cooperativa no le manda nada al CRM; el CRM le cree
-- al vendedor. Un cierre inventado —o mal digitado— le pagaba cuota y le subía
-- la conversión, y no había forma de deshacerlo: el DELETE está vetado y la
-- corrección exige monto > 0.
--
-- QUÉ NO HACE, y por qué: NO reabre el lead. En el CRM un convertido es estado
-- terminal por diseño (`private.trg_leads_guard_tenencia`, «Un lead convertido
-- no se puede reabrir», sin válvula que lo esquive) y el episodio del ledger es
-- inmutable una vez cerrado. Tampoco borra la fila: el lead quedó convertido y
-- esta fila es su ancla de legalidad ante la P4 —por eso la P4 mira que el
-- cierre EXISTA, anulado o no; si mirara solo los vivos, anular dejaría el lead
-- imposible de editar para siempre.
--
-- Lo que sí hace es lo que Miguel pidió (2026-08-12): que un cierre falso no
-- cuente NI en dinero NI en conversión. El dinero lo quita `cumplimiento_metas_fn`
-- (filtra `anulado_en is null`); la conversión, `private.conversion_mensual_por_vendedor`
-- (excluye del NUMERADOR los episodios con cierre anulado — el divisor no se
-- toca: el lead se trabajó, y ésa es la regla de la casa).
--
-- De UNA SOLA DIRECCIÓN: des-anular sería volver a pagar, y eso merece su propia
-- decisión, no un botón. El trigger de inmutabilidad lo impide aunque una RPC
-- futura lo intentara.
create or replace function crm.anular_cierre_externo(
  p_cierre_id uuid,
  p_motivo text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_cierre crm.cierres_externos%rowtype;
  v_motivo text := btrim(p_motivo);
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia anula cierres externos'
      using errcode = '42501';
  end if;

  -- El motivo es obligatorio a propósito: esto le quita dinero a una persona y
  -- esa persona merece una razón escrita, no un registro de auditoría mudo.
  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la anulacion'
      using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres'
      using errcode = '22023';
  end if;

  select * into v_cierre
  from crm.cierres_externos
  where id = p_cierre_id
  for update;
  if not found then
    raise exception 'Cierre externo no encontrado';
  end if;
  if v_cierre.anulado_en is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre ya estaba anulado',
      detail  = pg_catalog.format('cierre %s, anulado el %s', v_cierre.id, v_cierre.anulado_en);
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.cierres_externos
     set anulado_en = now(),
         anulado_por = v_uid,
         motivo_anulacion = v_motivo
   where id = p_cierre_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    v_cierre.lead_id,
    'nota',
    'Gerencia anulo el cierre externo',
    jsonb_build_object(
      'accion', 'anulacion_cierre_externo',
      'cierre_externo_id', p_cierre_id,
      'motivo', v_motivo,
      'anulado', jsonb_build_object(
        'cooperativa', v_cierre.cooperativa,
        'monto', v_cierre.monto,
        'moneda', v_cierre.moneda,
        'numero_transaccion', v_cierre.numero_transaccion,
        'vendedor_id', v_cierre.vendedor_id)
    ),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'cierre_id', p_cierre_id,
    'lead_id', v_cierre.lead_id);
end;
$$;

comment on function crm.anular_cierre_externo(uuid, text) is
  'Anula un cierre en cooperativa (fraude o error), SOLO gerencia y con motivo obligatorio. El cierre deja de contar en la cuota Y en la conversion mensual; la fila NO se borra (es el ancla de legalidad del lead convertido) y el lead NO se reabre (un convertido es terminal por diseno). Es de una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo y la foto de lo anulado.';

revoke all on function crm.anular_cierre_externo(uuid, text)
  from public, anon, service_role;
grant execute on function crm.anular_cierre_externo(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. crm.cierres_externos_fn — lectura para Mi cartera y el desglose
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER con justificación escrita: la tabla es deny-by-default (no
-- hay policies que un INVOKER pueda usar — mismo caso que conversion_mensual_fn
-- sobre el ledger). El gate es ALLOWLIST explícita ANTES de tocar datos, y el
-- ámbito se captura UNA vez en array para que `= any(...)` sea indexable
-- (lección 20260809144920). El lector global (directorio) recibe agregados y
-- totales pero NO las filas: las filas llevan PII (documento, teléfono) y ese
-- rol existe para leer números, no personas (lección RETOMAR-43 del rol raro).
create or replace function crm.cierres_externos_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text;
  v_lector     boolean;
  v_global     boolean;
  v_filas      boolean;
  v_alcance    text;
  v_visibles   uuid[];
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini        timestamptz;
  v_fin        timestamptz;
  v_payload    jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_filas := coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false);
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'alcance', v_alcance,
    -- Filas para la sección «En cooperativas» de Mi cartera (todo el
    -- histórico del ámbito, más reciente primero). Tope de 200 con total al
    -- lado: sin tope sería la lista sin fin que F2 vino a matar; con tope
    -- mudo, el front sumaría filas truncadas y mentiría en los totales — por
    -- eso los mini-totales NO salen de las filas sino de `totales`.
    'cierres', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or l.vendedor_id = any(v_visibles)
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        -- Los anulados SÍ viajan en las filas (y NO en los totales): el asesor
        -- tiene que poder entender por qué le bajó el total, no encontrarse un
        -- hueco donde antes había un cierre.
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where v_global or ce0.vendedor_id = any(v_visibles)
        order by ce0.creado_en desc
        limit 200
      ) ce
      join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where v_global or ce.vendedor_id = any(v_visibles)
    ),
    -- Las filas DEL MES pedido: es la vista de revisión de supervisor y gerencia
    -- («Ver cierres del mes»), donde el número de operación se contrasta. NO se
    -- filtra en el cliente sobre `cierres`, que viene tope 200 por antigüedad y
    -- podría no alcanzar el mes entero.
    'cierres_mes', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or l.vendedor_id = any(v_visibles)
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where ce0.creado_en >= v_ini and ce0.creado_en < v_fin
          and (v_global or ce0.vendedor_id = any(v_visibles))
        order by ce0.creado_en desc
        limit 200
      ) ce
      join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_mes_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where ce.creado_en >= v_ini and ce.creado_en < v_fin
        and (v_global or ce.vendedor_id = any(v_visibles))
    ),
    -- Mini-totales de Mi cartera: TODO el histórico del ámbito, por
    -- cooperativa y moneda (PEN/USD jamás sumados). Servidos aquí para que el
    -- front no haga aritmética sobre una lista que puede venir truncada.
    'totales', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cooperativa', t.cooperativa,
        'moneda', t.moneda,
        'capital', t.capital,
        'cierres', t.cierres
      ) order by t.cooperativa, t.moneda)
      from (
        select ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        where (v_global or ce.vendedor_id = any(v_visibles))
          and ce.anulado_en is null   -- los anulados no son dinero
        group by ce.cooperativa, ce.moneda
      ) t
    ), '[]'::jsonb),
    -- Desglose por empresa del MES pedido, por vendedor × cooperativa ×
    -- moneda, para supervisor y gerencia. La parte «Avance» del desglose la
    -- pone cumplimiento_metas_fn (capital_real ya INCLUYE los externos tras
    -- esta migración): Avance = capital_real − estos agregados, resta de dos
    -- números servidos — no una división en cliente.
    'por_empresa', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', x.vendedor_id,
        'vendedor_nombre', x.nombre,
        'cooperativa', x.cooperativa,
        'moneda', x.moneda,
        'capital', x.capital,
        'cierres', x.cierres
      ) order by x.nombre, x.cooperativa, x.moneda)
      from (
        select ce.vendedor_id, p.nombre_completo as nombre,
               ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        left join public.perfiles p on p.id = ce.vendedor_id
        where ce.creado_en >= v_ini and ce.creado_en < v_fin
          and (v_global or ce.vendedor_id = any(v_visibles))
          and ce.anulado_en is null   -- los anulados no son dinero
        group by ce.vendedor_id, p.nombre_completo, ce.cooperativa, ce.moneda
      ) x
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.cierres_externos_fn(date) is
  'Cierres en cooperativas para el front: filas del historico del ambito (Mi cartera, tope 200 + total), filas DEL MES pedido (vista de revision de supervisor/gerencia, con el numero de operacion), mini-totales por cooperativa/moneda y desglose del mes por vendedor x cooperativa x moneda. Los cierres ANULADOS viajan en las filas (marcados) pero NO en los totales ni en el desglose: no son dinero. Gate allowlist; ambito por vendedor_ids_visibles en array; el lector global recibe agregados sin filas (PII).';

revoke all on function crm.cierres_externos_fn(date)
  from public, anon, service_role;
grant execute on function crm.cierres_externos_fn(date) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. crm.cumplimiento_metas_fn — la cuota suma los cierres externos
-- ---------------------------------------------------------------------------
-- Cuerpo de producción (preflight 0.2 lo ancla por md5) con UN cambio: la CTE
-- `reales` bebe del UNION ALL de contratos confirmados + cierres externos.
-- ⚠️ VALORES-SOLO: ni una clave nueva ni un token distinto en el payload. El
-- front desplegado valida esta respuesta con `v.strictObject` y
-- `fuentes_reales.capital_y_contratos` es un `v.literal('contratos_confirmados')`:
-- cambiar la etiqueta rompería el CRM en producción en el instante del merge.
-- La procedencia fina (qué parte es coop) la sirve crm.cierres_externos_fn.
create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode='22023';
  end if;
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima';

  select mp.id,mp.revision,mp.publicada_en
    into v_periodo_id,v_revision,v_publicada_en
  from crm.meta_periodos mp where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision:=coalesce(v_revision,0);

  with contratos_base as materialized (
    -- public.contratos es la confirmación canónica. El lateral resume todos los
    -- enlaces explícitos sin duplicar el contrato y detecta los legacy ambiguos
    -- que apuntan a vendedores distintos: esos quedan sin atribuir.
    select
      c.id,
      c.categoria,
      c.moneda,
      c.capital,
      c.creado_por,
      coalesce(enlaces.tiene_vendedor_explicito,false)
        as tiene_vendedor_explicito,
      coalesce(enlaces.vendedores_distintos,0) as vendedores_distintos,
      enlaces.vendedor_unico
    from public.contratos c
    left join lateral (
      select
        count(*) filter(where lead.vendedor_id is not null)>0
          as tiene_vendedor_explicito,
        count(distinct lead.vendedor_id)
          filter(where lead.vendedor_id is not null)::integer
          as vendedores_distintos,
        case
          when count(distinct lead.vendedor_id)
            filter(where lead.vendedor_id is not null)=1
          then min(lead.vendedor_id::text)
            filter(where lead.vendedor_id is not null)::uuid
        end as vendedor_unico
      from crm.leads lead
      where lead.contrato_id=c.id
    ) enlaces on true
    where c.creado_en>=v_ini and c.creado_en<v_fin
      and c.categoria in ('nuevo','renovacion','upgrade')
      and c.moneda in ('PEN','USD')
  ), contratos_confirmados as materialized (
    -- La atribución explícita es autoritativa: si existe pero no pertenece al
    -- snapshot del mes, no cae silenciosamente al autor. El autor inmutable se
    -- usa solo cuando el contrato no tiene vendedor explícito. metas_vendedor
    -- impide que supervisores u otros actores se apropien de la producción.
    select
      base.id,
      case
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito then meta_lead.vendedor_id
        else meta_autor.vendedor_id
      end as vendedor_id,
      base.categoria,
      base.moneda,
      base.capital
    from contratos_base base
    left join crm.metas_vendedor meta_lead
      on meta_lead.meta_periodo_id=v_periodo_id
     and meta_lead.vendedor_id=base.vendedor_unico
    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id=v_periodo_id
     and meta_autor.vendedor_id=base.creado_por
  ), externos_confirmados as materialized (
    -- Cierres en cooperativas (Qorilazo/Prodelco): suman a la cuota del mes
    -- como categoría 'nuevo', en SU moneda (PEN/USD jamás se suman), atribuidos
    -- al vendedor_id FOTO del cierre y validados contra el snapshot de metas
    -- del mes — el MISMO contrato que un contrato Avance: fuera del snapshot ⇒
    -- sin atribución, nunca cae a otro actor (el JOIN hace ambas cosas).
    -- Ventana por creado_en: la fecha del cierre es automática y no se
    -- retro-data, así que el mes del cierre es el mes real.
    select
      mv.vendedor_id,
      'nuevo'::text as categoria,
      ce.moneda,
      ce.monto as capital
    from crm.cierres_externos ce
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=v_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=v_ini and ce.creado_en<v_fin
      -- Un cierre anulado por gerencia (fraude o error) deja de pagar. La fila
      -- sigue ahi porque es el ancla de legalidad del lead convertido, pero no
      -- es dinero. Su gemelo en la conversion vive en
      -- private.conversion_mensual_por_vendedor.
      and ce.anulado_en is null
  ), reales as (
    select vendedor_id,categoria,moneda,
      count(*)::integer as contratos_real,
      coalesce(sum(capital),0) as capital_real
    from (
      select vendedor_id,categoria,moneda,capital
      from contratos_confirmados
      where vendedor_id is not null
      union all
      select vendedor_id,categoria,moneda,capital
      from externos_confirmados
    ) confirmados
    group by vendedor_id,categoria,moneda
  ), conversiones as (
    -- La conversión conserva su definición histórica; la meta simplificada la
    -- publica en cero y por tanto deja de mostrarse como objetivo.
    -- ⚠️ El NUMERADOR excluye los cierres en cooperativa ANULADOS, igual que
    -- `private.conversion_mensual_por_vendedor`. Sin esto, tras una anulación
    -- este payload seguía diciendo «1 convertido, 100 %» —el lead sigue en
    -- etapa convertido— mientras la conversión mensual ya decía 0 %: dos
    -- números para el mismo concepto, y los dos pintados (resumen de gerencia,
    -- inteligencia comercial y las alertas beben de aquí). Es la misma clase de
    -- bug que cerró el release «un solo número bajo un solo nombre».
    -- El DIVISOR (`resueltos`) NO se toca: el lead se trabajó y sigue contando.
    select l.vendedor_id,
      count(*) filter(where l.etapa='convertido' and not private.cierre_externo_anulado(l.id))::integer as convertidos,
      count(*)::integer as resueltos,
      case when count(*)>0 then round(
        100.0*count(*) filter(where l.etapa='convertido' and not private.cierre_externo_anulado(l.id))/count(*),2
      ) end as conversion_real
    from crm.leads l
    where l.vendedor_id is not null
      and (
        (l.etapa='convertido' and l.convertido_en>=v_ini and l.convertido_en<v_fin)
        or (l.etapa='descartado' and l.descartado_en>=v_ini and l.descartado_en<v_fin)
      )
    group by l.vendedor_id
  ), visibles as (
    select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
    from crm.metas_vendedor mv
    join public.perfiles p on p.id=mv.vendedor_id
    join public.perfiles s on s.id=mv.supervisor_id
    where mv.meta_periodo_id=v_periodo_id
      and (private.es_lector_global()
        or mv.vendedor_id in (select private.vendedor_ids_visibles(v_uid)))
  )
  select jsonb_build_object(
    'version',1,'periodo',p_periodo,'revision',v_revision,
    'publicada_en',v_publicada_en,
    'fuentes_reales',jsonb_build_object(
      'capital_y_contratos','contratos_confirmados',
      'conversion','leads_resueltos'
    ),
    'vendedores',coalesce((select jsonb_agg(jsonb_build_object(
      'vendedor_id',mv.vendedor_id,'nombre',mv.nombre_completo,
      'supervisor_id',mv.supervisor_id,'supervisor_nombre',mv.supervisor_nombre,
      'conversion_objetivo',mv.conversion_objetivo,
      'conversion_real',cv.conversion_real,
      'convertidos',coalesce(cv.convertidos,0),'resueltos',coalesce(cv.resueltos,0),
      'detalles',(select jsonb_agg(jsonb_build_object(
        'categoria',d.categoria,'moneda',d.moneda,
        'capital_objetivo',d.capital_objetivo,
        'capital_real',coalesce(r.capital_real,0),
        'capital_cumplimiento_pct',case when d.capital_objetivo>0
          then round(100.0*coalesce(r.capital_real,0)/d.capital_objetivo,2) end,
        'contratos_objetivo',d.contratos_objetivo,
        'contratos_real',coalesce(r.contratos_real,0),
        'contratos_cumplimiento_pct',case when d.contratos_objetivo>0
          then round(100.0*coalesce(r.contratos_real,0)/d.contratos_objetivo,2) end
      ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
      from crm.metas_vendedor_detalle d
      left join reales r on r.vendedor_id=mv.vendedor_id
        and r.categoria=d.categoria and r.moneda=d.moneda
      where d.meta_vendedor_id=mv.id)
    ) order by mv.supervisor_nombre,mv.nombre_completo) from visibles mv
    left join conversiones cv on cv.vendedor_id=mv.vendedor_id),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$;

comment on function crm.cumplimiento_metas_fn(date) is
  'Cumplimiento de la última revisión mensual. Cuenta contratos canónicos por vendedor explícito elegible (autor inmutable solo si ningún lead declara vendedor) MÁS los cierres externos en cooperativas (categoría nuevo, vendedor foto del cierre). Todo candidato debe estar en el snapshot de metas del mes; inelegibles o ambiguos quedan sin atribuir. La etiqueta fuentes_reales conserva su literal v1 (el front desplegado la valida estricta); el desglose por empresa vive en crm.cierres_externos_fn. PEN/USD permanece separado.';

-- ---------------------------------------------------------------------------
-- 6-bis. private.conversion_mensual_por_vendedor — la conversión ignora los
--        cierres externos ANULADOS
-- ---------------------------------------------------------------------------
-- Cuerpo ÍNTEGRO de producción (20260811154434, único sitio donde se define;
-- el preflight 0.2 lo ancla por md5) con UN cambio: la CTE `cierres` —el
-- NUMERADOR— excluye los episodios cuyo lead tiene un cierre externo anulado.
--
-- Por qué aquí y no en el ledger: el episodio de `crm.lead_asignaciones` es
-- inmutable una vez cerrado, por diseño y con trigger que lo defiende. La
-- conversión no puede «desconvertirse»; lo que sí puede es dejar de contar el
-- cierre que gerencia declaró falso. Ése es el acuerdo con Miguel (2026-08-12):
-- un cierre anulado no cuenta NI en dinero NI en conversión.
--
-- El DIVISOR no se toca a propósito: el asesor trabajó ese lead y le sigue
-- contando, igual que le cuenta un descartado (regla de la casa). Lo que se le
-- quita es el premio, no el trabajo.
--
-- Un cierre AVANCE nunca tiene fila en `crm.cierres_externos`, así que para
-- ellos el predicado es cierto por vacuidad y los números del mes no se mueven
-- ni un decimal (la regresión `test-conversion-mensual.sql` lo prueba).
--
-- ⚠️ De la copia NO se toca nada más: ni `#variable_conflict use_column`, ni la
-- firma, ni el `returns table(...)` —el postflight de la migración de origen
-- asevera contra `pg_proc` que existe `cierres_de_arrastre`—, ni el `revoke`
-- total sin `grant` (es núcleo privado: solo la llaman DEFINERs que ya hicieron
-- su gate).
create or replace function private.conversion_mensual_por_vendedor(
  p_ini timestamptz,
  p_fin timestamptz,
  p_global boolean,
  p_visibles uuid[],
  p_factor numeric
)
returns table (
  analista_id uuid,
  divisor integer,
  divisor_aproximado integer,
  divisor_por_motivo jsonb,
  cierres_no_referidos integer,
  cierres_referidos integer,
  cierres_de_arrastre integer,
  numerador numeric,
  conversion_pct numeric,
  procedencia jsonb,
  referidos_recibidos integer,
  referidos_aporta_pct numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
-- Los nombres de las columnas de salida (`analista_id`, `divisor`, …) son
-- VARIABLES dentro de un cuerpo plpgsql y podrían ganarle a una columna
-- homónima. Todo el cuerpo va cualificado, pero esta directiva lo hace
-- estructural en vez de depender de la disciplina de quien edite mañana: ante
-- la duda, gana la COLUMNA, que es la semántica SQL de siempre.
#variable_conflict use_column
begin
return query
with recibidos as (
  -- DIVISOR (bruto): «V RECIBIÓ el lead en M» = tiene un episodio con
  -- `asignado_en` dentro de [ini, fin). Entran todos los canales, los abiertos y
  -- los DESCARTADOS. Como el ledger NO TIENE columna `activo`, la LEY —«la
  -- conversión no filtra activo», un lead soft-borrado sigue contando— se
  -- cumple por construcción y no hay predicado que alguien pueda «arreglar».
  -- `group by (analista, lead)` = contar el LEAD y no el episodio: un A→B→A
  -- dentro del mes le pesa UNO a A (T5). Sin esto se podría hundir un
  -- porcentaje moviendo un lead de ida y vuelta.
  -- El `order by … ASC` no es cosmético: cuando un lead tiene VARIOS episodios
  -- del mismo analista dentro del mes, la pregunta que responden `origen` y
  -- `motivo_apertura` es «¿por qué entró este lead al divisor DE ESTE MES?», y
  -- eso lo contesta el PRIMER episodio del mes, no el último. Con `desc`, 100
  -- leads que entran por `ingreso` el día 1, se parquean el 2 y se reactivan el
  -- mismo día 2 salían en el desglose como `{"reactivado": 100}`: la clave
  -- `ingreso` desaparecía y el pico de la carga masiva —lo único que este
  -- desglose existe para hacer VISIBLE (H3)— quedaba escondido, y encima
  -- disfrazado de reciclaje de cartera vieja. Verificado en PG16. No mueve el
  -- divisor (sigue habiendo un valor por (analista, lead)): solo reetiqueta.
  select
    la.analista_id,
    la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini
    and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
),
cierres as (
  -- NUMERADOR: atribuido al `analista_id` de la fila inmutable que cerró (T2),
  -- fechado por `resultado_en` (T3) y con «era referido» leído del SNAPSHOT
  -- (T4). La fecha del cierre sale de la MISMA fila que `asignado_en`: numerador
  -- y procedencia comparten reloj y no se pueden contradecir.
  -- `coalesce(resultado_en, finalizado_en)` y no `resultado_en` a secas: el CHECK
  -- `lead_asignaciones_cierre_consistente` es TRIVALUADO en la rama 'convertido'
  -- —`resultado_en = finalizado_en` da NULL si el primero es NULL, y un CHECK
  -- solo rechaza en FALSE—, así que un cierre real puede existir sin
  -- `resultado_en` y se perdería del numerador dando 0 % donde hubo 100 %. El
  -- fallback es seguro: con `resultado` no nulo, el CHECK exige `finalizado_en is
  -- not null` en un predicado bivaluado, o sea que SIEMPRE hay fecha. En el caso
  -- sano los dos campos son iguales y esto no cambia nada. Ver cabecera.
  select
    la.analista_id,
    la.lead_id,
    (la.origen = 'referido') as fue_referido,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    -- El mes que se está midiendo, calculado UNA vez y arrastrado en la CTE para
    -- que «arrastre» y «cubo de procedencia» no puedan derivarlo cada uno a su
    -- manera. `p_ini` es por contrato el primer instante del mes en Lima.
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
    -- ÚNICO cambio respecto del cuerpo de producción (cierres externos,
    -- 2026-08-12): un cierre en cooperativa que gerencia ANULÓ —falso o mal
    -- digitado— deja de contar como conversión ganada. El episodio del ledger
    -- no se puede reabrir (es inmutable por diseño), así que la anulación se
    -- expresa aquí. Para un cierre Avance no hay fila en `cierres_externos` y
    -- el predicado es falso por vacuidad: sus números no se mueven.
    -- La pregunta se hace con `private.cierre_externo_anulado` y no en línea:
    -- el otro numerador de conversión (la CTE `conversiones` de
    -- `cumplimiento_metas_fn`) hace la MISMA pregunta, y escrita dos veces a
    -- mano las dos divergen — ya pasó una vez.
    and not private.cierre_externo_anulado(la.lead_id)
),
motivos as (
  -- Desglose del divisor por motivo de apertura. Es lo que deja VISIBLE en
  -- pantalla el pico de una carga masiva (H3) en vez de esconderlo dentro de un
  -- porcentaje. Solo cuenta lo que está en el divisor: los referidos no.
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r
  where not r.fue_referido
  group by r.analista_id, r.motivo
),
motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m
  group by m.analista_id
),
agg_div as (
  -- El divisor EXCLUYE los referidos (T10). La fila del asesor SIGUE existiendo
  -- aunque el divisor quede en 0: es el caso «solo recibió referidos», que hay
  -- que poder distinguir de «no recibió nada».
  select
    r.analista_id,
    count(*) filter (where not r.fue_referido)::int as divisor,
    count(*) filter (where r.aproximado and not r.fue_referido)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r
  group by r.analista_id
),
agg_cie as (
  -- Se cuentan LEADS DISTINTOS, no episodios — el mismo criterio que el divisor
  -- («T5: se cuenta el LEAD, no el episodio») y por el mismo motivo. Aquí además
  -- es un cinturón contra el agujero 2: el EXCLUDE `lead_asignaciones_sin_solape`
  -- deja convivir dos episodios convertidos del mismo lead si son ADYACENTES o de
  -- duración cero, y un `count(*)` publicaría 200 % con divisor 1. El `filter`
  -- sigue separando referidos de no referidos: `count(distinct x) filter (...)`
  -- es SQL válido y para el caso normal —un cierre por lead— da exactamente lo
  -- mismo que antes (comprobado sobre el caso canónico de Ana: 16 y 12).
  -- ⚠️ ALCANCE EXACTO DEL CINTURÓN: el `group by` es por `analista_id`, así que
  -- esto deduplica DENTRO de un analista. El mismo lead cerrado por DOS
  -- analistas en episodios terminales adyacentes o de duración cero suma 1 + 1
  -- en `total`, y eso NO se arregla aquí sin romper T5 (cada cierre se atribuye
  -- a quien lo cerró): lo cierra en la raíz el índice único parcial de
  -- `20260811190310_crm_ledger_cierres_integros.sql`, que va en el mismo
  -- despliegue.
  -- `cierres_de_arrastre` es el sumando que explica un `conversion_pct` por
  -- encima de 100 sin ninguna fila enferma: cierres del mes cuyo divisor fue
  -- otro mes. Va también en `total`, que era el único sitio del payload donde el
  -- número no se podía descomponer (ver cabecera, «El porcentaje NO tiene
  -- techo»).
  select
    c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c
  group by c.analista_id
),
proc as (
  -- Procedencia en CONTEOS ENTEROS, nunca en porcentajes (T6): sumar
  -- porcentajes ya redondeados hace que «agosto + julio» no cuadre con el
  -- total. Los meses de más de 11 atrás caen en un cubo `anteriores` para que
  -- el payload no crezca sin techo.
  -- También por LEADS DISTINTOS, para que la suma de la procedencia cuadre con
  -- los `cierres_*` de la fila: si el numerador cuenta leads y el desglose
  -- contara episodios, «agosto + julio» dejaría de sumar el total y la
  -- contradicción se leería como un bug de la pantalla.
  -- `cierres` se calcula como la SUMA DE LOS DOS MISMOS conteos filtrados que
  -- usa `agg_cie`, y NO como un `count(distinct lead_id)` a secas. Parecen lo
  -- mismo y no lo son: un lead con dos episodios convertidos en el mes con
  -- snapshots de `origen` distintos (uno 'landing', otro 'referido') suma 1 + 1
  -- en `agg_cie` —el `distinct` es por grupo del `filter`, no global— y habría
  -- sumado 1 aquí. La tarjeta diría «2 cierres» arriba y «1 cierre» en su propio
  -- desglose por mes. Escrito así, los dos lados no se pueden separar por
  -- construcción, valga lo que valga el ledger. Verificado en PG16.
  select
    c.analista_id,
    c.mes_cubo,
    (count(distinct c.lead_id) filter (where not c.fue_referido)
     + count(distinct c.lead_id) filter (where c.fue_referido))::int as cierres,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos
  from (
    select
      c0.analista_id,
      c0.lead_id,
      c0.fue_referido,
      case
        when (extract(year from p_ini at time zone 'America/Lima')::int * 12
              + extract(month from p_ini at time zone 'America/Lima')::int)
             - (extract(year from c0.mes_origen)::int * 12
                + extract(month from c0.mes_origen)::int) <= 11
        then c0.mes_origen
      end as mes_cubo
    from cierres c0
  ) c
  group by c.analista_id, c.mes_cubo
),
proc_json as (
  select
    p.analista_id,
    jsonb_agg(
      jsonb_build_object(
        'mes', case when p.mes_cubo is not null
                    then pg_catalog.to_char(p.mes_cubo, 'YYYY-MM') end,
        'mes_nombre', case when p.mes_cubo is not null
                           then private.etiqueta_mes_es(p.mes_cubo)
                           else 'anteriores' end,
        'anio', case when p.mes_cubo is not null
                     then extract(year from p.mes_cubo)::int end,
        'cierres', p.cierres,
        'cierres_referidos', p.cierres_referidos
      )
      order by p.mes_cubo desc nulls last
    ) as procedencia
  from proc p
  group by p.analista_id
)
select
  coalesce(d.analista_id, c.analista_id),
  coalesce(d.divisor, 0),
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  -- Numerador FRACCIONARIO y SIN redondear (T6). `numeric` es decimal exacto:
  -- con float8 daría 12,449999…
  (coalesce(c.cierres_no_referidos, 0) + p_factor * coalesce(c.cierres_referidos, 0))::numeric,
  -- NULL, jamás 0, cuando el divisor es 0: un 0 se leería como «0 % de
  -- conversión», o sea como que no cerró nada de lo que recibió.
  case when coalesce(d.divisor, 0) > 0 then
    round(
      100.0 * (coalesce(c.cierres_no_referidos, 0) + p_factor * coalesce(c.cierres_referidos, 0))
      / d.divisor, 2)
  end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  -- Cuántos PUNTOS del porcentaje puso el 15 % de los referidos.
  case when coalesce(d.divisor, 0) > 0 then
    round(100.0 * p_factor * coalesce(c.cierres_referidos, 0) / d.divisor, 2)
  end
-- FULL OUTER JOIN: un asesor puede tener divisor sin cierres (mes normal) o
-- cierres SIN divisor (arrastra cartera vieja y no recibió nada). El segundo es
-- justo el que hay que poder distinguir; un INNER JOIN lo haría desaparecer y la
-- pantalla diría que no trabajó.
from agg_div d
full outer join agg_cie c on c.analista_id = d.analista_id
left join motivos_json mj on mj.analista_id = d.analista_id
left join proc_json pj on pj.analista_id = coalesce(d.analista_id, c.analista_id);
end;
$function$;

comment on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric) is
  'Nucleo aritmetico UNICO de la conversion mensual: divisor = leads NO referidos recibidos en el mes (asignado_en, T1/T10), numerador = cierres del mes con los referidos al p_factor (T2/T3/T4), EXCLUIDOS los cierres en cooperativa que gerencia anulo. Los DOS lados cuentan LEADS DISTINTOS, nunca episodios (T5), y el cierre se fecha con coalesce(resultado_en, finalizado_en) porque el CHECK del ledger es trivaluado en la rama convertido. plpgsql y no language sql a proposito: SECURITY DEFINER + SET search_path impiden el inlining, y sin inlining el plan seria GENERICO y el ambito caeria a Filter (los indices por analista dejarian de servir). Sin gate: solo la llaman funciones que ya hicieron el suyo.';

revoke all on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)
  from public, anon, authenticated, service_role;
-- ---------------------------------------------------------------------------
-- 7. Postflight — se EJERCITA el comportamiento dentro de una subtransacción
--    que SIEMPRE se deshace (P0999); los veredictos (variables plpgsql)
--    sobreviven al rollback y se comprueban fuera.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_id          uuid;
  v_id2         uuid;
  v_tel         text;
  v_tel2        text;
  v_vendedor    uuid;
  v_cierre      uuid;
  v_asig_antes  bigint;
  v_asig_dentro bigint;
  v_lead_conv   crm.leads%rowtype;
  v_p4_bloquea_ok  boolean := false;  -- (1) convertido sin perfil NI cierre sigue prohibido
  v_p2_ok          boolean := false;  -- (2) sin válvula no hay conversión, ni con cierre
  v_p4_externo_ok  boolean := false;  -- (3) con cierre externo el convertido sin perfil PASA
  v_upd_directo_ok boolean := false;  -- (4) UPDATE del cierre sin válvula → P0409
  v_del_ok         boolean := false;  -- (5) DELETE del cierre → P0409 siempre
  v_rpc_gate_ok    boolean := false;  -- (6) la RPC sin sesión → 42501
  v_ledger_ok      boolean := false;  -- (7) el episodio del lead de prueba se cerró convertido (circuito real)
  v_ref_unica_ok   boolean := false;  -- (8) mismo deposito + misma coop en OTRO lead → rechazado
  v_anulado_ancla_ok boolean := false;  -- (9) anulado, el cierre SIGUE siendo el ancla de la P4
  v_no_resucita_ok boolean := false;  -- (10) un cierre anulado no se restablece ni con valvula
  v_motivo_obliga_ok boolean := false;  -- (11) no hay anulacion sin motivo (la trampa del CHECK trivaluado)
begin
  select count(*) into v_asig_antes from crm.lead_asignaciones;

  -- (6) fuera de la subtransacción no hace falta: la RPC no toca nada antes
  -- del gate, pero la probamos dentro igualmente por simetría con el resto.
  begin
    -- Dos teléfonos sintéticos libres (formato +519########): el segundo lead
    -- existe para probar que la referencia repetida se rechaza por SU índice y
    -- no de rebote por el UNIQUE(lead_id).
    for i in 1..200 loop
      v_tel2 := '+519' || pg_catalog.lpad((80000000 + i)::text, 8, '0');
      if not exists (select 1 from crm.leads l where l.telefono = v_tel2) then
        if v_tel is null then v_tel := v_tel2; v_tel2 := null;
        else exit;
        end if;
      else
        v_tel2 := null;
      end if;
    end loop;
    if v_tel is null or v_tel2 is null then
      raise exception 'Postflight: no quedan dos telefonos sinteticos libres para la prueba';
    end if;

    -- El vendedor: cualquiera real y activo (en branch el seed corre antes; en
    -- producción crm.equipo está poblada). Sin filas, el mensaje lo dice.
    select e.perfil_id into v_vendedor
    from crm.equipo e
    where e.rol_crm = 'vendedor' and e.activo
    limit 1;
    if v_vendedor is null then
      select e.perfil_id into v_vendedor from crm.equipo e where e.activo limit 1;
    end if;
    if v_vendedor is null then
      raise exception 'Postflight: crm.equipo esta vacia; se necesita un perfil real para la FK de vendedor_id';
    end if;

    -- Lead CON analista, a propósito: `trg_leads_guard_tenencia` prohíbe
    -- convertir sin analista incluso bajo la válvula (descubierto al aplicar
    -- en branch), así que el lead de prueba recorre el camino real completo —
    -- su episodio se ABRE aquí y el veredicto (7) exige que el cierre bajo la
    -- válvula lo CIERRE como convertido: este postflight ya no solo prueba la
    -- P4, prueba el circuito entero que la conversión mensual cuenta.
    insert into crm.leads (
      nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
      vendedor_id, asignado_supervisor_id, activo
    ) values (
      'POSTFLIGHT cierres externos', v_tel, 'otro', 'nuevo', 1000, 'PEN',
      v_vendedor, null, true
    )
    returning id into v_id;

    -- (1) convertido sin perfil y SIN cierre debe seguir prohibido aun con la
    -- válvula: la P4 se relajó, no se apagó.
    begin
      perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      update crm.leads set etapa = 'convertido', convertido_en = now()
       where id = v_id;
    exception when raise_exception then
      v_p4_bloquea_ok := (sqlerrm like '%convertido debe estar enlazado%');
    end;
    perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

    -- La foto del cierre, insertada como owner (la Data API no puede: cero
    -- grants — el veredicto estructural de abajo lo afirma con
    -- has_table_privilege).
    insert into crm.cierres_externos (
      lead_id, cooperativa, monto, moneda,
      documento_tipo, documento, nombre_completo, numero_transaccion,
      vendedor_id, creado_por
    ) values (
      v_id, 'qorilazo', 5000.00, 'PEN',
      'DNI', '99999998', 'POSTFLIGHT cierres externos', 'POSTFLIGHT-OP-1',
      v_vendedor, v_vendedor
    )
    returning id into v_cierre;

    -- (8) el mismo depósito, en la misma cooperativa, sobre OTRO lead: es el
    -- fraude exacto del checkpoint (teléfono nuevo, lead nuevo, mismo depósito).
    -- Va contra un segundo lead a propósito, para que el UNIQUE(lead_id) no sea
    -- quien lo rechace: el veredicto es del índice del depósito o de nadie. Y
    -- se manda con otra caja y con espacios, que es lo que normaliza el índice.
    insert into crm.leads (
      nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
      vendedor_id, asignado_supervisor_id, activo
    ) values (
      'POSTFLIGHT cierres externos 2', v_tel2, 'otro', 'nuevo', 1000, 'PEN',
      v_vendedor, null, true
    )
    returning id into v_id2;
    begin
      insert into crm.cierres_externos (
        lead_id, cooperativa, monto, moneda,
        documento_tipo, documento, nombre_completo, numero_transaccion,
        vendedor_id, creado_por
      ) values (
        v_id2, 'qorilazo', 5000.00, 'PEN',
        'DNI', '99999998', 'POSTFLIGHT cierres externos', ' postflight-op-1 ',
        v_vendedor, v_vendedor
      );
    exception when unique_violation then
      v_ref_unica_ok := true;
    end;

    -- (2) con cierre pero SIN válvula, la conversión sigue prohibida (P2).
    begin
      update crm.leads set etapa = 'convertido' where id = v_id;
    exception when raise_exception then
      v_p2_ok := (sqlerrm like '%solo se hace v_a la operaci_n de conversi_n%');
    end;

    -- (3) con cierre y CON válvula, el convertido sin perfil pasa.
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
    update crm.leads set etapa = 'convertido', convertido_en = now()
     where id = v_id;
    perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
    select * into v_lead_conv from crm.leads where id = v_id;
    v_p4_externo_ok := (v_lead_conv.etapa = 'convertido'
                        and v_lead_conv.perfil_id is null
                        and v_lead_conv.convertido_en is not null);

    -- (4) el cierre no se toca sin válvula.
    begin
      update crm.cierres_externos set monto = 6000.00 where id = v_cierre;
    exception when sqlstate 'P0409' then
      v_upd_directo_ok := true;
    end;

    -- (5) el cierre no se borra, con o sin válvula.
    begin
      perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      delete from crm.cierres_externos where id = v_cierre;
    exception when sqlstate 'P0409' then
      v_del_ok := true;
    end;
    perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

    -- (6) la RPC sin sesión muere en el gate con 42501.
    begin
      perform crm.convertir_lead_externo(
        v_id, 'qorilazo', 1000.00, 'PEN', 'DNI', '99999998', 'X', 'POSTFLIGHT-OP-6');
    exception when insufficient_privilege then
      v_rpc_gate_ok := true;
    end;

    -- (9) EL ANCLA SOBREVIVE A LA ANULACIÓN. Es el riesgo más silencioso de
    -- todo este fichero: la P4 relajada deja pasar al convertido sin perfil
    -- PORQUE existe el cierre. Si la anulación quitara ese ancla —o si la P4
    -- mirara solo los cierres vivos—, anular dejaría el lead IMPOSIBLE DE
    -- EDITAR para siempre, y nadie lo notaría hasta que alguien tocara la
    -- ficha. Aquí se anula el cierre y acto seguido se edita el lead: si la P4
    -- se quejara, este UPDATE moriría.
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
    update crm.cierres_externos
       set anulado_en = now(), anulado_por = v_vendedor,
           motivo_anulacion = 'POSTFLIGHT: anulacion de prueba'
     where id = v_cierre;
    perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
    update crm.leads
       set nombre_completo = 'POSTFLIGHT cierres externos (editado)'
     where id = v_id;
    v_anulado_ancla_ok := exists (
      select 1 from crm.leads l
      where l.id = v_id and l.etapa = 'convertido' and l.perfil_id is null
        and l.nombre_completo = 'POSTFLIGHT cierres externos (editado)'
    );

    -- (10) y la anulación es de una sola dirección: ni con la válvula se
    -- resucita un cierre anulado.
    begin
      perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      update crm.cierres_externos
         set anulado_en = null, anulado_por = null, motivo_anulacion = null
       where id = v_cierre;
    exception when sqlstate 'P0409' then
      v_no_resucita_ok := true;
    end;
    perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

    -- (11) NO HAY ANULACIÓN SIN MOTIVO, y se prueba contra la BASE, no contra
    -- la RPC: la RPC ya valida el motivo, pero el CHECK existe para las rutas
    -- que aún no se han escrito. Este caso nace de un defecto real encontrado
    -- en revisión: con el motivo en NULL, `btrim(null) <> ''` daba NULL y un
    -- CHECK solo rechaza en FALSE, así que la fila entraba. Si alguien vuelve a
    -- redactar este CHECK «más limpio», este veredicto lo caza.
    begin
      insert into crm.cierres_externos (
        lead_id, cooperativa, monto, moneda,
        documento_tipo, documento, nombre_completo, numero_transaccion,
        vendedor_id, creado_por,
        anulado_en, anulado_por, motivo_anulacion
      ) values (
        v_id2, 'prodelco', 1.00, 'PEN',
        'DNI', '99999996', 'POSTFLIGHT sin motivo', 'POSTFLIGHT-OP-11',
        v_vendedor, v_vendedor,
        now(), v_vendedor, null
      );
    exception when check_violation then
      v_motivo_obliga_ok := true;
    end;

    -- (7) el ledger ganó EXACTAMENTE los episodios de los DOS leads de prueba
    -- (el del circuito y el del depósito repetido), ni uno más, y el cierre bajo
    -- la válvula cerró el del primero como convertido — medido DENTRO, con la
    -- foto viva. Es el circuito completo que cuenta la conversión mensual.
    -- El segundo lead debe quedar con su episodio ABIERTO: su cierre fue
    -- rechazado por el índice del depósito, así que nada lo cerró.
    select count(*) into v_asig_dentro from crm.lead_asignaciones;
    v_ledger_ok := (v_asig_dentro = v_asig_antes + 2)
      and exists (
        select 1 from crm.lead_asignaciones la
        where la.lead_id = v_id
          and la.resultado = 'convertido'
          and la.finalizado_en is not null
      )
      and exists (
        select 1 from crm.lead_asignaciones la
        where la.lead_id = v_id2
          and la.resultado is null
          and la.finalizado_en is null
      );

    raise exception using errcode = 'P0999', message = 'postflight: deshacer';
  exception
    when sqlstate 'P0999' then
      perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  end;

  if not v_p4_bloquea_ok then
    raise exception 'Postflight (1): un convertido sin perfil y sin cierre externo NO fue rechazado — la P4 quedo apagada en vez de relajada';
  end if;
  if not v_p2_ok then
    raise exception 'Postflight (2): la conversion por UPDATE sin valvula NO fue rechazada — P2 rota';
  end if;
  if not v_p4_externo_ok then
    raise exception 'Postflight (3): un convertido con cierre externo y sin perfil NO paso — la relajacion de P4 no funciona';
  end if;
  if not v_upd_directo_ok then
    raise exception 'Postflight (4): un UPDATE directo del cierre sin valvula NO fue rechazado con P0409';
  end if;
  if not v_del_ok then
    raise exception 'Postflight (5): un DELETE del cierre NO fue rechazado con P0409';
  end if;
  if not v_rpc_gate_ok then
    raise exception 'Postflight (6): crm.convertir_lead_externo sin sesion NO devolvio 42501';
  end if;
  if not v_ledger_ok then
    raise exception 'Postflight (7): el ledger no refleja el circuito de los leads de prueba (antes %, durante %; se esperaba antes+2: el primero cerrado convertido y el segundo con su episodio abierto)',
      v_asig_antes, v_asig_dentro;
  end if;
  if not v_ref_unica_ok then
    raise exception 'Postflight (8): el MISMO numero de operacion en la misma cooperativa, sobre otro lead, NO fue rechazado — el mismo cierre se puede cobrar dos veces';
  end if;
  if not v_anulado_ancla_ok then
    raise exception 'Postflight (9): tras anular el cierre, el lead convertido sin perfil dejo de poder editarse — la P4 debe mirar que el cierre EXISTA, no que este vivo';
  end if;
  if not v_no_resucita_ok then
    raise exception 'Postflight (10): un cierre anulado SE PUDO restablecer bajo la valvula — la anulacion debe ser de una sola direccion';
  end if;
  if not v_motivo_obliga_ok then
    raise exception 'Postflight (11): entro un cierre ANULADO SIN MOTIVO — el CHECK de la anulacion volvio a ser trivaluado (un CHECK solo rechaza en FALSE, y con el motivo en NULL la rama da NULL)';
  end if;

  -- Veredictos estructurales (fuera de la subtransacción: son estado, no datos).
  if not (select relrowsecurity from pg_class
          where oid = 'crm.cierres_externos'::regclass) then
    raise exception 'Postflight: crm.cierres_externos quedo SIN RLS';
  end if;
  if has_table_privilege('authenticated', 'crm.cierres_externos', 'select')
     or has_table_privilege('anon', 'crm.cierres_externos', 'select')
     or has_table_privilege('service_role', 'crm.cierres_externos', 'select')
     or has_table_privilege('authenticated', 'crm.cierres_externos', 'insert') then
    raise exception 'Postflight: crm.cierres_externos tiene grants directos — debe ser deny-by-default absoluto';
  end if;

  -- La tabla de reservas nace con las MISMAS defensas: si alguna se cayera, la
  -- Data API podría fabricar una reserva y bloquear cierres ajenos a voluntad.
  if not (select relrowsecurity from pg_class
          where oid = 'crm.conversion_reservas'::regclass) then
    raise exception 'Postflight: crm.conversion_reservas quedo SIN RLS';
  end if;
  if has_table_privilege('authenticated', 'crm.conversion_reservas', 'select')
     or has_table_privilege('authenticated', 'crm.conversion_reservas', 'insert')
     or has_table_privilege('anon', 'crm.conversion_reservas', 'select')
     or has_table_privilege('service_role', 'crm.conversion_reservas', 'select') then
    raise exception 'Postflight: crm.conversion_reservas tiene grants directos — debe ser deny-by-default absoluto';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'crm.depositos_reclamados'::regclass) then
    raise exception 'Postflight: crm.depositos_reclamados quedo SIN RLS';
  end if;
  if has_table_privilege('authenticated', 'crm.depositos_reclamados', 'select')
     or has_table_privilege('authenticated', 'crm.depositos_reclamados', 'insert')
     or has_table_privilege('anon', 'crm.depositos_reclamados', 'select')
     or has_table_privilege('service_role', 'crm.depositos_reclamados', 'select') then
    raise exception 'Postflight: crm.depositos_reclamados tiene grants directos — debe ser deny-by-default absoluto';
  end if;

  raise notice 'Postflight cierres externos OK: P4 relajada pero viva (y sobrevive a la anulacion), P2 intacta, cierre inmutable (update/delete P0409), deposito unico por cooperativa, anulacion de una sola direccion, gate 42501, ledger intacto, deny-by-default verificado en las dos tablas';
end;
$postflight$;

commit;

-- ============================================================================
-- Nota de aplicación
-- ============================================================================
-- Ciclo obligatorio: branch de Supabase → aplicar por psql (pooler 5432) →
-- oráculo supabase/scripts/test-cierres-externos.sql → gate test-rls.mjs
-- (línea base 862 + bloque nuevo) → advisors (0 ERROR) → auditor-rls + Codex
-- refutando ANTES del merge. Tras el merge: `npm run gen:types` en app/ y
-- registrar en MIGRACIONES.md.
