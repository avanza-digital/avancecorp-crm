ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 1 de «Asignar cuenta de pago» (LEVEL 3: instrucciones de pago, núcleo SECURITY DEFINER, tabla nueva, pantalla de Pagos) + seguimiento de tu ronda anterior

Eres el revisor secundario. Sin base de datos, sin red y sin disco: todo lo que debes juzgar está transcrito abajo. Tu trabajo es REFUTAR. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo, línea o fragmento citado), riesgos y huecos de prueba, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; marca qué es hipótesis. No propongas `git reset --hard`, `git clean`, `rm -rf`, force push, DROP/TRUNCATE ni cambios directos en producción. El PRIMARY (Claude) decide con evidencia; tú asesoras.

## Negocio (decisión de Miguel, 01/10/2026)
22 contratos viejos no tienen cuenta de pago (fila en `crm.contrato_cuentas_pago`) y por eso no se pueden marcar sus pagos; el bloqueo es correcto y no se relaja. No se pueden vincular solos: el cliente tiene dos cuentas, o solo en la otra moneda, o ninguna. Hasta hoy NO existía operación para vincular una cuenta a un contrato ya creado: el alta solo vincula al crear, y «Cambiar cuenta de pago» (F3) rechaza contratos sin cuenta (su historial exige cuenta anterior y el correo del cliente, y avisa al cliente).

Miguel: «solo quiero que pueda marcar los pagos» → botón «Asignar cuenta» en Pagos del portal. Solo administración (admin y superadmin vigentes). Solo contratos que NO tienen ninguna cuenta de pago. Solo cuentas vigentes del mismo cliente y de la misma moneda. Motivo obligatorio, SIN adjunto. Queda registrado quién, cuándo, cuál y por qué. No avisa al cliente.

## Decisiones a refutar
1. Operación nueva y separada de F3: constancia propia `crm.contrato_cuenta_pago_asignaciones` (sin claves foráneas, RLS sin políticas, sin permisos de API, no se modifica, no se borra, no se vacía, con bitácora). No se altera el historial de F3.
2. Puerta INVOKER `crm.asignar_cuenta_pago_contrato` → núcleo DEFINER `private.asignar_cuenta_pago_contrato_autorizado`; compuerta `private.admin_banca_vigente(auth.uid())` (la de F3), antes de cualquier lectura.
3. Candados en el orden de F3: cuenta FOR SHARE → contrato FOR SHARE → INSERT del vínculo (`creado_por` = actor). Dos asignaciones simultáneas: gana la unicidad por contrato; solo ESA violación se traduce a «ya tiene cuenta de pago»; cualquier otro 23505 sube tal cual.
4. Idempotencia por `p_solicitud_id` (candado consultivo + comparación de contrato, cuenta y motivo normalizado). La pantalla genera el id una vez por ventana y lo reusa al reintentar.
5. Solo contratos `activo` o `vencido`. No sella cuotas ya pagadas. Devuelve banco, moneda y los 4 últimos caracteres de la cuenta.
6. Reversa: sin asignaciones registradas y con las piezas intactas, retira todo; en cualquier otro caso NO borra nada y solo retira el EXECUTE (hay un guion para reabrir).
7. Portal: el botón solo se OFRECE a admin/superadmin (el servidor revalida); la lista de cuentas sale de la puerta existente `crm.cuentas_bancarias_cliente_fn`; sin preselección; el bloqueo de pago y de exportación no cambia; todo texto del servidor entra escapado o por `textContent`; si la puerta nueva no existe, mensaje claro y nada se rompe.
8. Seguimiento de tu ronda anterior (migración `20261001233019`): se añadió la exigencia de READ COMMITTED en la migración, la carga relanzable y las reversas; el ensayo ahora da PASA / FALLA / INCOMPLETO; la reversa exige que los triggers de sello cuelguen de su función. Se RECHAZÓ la lista fija de `session_user` (el canal del operador crea su propio rol de acceso) y se REFUTÓ el FK del sello (`crm.cuotas_cuenta_pagada` no tiene claves foráneas; medido además a dos sesiones: un pago en vuelo solo toma AccessShareLock sobre la tabla de cuentas y la migración no espera).

## Preguntas
a. ¿Puede asignar alguien que no sea admin/superadmin vigente (operaciones, analista, cliente, anon, `service_role`, admin revocado o desactivado, sesión sin `sub`)? Mira NULL y el ACL real tras `create function`.
b. ¿Algún camino deja vinculada una cuenta de otro cliente, de otra moneda, inactiva/retirada, o a un contrato que ya tenía cuenta o que está cerrado? ¿Qué pasa si entre la validación y el INSERT alguien retira la cuenta (F4), cambia cliente o moneda del contrato, o corre la carga automática (que toma `crm.cuentas_bancarias` en EXCLUSIVE y después el contrato FOR SHARE)?
c. ¿Algún abrazo mortal con un pago (trigger 00: contrato FOR UPDATE; bloqueo: vínculo y contrato FOR SHARE), con F3, con F4 o con el alta? ¿FOR SHARE sobre el contrato basta? ¿La función es segura si el llamador va en REPEATABLE READ?
d. ¿La idempotencia tiene un hueco (otro actor, misma solicitud con otro contrato, motivo que normaliza distinto en pantalla y en servidor)?
e. Constancia y reversa: ¿algo puede modificar, borrar o vaciar la constancia? ¿La reversa puede borrar algo usado o dejar la puerta abierta? ¿`reabrir-puerta.sql` puede abrir más de lo que había?
f. Portal: ¿algún camino permite pagar o exportar algo que antes se bloqueaba? ¿HTML del servidor sin escapar? ¿Doble envío? ¿Una respuesta tardía de una ventana ya cerrada puede asignar o pintar en otra? ¿Qué pasa con la sesión caducada? ¿La lectura directa `from('contratos').select('cliente_id')` es un problema?
g. Seguimiento: ¿la guarda de aislamiento y el veredicto de tres estados del ensayo están bien implementados? ¿Queda algún falso verde?
h. ¿Qué caso falta en las pruebas?

## Evidencia (lo que SÍ se ejecutó; nada en producción)
- **Hechos medidos** en un banco Docker con el esquema de producción de hoy (sin datos): md5 de `prosrc` de `private.admin_banca_vigente(uuid)` = `810dce30e37d1da9d913ef48ab6a4aa1` (DEFINER, EXECUTE solo `authenticated`), `private.trg_contrato_cuenta_pago_coherente()` = `7e946a5af78a827c18ee5b218896f24c`, `private.trg_registro_cuenta_pago_no_borrar()` = `e95919db53c44ff1fe6632c346f27a06`. Triggers de `crm.contrato_cuentas_pago`: `trg_audit_contrato_cuentas_pago` (AFTER I/U/D), `trg_contrato_cuenta_pago_00_inmutable` (BEFORE UPDATE), `trg_contrato_cuenta_pago_coherente` (BEFORE INSERT/UPDATE); `contrato_id` es UNIQUE; la tabla solo tiene `select, insert` para `service_role`. Existe un vigía diario que exige bitácora completa en toda tabla `crm.*`.
- **Servidor de «asignar»**: las pruebas de banco (prueba sintética, ciclo aplicar/repetir/revertir/reabrir, mutantes y concurrencia a dos sesiones) están EN CURSO al escribir este encargo: NOT RUN todavía. No las des por hechas.
- **Auditor interno (auditor-rls)** sobre la migración de «asignar»: CHANGES_REQUESTED sin P0; no pudo tumbar la autorización, la coherencia del vínculo ni los candados. ACEPTADO y ya aplicado: escapes visibles `\\uXXXX` en la regla del motivo (antes eran caracteres invisibles; misma clase que F3/F4); traducir solo la violación de unicidad del vínculo; candado de TRUNCATE; veredicto fijado dentro de la transacción; retorno con los 4 últimos caracteres y mismas claves en la repetición; reversa que solo protege con huellas el BORRADO y siempre puede cerrar; guion para reabrir; preflight de triggers por función e índice único válido; sin índices sin lector; fila del ledger con el OK de Miguel. ANOTADO como riesgo previo fuera de este cambio: `service_role` conserva INSERT directo sobre `crm.contrato_cuentas_pago` (20260803221622) y el trigger de coherencia no exige cuenta vigente; ninguna Edge Function del repo escribe ahí.
- **Matriz HTTP (`test-rls.mjs`)**: se añadieron sondas de la puerta (denegado: analista, rol global, cliente, admin revocado, admin desactivado, anon; administración llega al núcleo y se queda en la validación del motivo, sin escribir), con salto ruidoso si la base no tiene la migración (`CRM_RLS_EXIGE_CUENTAS_PAGO=1` lo vuelve fallo). `node --check` y `--preflight` sin conexión: PASS. La matriz completa por HTTP: NOT RUN. No hay sesión `operaciones` ni `superadmin` en ese fixture (cubiertas en el banco).
- **Portal** (worktree propio, sin publicar): suite completa en la disposición real de carpetas 199/199 (línea base publicada: 164/164); pruebas nuevas 46/46; mutantes de las pruebas versionadas 119/119 muertos. Banco de comportamiento con jsdom ejecutando el `pagos.js` real contra un Supabase falso (54 comprobaciones; 55 con supabase-js real): rol (admin sí, operaciones no), éxito, error del servidor, sin cuentas, función ausente, doble clic, reintento con el mismo id, respuesta perdida, fila desbloqueada y pago posterior, cuentas que llegan tarde de una ventana ya cerrada; con HTML hostil en frase, caso, número de contrato, cliente, cuentas, error y respuesta de éxito no se crea ningún elemento. Sus mutantes: 57/57 muertos. Con la puerta de motivos ausente, el HTML de agenda y tabla es idéntico al publicado. NOT RUN: navegador contra Supabase real.
- **Seguimiento de la ronda anterior (migración `20261001233019`)**: antes de los cambios, ciclo del banco 273 pasos / 0 fallos. Tras tus hallazgos se cambió lo descrito en la decisión 8; la repetición del ciclo con la guarda de aislamiento, el ensayo en sus tres estados y las pruebas a dos sesiones de pagos en vuelo está EN CURSO. Parcial ya medido: un pago en vuelo de un contrato `ok` solo tiene AccessShareLock sobre `crm.cuentas_bancarias` y la migración no espera (0,1 s).

## Huecos declarados
- Sin navegador real ni PostgREST real: la API se simula por sesión en el banco y con un doble en el portal.
- La ventana lee el cliente del contrato con `from('contratos').select('cliente_id')` cuando abre desde la tabla por contrato (la consulta paginada no lo trae).
- Si después de asignar se corrige la FECHA de una cuota pagada antes, el sello existente (F5) la marca «inferido» en la cuenta asignada (comportamiento previo).
- Una asignación equivocada solo se corrige con «Cambiar cuenta de pago» (F3: correo del cliente y aviso).
- El motivo queda en claro en `public.audit_log` (igual que F3 y F4); la ventana pide no escribir números de cuenta, CCI ni documentos.

## Archivos

### supabase/migrations/20261002005004_crm_asignar_cuenta_pago.sql (NUEVA, completa)
```sql
-- Cuentas de pago · ASIGNAR la cuenta de pago a un contrato que no tiene ninguna (02/10/2026).
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
        'ultimos', (select pg_catalog.right(cb.numero_cuenta, 4) from crm.cuentas_bancarias cb
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
    'ultimos', pg_catalog.right(v_cuenta.numero_cuenta, 4));
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
          and t.tgname in ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
                           'trg_contrato_cuenta_pago_asignaciones_00_inmutable',
                           'trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar')
          and t.tgenabled = 'O') <> 3 then
    raise exception 'ASIGNAR POSTFLIGHT: la bitácora o los candados de la constancia no quedaron como se espera';
  end if;
  -- Forma, cuerpo, EXECUTE exacto (rol NULL = solo su dueño), search_path vacío y comentario.
  for v_f in
    select * from (values
      ('private.trg_contrato_cuenta_pago_asignaciones_inmutable()', null, true, '49bb93b9429aa7b0c168cc8ceb43acfc'),
      ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)', 'authenticated', true, 'c636b7394d82f9659cad78da2d3a301a'),
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
  perform pg_catalog.set_config('crm.asignar_cuenta_pago_resultado', 'ASIGNAR_CUENTA_PAGO_OK', false);
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila (el canal de `db query` no transporta los avisos) y solo existe si
-- la transacción de arriba se confirmó.
select pg_catalog.current_setting('crm.asignar_cuenta_pago_resultado', true) as resultado;
```

### supabase/scripts/cuentas-pago-asignar/reversa.sql (NUEVA, completa)
```sql
-- REVERSA de 20261002005004_crm_asignar_cuenta_pago.
--   · Si NO hay ninguna asignación registrada y las piezas son las de la migración: deja todo
--     como antes (quita la puerta, el núcleo, el candado y la tabla de constancias, que está vacía).
--   · En cualquier otro caso NO borra nada: solo CIERRA la puerta (retira el permiso de
--     ejecutar), para que nadie asigne más. Las constancias y los vínculos que crearon son
--     instrucciones de pago en uso. Cerrar es siempre seguro, por eso no exige que las piezas
--     sigan siendo las de la migración. Para reabrir: reabrir-puerta.sql.
-- No toca ningún vínculo en ningún caso.
-- Límite conocido: una asignación que ya había empezado cuando se lanza la reversa espera a que
-- esta termine y luego se completa (el permiso se comprueba al entrar). Si el veredicto dice
-- PUERTA_CERRADA, vuelve a contar las asignaciones un minuto después.
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $reversa$
declare
  v_asignaciones bigint;
  v_intactas boolean;
begin
  -- Se cuenta DESPUÉS de tomar el candado de la tabla: eso solo vale en READ COMMITTED (con una
  -- fotografía anterior al candado se podría borrar una tabla que ya tiene una asignación).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is null
     or pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is null
     or pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is null then
    raise exception 'REVERSA ASIGNAR: la migración 20261002005004 no está aplicada; no hay nada que revertir';
  end if;

  -- Nadie asigna mientras se decide: la asignación escribe en esta tabla.
  lock table crm.contrato_cuenta_pago_asignaciones in access exclusive mode;
  select pg_catalog.count(*) into v_asignaciones from crm.contrato_cuenta_pago_asignaciones;

  v_intactas :=
    (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
     where p.oid = 'private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'::regprocedure)
      = 'c636b7394d82f9659cad78da2d3a301a'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = 'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'::regprocedure)
      = '46e03517fc68ffd79fed6892d1128c2b'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = 'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure)
      = '49bb93b9429aa7b0c168cc8ceb43acfc';

  if v_asignaciones = 0 and v_intactas then
    execute 'drop function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)';
    execute 'drop function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)';
    execute 'drop table crm.contrato_cuenta_pago_asignaciones';
    execute 'drop function private.trg_contrato_cuenta_pago_asignaciones_inmutable()';
    if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null
       or pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is not null
       or pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is not null
       or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is not null then
      raise exception 'REVERSA ASIGNAR: quedó alguna pieza de la migración';
    end if;
    perform pg_catalog.set_config('crm.reversa_asignar_resultado',
      'RETIRADA: sin asignaciones registradas; se quitaron la puerta, el núcleo, el candado y la tabla', false);
  else
    execute 'revoke all on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) from public, anon, authenticated, service_role';
    execute 'revoke all on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) from public, anon, authenticated, service_role';
    if pg_catalog.has_function_privilege('authenticated', 'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)', 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', 'private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)', 'EXECUTE') then
      raise exception 'REVERSA ASIGNAR: la puerta no quedó cerrada';
    end if;
    perform pg_catalog.set_config('crm.reversa_asignar_resultado',
      pg_catalog.format('PUERTA_CERRADA: %s asignaciones conservadas; no se borró nada%s', v_asignaciones,
        case when v_intactas then '' else ' (las piezas cambiaron después de la migración)' end), false);
  end if;
end;
$reversa$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila.
select pg_catalog.current_setting('crm.reversa_asignar_resultado', true) as resultado;
```

### supabase/scripts/cuentas-pago-asignar/reabrir-puerta.sql (NUEVA, completa)
```sql
-- REABRIR la puerta de «Asignar cuenta de pago» después de haberla cerrado con reversa.sql.
-- Solo devuelve el permiso de ejecutar a authenticated en la puerta y en su núcleo (la compuerta
-- de administración sigue dentro del núcleo). Se niega si las piezas no son las de la migración
-- 20261002005004: no se reabre una puerta que alguien cambió sin revisarla.
-- Solo Miguel, con autorización expresa.
begin;
set local lock_timeout = '5s';

do $reabrir$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
       is distinct from 'c636b7394d82f9659cad78da2d3a301a'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'))
       is distinct from '46e03517fc68ffd79fed6892d1128c2b'
     or pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is null then
    raise exception 'REABRIR ASIGNAR: las piezas vivas no son las de la migración 20261002005004; no se reabre';
  end if;
  execute 'grant execute on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) to authenticated';
  execute 'grant execute on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) to authenticated';
  if exists (
    select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
    where p.oid in ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'::regprocedure,
                    'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'::regprocedure)
      and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
      and a.grantee <> 'authenticated'::regrole::oid
  ) then
    raise exception 'REABRIR ASIGNAR: quedó un permiso de ejecutar de más';
  end if;
  perform pg_catalog.set_config('crm.reabrir_asignar_resultado', 'PUERTA_REABIERTA', false);
end;
$reabrir$;

notify pgrst, 'reload schema';
commit;

select pg_catalog.current_setting('crm.reabrir_asignar_resultado', true) as resultado;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260926204051_crm_cambio_cuenta_pago.sql líneas 105-122 (F3: la compuerta private.admin_banca_vigente)
```sql
  105  -- ── 0. Compuerta común: admin o superadmin activo y con la membresía CRM no revocada (P04) ─────
  106  create function private.admin_banca_vigente(p_uid uuid)
  107  returns boolean
  108  language sql
  109  stable
  110  security definer
  111  set search_path to ''
  112  as $function$
  113    select p_uid is not null
  114       and exists (
  115         select 1 from public.perfiles p
  116         where p.id = p_uid and p.rol in ('admin', 'superadmin') and p.activo is true)
  117       and not exists (
  118         select 1 from crm.equipo e
  119         where e.perfil_id = p_uid and e.activo is false);
  120  $function$;
  121  revoke all on function private.admin_banca_vigente(uuid) from public, anon, authenticated, service_role;
  122  grant execute on function private.admin_banca_vigente(uuid) to authenticated;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260926204051_crm_cambio_cuenta_pago.sql líneas 180-199 (F3: candado «no se borra» que la constancia nueva reutiliza)
```sql
  180  -- Candados de los registros: nada se borra; el historial solo sella el aviso; el sello solo se
  181  -- re-sella (una cuota que vuelve a pagarse tras una anulación).
  182  create function private.trg_registro_cuenta_pago_no_borrar()
  183  returns trigger
  184  language plpgsql
  185  security definer
  186  set search_path to ''
  187  as $function$
  188  begin
  189    raise exception using errcode = '22023',
  190      message = 'Los registros de cuentas de pago no se borran';
  191  end;
  192  $function$;
  193  revoke all on function private.trg_registro_cuenta_pago_no_borrar() from public, anon, authenticated, service_role;
  194  create trigger trg_cuotas_cuenta_pagada_00_no_borrar before delete on crm.cuotas_cuenta_pagada
  195    for each row execute function private.trg_registro_cuenta_pago_no_borrar();
  196  create trigger trg_contrato_cuenta_pago_cambios_00_no_borrar before delete on crm.contrato_cuenta_pago_cambios
  197    for each row execute function private.trg_registro_cuenta_pago_no_borrar();
  198  create trigger trg_cambio_cuenta_avisos_00_no_borrar before delete on crm.cambio_cuenta_avisos
  199    for each row execute function private.trg_registro_cuenta_pago_no_borrar();
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260927020317_crm_cuentas_gloria_motivo_y_cuenta_retirada.sql líneas 61-249 (F3: núcleo vigente del CAMBIO de cuenta (el molde: validaciones y orden de candados))
```sql
   61  create or replace function private.cambiar_cuenta_pago_contratos_autorizado(
   62    p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_nueva_id uuid,
   63    p_contrato_ids uuid[], p_motivo text, p_respaldo_ruta text)
   64  returns jsonb
   65  language plpgsql
   66  security definer
   67  set search_path to ''
   68  as $function$
   69  declare
   70    v_actor uuid := (select auth.uid());
   71    v_ids uuid[];
   72    v_motivo text := pg_catalog.regexp_replace(coalesce(p_motivo, ''), '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g');
   73    v_previos integer;
   74    v_igual boolean;
   75    v_prev_ids uuid[];
   76    v_cuenta crm.cuentas_bancarias%rowtype;
   77    v_obj storage.objects%rowtype;
   78    v_ct record;
   79    v_contados integer := 0;
   80    v_hechos integer;
   81    v_etag text;
   82    v_en_curso text;
   83  begin
   84    if not coalesce(private.admin_banca_vigente(v_actor), false) then
   85      raise exception using errcode = '42501',
   86        message = 'Solo administración puede cambiar la cuenta de pago';
   87    end if;
   88    if p_solicitud_id is null or p_cliente_id is null or p_cuenta_nueva_id is null then
   89      raise exception using errcode = '22023', message = 'Faltan datos del cambio';
   90    end if;
   91    v_ids := array(select distinct x from pg_catalog.unnest(p_contrato_ids) x where x is not null order by x);
   92    if coalesce(pg_catalog.cardinality(v_ids), 0) = 0
   93       or pg_catalog.cardinality(v_ids) <> coalesce(pg_catalog.cardinality(p_contrato_ids), 0)
   94       or pg_catalog.cardinality(v_ids) > 100 then
   95      raise exception using errcode = '22023', message = 'Elige entre 1 y 100 contratos, sin repetir';
   96    end if;
   97    if pg_catalog.length(pg_catalog.regexp_replace(v_motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) < 5
   98       or pg_catalog.length(v_motivo) > 500 then
   99      raise exception using errcode = '22023', message = 'Escribe el motivo del cambio (5 a 500 caracteres)';
  100    end if;
  101  
  102    -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con datos
  103    -- distintos (cuenta, contratos, motivo o respaldo) se rechaza.
  104    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cambio-cuenta:' || p_solicitud_id::text, 0));
  105    select count(*),
  106           bool_and(c.cliente_id = p_cliente_id and c.cuenta_nueva_id = p_cuenta_nueva_id
  107                    and c.motivo = v_motivo and c.respaldo_ruta = p_respaldo_ruta),
  108           array_agg(c.contrato_id order by c.contrato_id)
  109      into v_previos, v_igual, v_prev_ids
  110    from crm.contrato_cuenta_pago_cambios c
  111    where c.solicitud_id = p_solicitud_id;
  112    if v_previos > 0 then
  113      if v_igual and v_prev_ids = v_ids then
  114        return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true,
  115          'contratos', v_previos);
  116      end if;
  117      raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  118    end if;
  119  
  120    -- Respaldo: el correo del cliente, en su carpeta, subido por este mismo admin y sin usar en otra
  121    -- solicitud (el segundo candado serializa dos solicitudes que intenten el mismo archivo).
  122    if p_respaldo_ruta is null
  123       or pg_catalog.split_part(p_respaldo_ruta, '/', 1) is distinct from p_cliente_id::text
  124       or not coalesce(p_respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false) then
  125      raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  126    end if;
  127    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-cambio-cuenta:' || p_respaldo_ruta, 0));
  128    select * into v_obj from storage.objects
  129    where bucket_id = 'respaldos-cambio-cuenta' and name = p_respaldo_ruta;
  130    if not found
  131       or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
  132       or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
  133      raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  134    end if;
  135    if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then
  136      raise exception using errcode = '22023', message = 'El respaldo debe subirlo quien hace el cambio';
  137    end if;
  138    if exists (select 1 from crm.contrato_cuenta_pago_cambios c
  139               where c.respaldo_ruta = p_respaldo_ruta and c.solicitud_id <> p_solicitud_id) then
  140      raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
  141    end if;
  142    -- El mismo archivo subido otra vez con otra ruta tampoco vale: se compara la huella del
  143    -- contenido que calcula Storage (eTag), no un dato del navegador.
  144    v_etag := nullif(pg_catalog.btrim(v_obj.metadata->>'eTag', '"'), '');
  145    if v_etag is not null then
  146      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-etag:' || v_etag, 0));
  147      if exists (select 1 from crm.contrato_cuenta_pago_cambios c
  148                 join storage.objects o on o.bucket_id = 'respaldos-cambio-cuenta' and o.name = c.respaldo_ruta
  149                 where c.solicitud_id <> p_solicitud_id
  150                   and pg_catalog.btrim(o.metadata->>'eTag', '"') = v_etag) then
  151        raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
  152      end if;
  153    end if;
  154  
  155    -- Cuenta nueva: del cliente y vigente.
  156    select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_nueva_id for share;
  157    if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
  158      raise exception using errcode = '22023', message = 'La cuenta nueva no es de este cliente';
  159    end if;
  160    if not v_cuenta.activa then
  161      raise exception using errcode = '22023', message = 'La cuenta nueva ya no está vigente';
  162    end if;
  163  
  164    -- Contratos (se bloquean antes que los enlaces, como al registrar un pago): del cliente,
  165    -- abiertos y en la moneda de la cuenta.
  166    for v_ct in
  167      select ct.id, ct.cliente_id, ct.moneda, ct.estado, ct.numero_contrato
  168      from public.contratos ct
  169      where ct.id = any(v_ids)
  170      order by ct.id
  171      for share
  172    loop
  173      if v_ct.cliente_id is distinct from p_cliente_id then
  174        raise exception using errcode = '22023',
  175          message = pg_catalog.format('El contrato %s no es de este cliente', v_ct.numero_contrato);
  176      end if;
  177      if v_ct.estado not in ('activo', 'vencido') then
  178        raise exception using errcode = '22023',
  179          message = pg_catalog.format('El contrato %s está cerrado (%s)', v_ct.numero_contrato, v_ct.estado);
  180      end if;
  181      if v_ct.moneda is distinct from v_cuenta.moneda then
  182        raise exception using errcode = '22023',
  183          message = pg_catalog.format('El contrato %s es en %s y la cuenta nueva en %s',
  184            v_ct.numero_contrato, v_ct.moneda, v_cuenta.moneda);
  185      end if;
  186      v_contados := v_contados + 1;
  187    end loop;
  188    if v_contados <> pg_catalog.cardinality(v_ids) then
  189      raise exception using errcode = '22023', message = 'Algún contrato no existe';
  190    end if;
  191    perform 1 from crm.contrato_cuentas_pago l where l.contrato_id = any(v_ids) order by l.contrato_id for update;
  192  
  193    -- Un aviso al cliente en curso para estos contratos (reservado y sin confirmar): si el cambio
  194    -- entrara ahora, ese aviso anunciaría una cuenta que este cambio deja atrás. Con los enlaces ya
  195    -- bloqueados, toda reserva hecha antes está confirmada en la base y se ve aquí.
  196    select ct.numero_contrato into v_en_curso
  197    from crm.contrato_cuenta_pago_cambios c
  198    join crm.cambio_cuenta_avisos av on av.solicitud_id = c.solicitud_id
  199    join public.contratos ct on ct.id = c.contrato_id
  200    where c.contrato_id = any(v_ids)
  201      and av.reserva is not null
  202      and av.reclamado_en > pg_catalog.clock_timestamp() - interval '10 minutes'
  203    order by ct.numero_contrato
  204    limit 1;
  205    if v_en_curso is not null then
  206      raise exception using errcode = '22023',
  207        message = pg_catalog.format('Se está enviando al cliente el aviso de un cambio anterior del contrato %s; espera unos segundos y vuelve a intentar', v_en_curso);
  208    end if;
  209  
  210    -- Enlaces actuales: cada contrato debe tener cuenta de pago y no ser ya la nueva.
  211    for v_ct in
  212      select ct.numero_contrato, l.cuenta_bancaria_id
  213      from public.contratos ct
  214      left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
  215      where ct.id = any(v_ids)
  216      order by ct.id
  217    loop
  218      if v_ct.cuenta_bancaria_id is null then
  219        raise exception using errcode = '22023',
  220          message = pg_catalog.format('El contrato %s no tiene cuenta de pago; requiere conciliación', v_ct.numero_contrato);
  221      end if;
  222      if v_ct.cuenta_bancaria_id = p_cuenta_nueva_id then
  223        raise exception using errcode = '22023',
  224          message = pg_catalog.format('El contrato %s ya cobra en esa cuenta', v_ct.numero_contrato);
  225      end if;
  226    end loop;
  227  
  228    -- Primero la historia; luego el enlace (el candado exige esa historia en esta transacción).
  229    insert into crm.contrato_cuenta_pago_cambios
  230      (solicitud_id, contrato_id, cliente_id, cuenta_anterior_id, cuenta_nueva_id,
  231       motivo, respaldo_ruta, cambiado_por)
  232    select p_solicitud_id, l.contrato_id, p_cliente_id, l.cuenta_bancaria_id, p_cuenta_nueva_id,
  233           v_motivo, p_respaldo_ruta, v_actor
  234    from crm.contrato_cuentas_pago l
  235    where l.contrato_id = any(v_ids);
  236  
  237    update crm.contrato_cuentas_pago
  238       set cuenta_bancaria_id = p_cuenta_nueva_id
  239     where contrato_id = any(v_ids);
  240    get diagnostics v_hechos = row_count;
  241    if v_hechos <> pg_catalog.cardinality(v_ids) then
  242      raise exception 'CAMBIO_CUENTA: se esperaban % enlaces y se cambiaron %', pg_catalog.cardinality(v_ids), v_hechos;
  243    end if;
  244  
  245    return pg_catalog.jsonb_build_object(
  246      'solicitud_id', p_solicitud_id, 'ya_aplicada', false, 'contratos', v_hechos,
  247      'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda);
  248  end;
  249  $function$;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260803221622_crm_cuentas_bancarias_por_contrato.sql líneas 171-257 (el vínculo, su unicidad por contrato y el trigger de coherencia)
```sql
  171  -- ── 2) Enlace exacto contrato → cuenta ──────────────────────────────────────
  172  
  173  create table crm.contrato_cuentas_pago (
  174    id                  uuid primary key default gen_random_uuid(),
  175    contrato_id         uuid not null unique
  176                        references public.contratos(id) on delete cascade,
  177    cuenta_bancaria_id  uuid not null
  178                        references crm.cuentas_bancarias(id) on delete restrict,
  179    creado_por          uuid references public.perfiles(id) on delete set null,
  180    creado_en           timestamptz not null default now()
  181  );
  182  
  183  alter table crm.contrato_cuentas_pago enable row level security;
  184  
  185  comment on table crm.contrato_cuentas_pago is
  186    'Cuenta bancaria fija para todos los desembolsos del contrato (intereses, devoluciones y retorno de capital). Una fila por contrato.';
  187  
  188  create index contrato_cuentas_pago_cuenta_idx
  189    on crm.contrato_cuentas_pago (cuenta_bancaria_id);
  190  create index contrato_cuentas_pago_creado_por_idx
  191    on crm.contrato_cuentas_pago (creado_por)
  192    where creado_por is not null;
  193  
  194  create or replace function private.trg_contrato_cuenta_pago_inmutable()
  195  returns trigger
  196  language plpgsql
  197  security definer
  198  set search_path = ''
  199  as $$
  200  begin
  201    if row(new.id, new.contrato_id, new.cuenta_bancaria_id, new.creado_en)
  202       is distinct from
  203       row(old.id, old.contrato_id, old.cuenta_bancaria_id, old.creado_en) then
  204      raise exception using
  205        errcode = '22023',
  206        message = 'La cuenta de pago del contrato es historica y no se reemplaza';
  207    end if;
  208    if new.creado_por is distinct from old.creado_por
  209       and not (
  210         new.creado_por is null
  211         and old.creado_por is not null
  212         and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
  213       ) then
  214      raise exception using errcode = '22023', message = 'La autoria del enlace bancario es inmutable';
  215    end if;
  216    return new;
  217  end;
  218  $$;
  219  
  220  create trigger trg_contrato_cuenta_pago_00_inmutable
  221    before update on crm.contrato_cuentas_pago
  222    for each row execute function private.trg_contrato_cuenta_pago_inmutable();
  223  
  224  -- Defensa estructural aun frente a una escritura privilegiada: la cuenta debe
  225  -- pertenecer al MISMO cliente y moneda del contrato. El cliente API no tiene
  226  -- grants directos sobre esta tabla; la insercion normal va por la RPC atomica.
  227  create or replace function private.trg_contrato_cuenta_pago_coherente()
  228  returns trigger
  229  language plpgsql
  230  security definer
  231  set search_path = ''
  232  as $$
  233  begin
  234    if not exists (
  235      select 1
  236      from public.contratos ct
  237      join crm.cuentas_bancarias cb
  238        on cb.id = new.cuenta_bancaria_id
  239       and cb.cliente_id = ct.cliente_id
  240       and cb.moneda = ct.moneda
  241      where ct.id = new.contrato_id
  242    ) then
  243      raise exception using
  244        errcode = '23514',
  245        message = 'La cuenta bancaria no pertenece al cliente o a la moneda del contrato';
  246    end if;
  247    return new;
  248  end;
  249  $$;
  250  
  251  create trigger trg_contrato_cuenta_pago_coherente
  252    before insert or update on crm.contrato_cuentas_pago
  253    for each row execute function private.trg_contrato_cuenta_pago_coherente();
  254  
  255  create trigger trg_audit_contrato_cuentas_pago
  256    after insert or delete or update on crm.contrato_cuentas_pago
  257    for each row execute function private.log_audit_crm();
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260803221622_crm_cuentas_bancarias_por_contrato.sql líneas 762-772 (permisos de tabla del vínculo y de las cuentas)
```sql
  762  -- ── 8) Grants y hardening ──────────────────────────────────────────────────
  763  
  764  -- Las tablas sensibles quedan deny-by-default para sesiones humanas. Toda
  765  -- lectura/escritura pasa por una RPC con gate y payload recortado.
  766  revoke all on table crm.cuentas_bancarias from public, anon, authenticated;
  767  revoke all on table crm.contrato_cuentas_pago from public, anon, authenticated;
  768  grant select, insert, update on crm.cuentas_bancarias to service_role;
  769  grant select, insert on crm.contrato_cuentas_pago to service_role;
  770  
  771  revoke all on function crm.cuentas_bancarias_cliente_fn(uuid, text) from public, anon;
  772  grant execute on function crm.cuentas_bancarias_cliente_fn(uuid, text) to authenticated;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260927012948_crm_retirar_cuenta_cliente.sql líneas 150-260 (F4: retiro de una cuenta (candados y la regla «cobra contratos abiertos»))
```sql
  150    v_quien text;
  151  begin
  152    if not coalesce(private.admin_banca_vigente(v_actor), false) then
  153      raise exception using errcode = '42501', message = 'Solo administración puede retirar cuentas bancarias';
  154    end if;
  155    if p_solicitud_id is null or p_cliente_id is null or p_cuenta_id is null then
  156      raise exception using errcode = '22023', message = 'Faltan datos del retiro';
  157    end if;
  158    if pg_catalog.length(pg_catalog.regexp_replace(v_motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) < 5
  159       or pg_catalog.length(v_motivo) > 500 then
  160      raise exception using errcode = '22023', message = 'Escribe el motivo del retiro (5 a 500 caracteres)';
  161    end if;
  162  
  163    -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con otros
  164    -- datos se rechaza. Va antes de mirar la cuenta, que tras el primer intento ya está retirada.
  165    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('retiro-cuenta:' || p_solicitud_id::text, 0));
  166    select * into v_previo from crm.cuentas_bancarias_retiros where solicitud_id = p_solicitud_id;
  167    if found then
  168      if v_previo.cuenta_id = p_cuenta_id and v_previo.cliente_id = p_cliente_id
  169         and v_previo.motivo = v_motivo and v_previo.respaldo_ruta is not distinct from v_ruta then
  170        return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true,
  171          'cuenta_id', p_cuenta_id);
  172      end if;
  173      raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  174    end if;
  175  
  176    -- La cuenta: del cliente y vigente. Bloqueo exclusivo: un alta de contrato o un cambio de F3
  177    -- que la elijan esperan a este retiro y después la ven retirada.
  178    select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_id for update;
  179    if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
  180      raise exception using errcode = '22023', message = 'La cuenta no es de este cliente';
  181    end if;
  182    if not v_cuenta.activa then
  183      select pr.nombre_completo into v_quien
  184      from public.perfiles pr
  185      where pr.id = v_cuenta.desactivada_por and pr.rol <> 'cliente';
  186      if exists (select 1 from crm.cuentas_bancarias_retiros r where r.cuenta_id = p_cuenta_id) then
  187        raise exception using errcode = '22023',
  188          message = pg_catalog.format('La cuenta ya fue retirada el %s%s',
  189            pg_catalog.to_char(v_cuenta.desactivada_en at time zone 'America/Lima', 'DD/MM/YYYY'),
  190            case when v_quien is not null then ' por ' || v_quien else '' end);
  191      end if;
  192      -- Desactivada por una corrección de datos (nueva versión) u otra vía: no fue un «retiro».
  193      raise exception using errcode = '22023',
  194        message = pg_catalog.format('La cuenta ya no está vigente desde el %s: se reemplazó por una versión corregida',
  195          pg_catalog.to_char(v_cuenta.desactivada_en at time zone 'America/Lima', 'DD/MM/YYYY'));
  196    end if;
  197  
  198    -- Contratos abiertos que todavía cobran en esta cuenta FÍSICA (mismo cliente, moneda y CCI): una
  199    -- cuenta corregida deja versiones viejas, inactivas pero todavía enlazadas a sus contratos, y el
  200    -- registro de pagos las acepta como instrucción contractual. Primero se cambia su cuenta de pago
  201    -- (F3). Ninguna vía crea enlaces hacia versiones inactivas (alta y F3 exigen activa bajo bloqueo):
  202    -- los enlaces viejos solo pueden irse, y eso falla cerrado.
  203    select pg_catalog.array_agg(ct.numero_contrato order by ct.numero_contrato) into v_abiertos
  204    from crm.contrato_cuentas_pago l
  205    join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  206    join public.contratos ct on ct.id = l.contrato_id
  207    where cb.cliente_id = v_cuenta.cliente_id
  208      and cb.moneda = v_cuenta.moneda
  209      and cb.cci = v_cuenta.cci
  210      and ct.estado in ('activo', 'vencido');
  211    if coalesce(pg_catalog.cardinality(v_abiertos), 0) > 0 then
  212      raise exception using errcode = '22023', detail = 'contratos_abiertos',
  213        message = pg_catalog.format('La cuenta todavía cobra %s %s. Primero cambia su cuenta de pago',
  214          case when pg_catalog.cardinality(v_abiertos) = 1 then 'el contrato' else 'los contratos' end,
  215          pg_catalog.array_to_string(v_abiertos, ', '));
  216    end if;
  217  
  218    -- Respaldo opcional: si viene, el correo del cliente en su carpeta, subido por este mismo admin.
  219    -- Puede ser el mismo correo de un cambio de F3 («cambien mi cuenta y retiren la vieja»).
  220    if v_ruta is not null then
  221      if pg_catalog.split_part(v_ruta, '/', 1) is distinct from p_cliente_id::text
  222         or not coalesce(v_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false) then
  223        raise exception using errcode = '22023', message = 'El respaldo no es un archivo válido de este cliente';
  224      end if;
  225      select * into v_obj from storage.objects
  226      where bucket_id = 'respaldos-cambio-cuenta' and name = v_ruta;
  227      if not found
  228         or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
  229         or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
  230        raise exception using errcode = '22023', message = 'El respaldo no es un archivo válido de este cliente';
  231      end if;
  232      if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then
  233        raise exception using errcode = '22023', message = 'El respaldo debe subirlo quien retira la cuenta';
  234      end if;
  235    end if;
  236  
  237    update crm.cuentas_bancarias
  238       set activa = false,
  239           desactivada_por = v_actor,
  240           desactivada_en = pg_catalog.now()
  241     where id = p_cuenta_id;
  242    insert into crm.cuentas_bancarias_retiros
  243      (solicitud_id, cuenta_id, cliente_id, moneda, motivo, respaldo_ruta, retirado_por, retirado_en)
  244    values
  245      (p_solicitud_id, p_cuenta_id, p_cliente_id, v_cuenta.moneda, v_motivo, v_ruta, v_actor, pg_catalog.now());
  246  
  247    return pg_catalog.jsonb_build_object(
  248      'solicitud_id', p_solicitud_id, 'ya_aplicada', false, 'cuenta_id', p_cuenta_id,
  249      'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda,
  250      'ultimos', pg_catalog.right(v_cuenta.numero_cuenta, 4));
  251  end;
  252  $function$;
  253  revoke all on function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)
  254    from public, anon, authenticated, service_role;
  255  grant execute on function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text) to authenticated;
  256  
  257  create function crm.retirar_cuenta_cliente(
  258    p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_id uuid, p_motivo text, p_respaldo_ruta text default null)
  259  returns jsonb
  260  language sql
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260927024423_crm_pago_declara_cuenta.sql líneas 61-190 (F5: sello de la cuenta de cada cuota y crm.registrar_pago_con_cuenta)
```sql
   61  create or replace function private.sellar_cuenta_cuota_pagada()
   62  returns trigger
   63  language plpgsql
   64  security definer
   65  set search_path to ''
   66  as $function$
   67  declare
   68    v_cuenta uuid;
   69    v_cci text := nullif(pg_catalog.current_setting('crm.cci_deposito', true), '');
   70    v_testigo text := nullif(pg_catalog.current_setting('crm.cci_deposito_testigo', true), '');
   71    v_nuevo_pago boolean := tg_op = 'INSERT';
   72    v_origen_previo text;
   73  begin
   74    -- Procedencia: la declaración solo vale si la armó crm.registrar_pago_con_cuenta en ESTA
   75    -- transacción (testigo = md5 del txid + CCI). Un CCI fijado a mano sin la RPC se ignora.
   76    if v_cci is not null and v_testigo is distinct from pg_catalog.md5(pg_catalog.txid_current()::text || '|' || v_cci) then
   77      raise exception using errcode = '22023',
   78        message = 'La cuenta del depósito solo se declara por crm.registrar_pago_con_cuenta';
   79    end if;
   80    if not v_nuevo_pago then
   81      v_nuevo_pago := old.estado is distinct from 'pagado';
   82    end if;
   83    -- Corrección de la fecha de una cuota ya pagada: solo se recalcula un sello deducido por la
   84    -- fecha ('registro'); lo declarado y lo inferido no dependen de ella.
   85    if not v_nuevo_pago then
   86      select q.origen into v_origen_previo from crm.cuotas_cuenta_pagada q where q.cuota_id = new.id;
   87      -- Sin sello previo (cuota pagada antes de tener cuenta de pago): se sella como 'inferido'.
   88      if v_origen_previo is not null and v_origen_previo <> 'registro' then
   89        return null;
   90      end if;
   91    end if;
   92  
   93    if v_nuevo_pago and v_cci is not null then
   94      -- Quien registra DECLARÓ a qué cuenta depositó (el CCI del Excel o la cuenta que mostró el
   95      -- modal): esa es la constancia. Solo vale una cuenta que sea o haya sido cuenta de pago de
   96      -- ESTE contrato (enlace actual o historial de cambios), en cualquiera de sus versiones
   97      -- (mismo cliente, moneda y CCI). Otro CCI del cliente se rechaza: un depósito fuera de la
   98      -- instrucción de pago es una anomalía, no una constancia.
   99      select cb.id into v_cuenta
  100      from crm.cuentas_bancarias cb
  101      join public.contratos ct on ct.id = new.contrato_id
  102      where cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda
  103        and pg_catalog.regexp_replace(cb.cci, '\D', '', 'g') = v_cci
  104        and exists (
  105          select 1 from crm.cuentas_bancarias ref
  106          where ref.id in (
  107            select l.cuenta_bancaria_id from crm.contrato_cuentas_pago l where l.contrato_id = new.contrato_id
  108            union
  109            select c.cuenta_anterior_id from crm.contrato_cuenta_pago_cambios c where c.contrato_id = new.contrato_id
  110            union
  111            select c.cuenta_nueva_id from crm.contrato_cuenta_pago_cambios c where c.contrato_id = new.contrato_id)
  112            and ref.cliente_id = cb.cliente_id and ref.moneda = cb.moneda and ref.cci = cb.cci)
  113      order by cb.activa desc, cb.creado_en desc
  114      limit 1;
  115      if v_cuenta is null then
  116        raise exception using errcode = '22023',
  117          message = 'El CCI del depósito no es de una cuenta de pago de este contrato';
  118      end if;
  119    else
  120      -- Sin declaración: la cuenta vigente en la FECHA del pago (si después de esa fecha, día de
  121      -- Lima, hubo un cambio, la cuenta anterior del primero; si no, la contractual actual).
  122      if new.fecha_pago_real is not null then
  123        select c.cuenta_anterior_id into v_cuenta
  124        from crm.contrato_cuenta_pago_cambios c
  125        where c.contrato_id = new.contrato_id
  126          and (c.cambiado_en at time zone 'America/Lima')::date > new.fecha_pago_real
  127        order by c.cambiado_en asc, c.id asc
  128        limit 1;
  129      end if;
  130      if v_cuenta is null then
  131        select l.cuenta_bancaria_id into v_cuenta
  132        from crm.contrato_cuentas_pago l
  133        where l.contrato_id = new.contrato_id;
  134      end if;
  135      -- Sin cuenta: el trigger BEFORE de exigencia ya rechazó el pago; nada que sellar.
  136      if v_cuenta is null then
  137        return null;
  138      end if;
  139    end if;
  140  
  141    insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
  142    values (new.id, new.contrato_id, v_cuenta,
  143            case when not v_nuevo_pago then 'inferido' when v_cci is not null then 'declarado' else 'registro' end)
  144    on conflict (cuota_id) do update
  145      set contrato_id = excluded.contrato_id,
  146          cuenta_bancaria_id = excluded.cuenta_bancaria_id,
  147          origen = case when v_nuevo_pago then excluded.origen else crm.cuotas_cuenta_pagada.origen end,
  148          sellada_en = pg_catalog.now();
  149    return null;
  150  end;
  151  $function$;
  152  
  153  -- ── 2. Registrar un pago declarando la cuenta del depósito ─────────────────────────────────
  154  -- INVOKER: el UPDATE corre con la RLS de quien registra (cronograma_admin_actualiza =
  155  -- es_gestor_cartera), exactamente la misma puerta que el UPDATE directo que hace hoy el portal.
  156  -- El CCI viaja al sello solo dentro de esta transacción y se limpia al terminar (también si el
  157  -- UPDATE falla: el ajuste es local a la transacción y se descarta con ella).
  158  create function crm.registrar_pago_con_cuenta(
  159    p_cuota_id uuid, p_fecha date, p_monto numeric, p_cci text)
  160  returns uuid
  161  language plpgsql
  162  volatile security invoker
  163  set search_path to ''
  164  as $function$
  165  declare
  166    v_id uuid;
  167    v_cci text := nullif(pg_catalog.regexp_replace(coalesce(p_cci, ''), '\D', '', 'g'), '');
  168  begin
  169    if p_cuota_id is null or p_fecha is null then
  170      raise exception using errcode = '22023', message = 'Faltan la cuota o la fecha del pago';
  171    end if;
  172    if p_monto is null or p_monto <= 0 then
  173      raise exception using errcode = '22023', message = 'El monto pagado debe ser mayor que cero';
  174    end if;
  175    if pg_catalog.btrim(coalesce(p_cci, '')) <> '' and (v_cci is null or pg_catalog.length(v_cci) <> 20) then
  176      raise exception using errcode = '22023', message = 'El CCI del depósito no tiene 20 dígitos';
  177    end if;
  178    perform pg_catalog.set_config('crm.cci_deposito', coalesce(v_cci, ''), true);
  179    perform pg_catalog.set_config('crm.cci_deposito_testigo',
  180      case when v_cci is null then '' else pg_catalog.md5(pg_catalog.txid_current()::text || '|' || v_cci) end, true);
  181    update public.cronograma_pagos
  182       set estado = 'pagado', fecha_pago_real = p_fecha, monto_pagado = p_monto,
  183           registrado_por = (select auth.uid())
  184     where id = p_cuota_id and estado = 'pendiente'
  185    returning id into v_id;
  186    perform pg_catalog.set_config('crm.cci_deposito', '', true);
  187    perform pg_catalog.set_config('crm.cci_deposito_testigo', '', true);
  188    return v_id;
  189  end;
  190  $function$;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260818200741_crm_contratos_correccion_pdf_eliminacion.sql líneas 602-664 (trigger 00 del cronograma (bloquea el contrato antes que el bloqueo de pagos))
```sql
  602  create or replace function private.proteger_cronograma_documental()
  603  returns trigger
  604  language plpgsql
  605  security definer
  606  set search_path = ''
  607  as $function$
  608  declare
  609    v_anterior uuid := case when tg_op in ('UPDATE', 'DELETE') then old.contrato_id end;
  610    v_nuevo uuid := case when tg_op in ('INSERT', 'UPDATE') then new.contrato_id end;
  611    v_cambio_documental boolean := true;
  612  begin
  613    -- En un CASCADE el padre ya no es visible cuando corre el trigger del hijo;
  614    -- el token solo lo instala el finalizador server-side que bloqueó ese padre.
  615    if tg_op = 'DELETE'
  616       and current_setting('crm.contrato_pdf_eliminacion_autorizada', true)
  617             = old.contrato_id::text then
  618      return old;
  619    end if;
  620  
  621    -- También serializa cambios de pago (estado/monto/fecha real), aunque no
  622    -- cambien el texto legal: un Admin autorizado sin pagos no puede perder esa
  623    -- condición después de que la Edge ya retiró los archivos.
  624    perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  625    if (
  626      v_anterior is not null
  627      and private.contrato_en_eliminacion(v_anterior)
  628      and not private.mutacion_documental_autorizada(v_anterior)
  629    ) or (
  630      v_nuevo is not null
  631      and private.contrato_en_eliminacion(v_nuevo)
  632      and not private.mutacion_documental_autorizada(v_nuevo)
  633    ) then
  634      raise exception 'El contrato está en proceso de eliminación'
  635        using errcode = '55000';
  636    end if;
  637  
  638    if tg_op = 'UPDATE' then
  639      v_cambio_documental := row(
  640        new.id, new.contrato_id, new.numero_cuota, new.fecha_programada,
  641        new.monto_programado, new.tipo
  642      ) is distinct from row(
  643        old.id, old.contrato_id, old.numero_cuota, old.fecha_programada,
  644        old.monto_programado, old.tipo
  645      );
  646    end if;
  647    if not v_cambio_documental then return new; end if;
  648  
  649    if (
  650      v_anterior is not null
  651      and private.contrato_documental_congelado(v_anterior)
  652      and not private.mutacion_documental_autorizada(v_anterior)
  653    ) or (
  654      v_nuevo is not null
  655      and private.contrato_documental_congelado(v_nuevo)
  656      and not private.mutacion_documental_autorizada(v_nuevo)
  657    ) then
  658      raise exception 'El cronograma contractual está congelado por su PDF legal'
  659        using errcode = '55000';
  660    end if;
  661  
  662    if tg_op = 'DELETE' then return old; end if;
  663    return new;
  664  end;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260925153226_p0xx_cuentas_cliente_backfill_lectura.sql líneas 437-467 (crm.cuentas_bancarias_cliente_fn: la lista de cuentas que usa la ventana)
```sql
  437  create or replace function crm.cuentas_bancarias_cliente_fn(
  438    p_cliente_id uuid, p_moneda text)
  439  returns table (
  440    cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  441    numero_cuenta text, cci text, titular_distinto boolean,
  442    beneficiario_nombre text, beneficiario_dni text, origen text,
  443    es_cuenta_perfil boolean, creada_en timestamptz
  444  )
  445  language plpgsql
  446  stable security definer
  447  set search_path to ''
  448  as $function$
  449  begin
  450    if p_moneda is null or p_moneda not in ('PEN', 'USD') then
  451      raise exception using errcode = '22023', message = 'Moneda bancaria invalida';
  452    end if;
  453    if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
  454      raise exception using errcode = '42501',
  455        message = 'Cliente no encontrado o fuera de tu cartera';
  456    end if;
  457  
  458    return query
  459    select c.cuenta_id, c.moneda, c.banco, c.tipo_cuenta,
  460           c.numero_cuenta, c.cci, c.titular_distinto,
  461           c.beneficiario_nombre, c.beneficiario_dni, c.origen,
  462           false, c.creada_en
  463    from private.cuentas_cliente_vigentes(p_cliente_id) c
  464    where c.moneda = p_moneda
  465    order by c.creada_en desc, c.cuenta_id desc;
  466  end;
  467  $function$;
```

### PORTAL (repo aparte) · js/admin/asignar-cuenta-core.js (NUEVO, completo)
```js
// Asignar la cuenta de pago a un contrato que no la tiene (01/10/2026).
// Núcleo puro de la ventana «Asignar cuenta de pago» de Pagos: quién ve el botón, qué se valida
// antes de enviar y los textos. Sin DOM ni red: lo prueba tests/asignar-cuenta-core.test.mjs.
// La frontera real está en el servidor (crm.asignar_cuenta_pago_contrato: solo administración,
// cuenta vigente del mismo cliente y moneda, contrato sin cuenta); esto solo da buena experiencia.

const MONEDA_EN_PALABRAS = new Map([['PEN', 'soles'], ['USD', 'dólares']])

// Casos del servidor que NO se arreglan asignando: el contrato ya tiene una cuenta vinculada,
// pero no le corresponde (eso se corrige con «Cambiar cuenta de pago» en Clientes).
const CASOS_QUE_NO_SE_ASIGNAN = new Set(['cuenta_no_corresponde'])

const ESTADOS_CERRADOS = new Set(['renovado', 'retirado'])

// Misma regla que «Cambiar cuenta de pago» en Clientes: solo administración.
export function puedeAsignarCuentaPago(rol) {
  return rol === 'admin' || rol === 'superadmin'
}

/**
 * ¿Lleva esta fila el botón «Asignar cuenta»? Solo para administración, solo si las cuentas de
 * la fila se pudieron verificar, el contrato sigue abierto y no tiene NINGUNA cuenta de pago
 * vinculada (si la tiene, aunque esté incompleta, no se asigna: se cambia), y solo si el caso
 * que dijo el servidor se arregla asignando.
 */
export function filaAdmiteAsignarCuenta(rol, fila) {
  if (!puedeAsignarCuentaPago(rol)) return false
  if (!fila || typeof fila !== 'object' || fila.cuentas_sin_verificar) return false
  if (fila.cuenta_pago_contrato !== null && fila.cuenta_pago_contrato !== undefined) return false
  if (ESTADOS_CERRADOS.has(fila.estado_contrato)) return false
  return !CASOS_QUE_NO_SE_ASIGNAN.has(String(fila.motivo_sin_cuenta?.caso ?? '').trim())
}

export function monedaEnPalabras(moneda) {
  return MONEDA_EN_PALABRAS.get(moneda) ?? 'la moneda del contrato'
}

// Segunda línea de la ventana: «Contrato 2026-01-000734 · en soles».
export function textoContratoAsignacion(numeroContrato, moneda) {
  const numero = String(numeroContrato ?? '').trim() || '—'
  return `Contrato ${numero} · en ${monedaEnPalabras(moneda)}`
}

// Las cuentas del cliente entre las que se puede elegir: las de la moneda del contrato.
export function cuentasParaAsignar(cuentas, moneda) {
  if (!Array.isArray(cuentas)) return []
  return cuentas.filter((cuenta) => cuenta && cuenta.id && cuenta.moneda === moneda)
}

export function textoSinCuentasParaAsignar(moneda) {
  return `El cliente no tiene ninguna cuenta en ${monedaEnPalabras(moneda)}. Regístrala primero en Clientes → Cuentas.`
}

// Misma regla del motivo que el servidor (que es quien manda): 5 a 500 caracteres sin contar
// los espacios de los extremos. No hay preselección: la cuenta se elige a conciencia.
export function validarAsignacion({ cuentaId, motivo } = {}) {
  if (!String(cuentaId ?? '').trim()) return 'Elige la cuenta en la que cobra este contrato.'
  const texto = String(motivo ?? '').trim()
  if (texto.length < 5 || texto.length > 500) return 'Escribe el motivo de la asignación (5 a 500 caracteres).'
  return null
}

// El servidor devuelve la solicitud que acaba de aplicar (o que ya estaba aplicada): solo eso
// cuenta como asignación hecha. Nunca se anuncia una asignación sin esa confirmación.
export function asignacionConfirmada(data, solicitudId) {
  const devuelta = String(data?.solicitud_id ?? '').trim().toLowerCase()
  return devuelta !== '' && devuelta === String(solicitudId ?? '').trim().toLowerCase()
}

const textoLlano = (valor) => (typeof valor === 'string' || typeof valor === 'number' ? String(valor).trim() : '')

/**
 * Aviso de éxito: «Cuenta asignada al contrato N: BCP …6087. Ya puedes registrar el pago.».
 * Dice cuál cuenta quedó (banco y los 4 últimos caracteres de su número) para que no haya duda
 * cuando el cliente tiene dos cuentas del mismo banco. `data` es la respuesta del servidor
 * (igual en el primer envío que en el reintento). Si falta el banco o faltan los últimos, la
 * cuenta no se nombra a medias: queda «Cuenta asignada al contrato N. Ya puedes registrar el pago.».
 * `numeroDeLaFila` es el respaldo del número de contrato.
 */
export function textoExitoAsignacion(data, numeroDeLaFila) {
  const numero = textoLlano(data?.numero_contrato) || textoLlano(numeroDeLaFila)
  const banco = textoLlano(data?.banco)
  const ultimos = textoLlano(data?.ultimos).slice(-4)   // nunca más de 4, venga lo que venga
  const cuenta = banco && ultimos ? `: ${banco} …${ultimos}` : ''
  return `Cuenta asignada al contrato${numero ? ` ${numero}` : ''}${cuenta}. Ya puedes registrar el pago.`
}

/**
 * Traduce el fallo del servidor sin inventar: sus mensajes de regla (22023) y de permiso (42501)
 * ya están escritos para la persona y se muestran tal cual. `status` es el de la respuesta HTTP.
 */
export function mensajeErrorAsignacion(error, status) {
  if (error?.code === 'PGRST202' || status === 404) {
    return 'La asignación todavía no está disponible. Avisa a soporte.'
  }
  const mensaje = typeof error?.message === 'string' ? error.message.trim() : ''
  if (error?.code === '42501') {
    // Un «permission denied…» de la base no es un texto para la persona.
    return mensaje && !/^permission denied/i.test(mensaje) ? mensaje : 'Solo administración puede asignar la cuenta de pago.'
  }
  if (error?.code === '22023' && mensaje) return mensaje
  return 'No se pudo asignar la cuenta. Revisa tu conexión y vuelve a intentar.'
}

/**
 * Qué decirle a la persona tras el envío: `null` si la asignación quedó hecha (recién aplicada o
 * ya aplicada en un intento anterior), o el mensaje del fallo. Una respuesta sin error pero sin
 * la confirmación de la solicitud NO cuenta como hecha: reintentar es seguro (mismo id).
 */
export function fallaDeAsignacion({ data, error, status } = {}, solicitudId) {
  if (error) return mensajeErrorAsignacion(error, status)
  return asignacionConfirmada(data, solicitudId) ? null : mensajeErrorAsignacion(null, status)
}
```

### PORTAL · DIFF frente a lo publicado (d22eae6): js/admin/pagos.js, js/admin/cuentas-pago-core.js y admin/pagos.html
```diff
diff --git a/admin/pagos.html b/admin/pagos.html
index 0bc868f..e917817 100644
--- a/admin/pagos.html
+++ b/admin/pagos.html
@@ -240,6 +240,39 @@
     </div>
   </div>
 
+  <!-- ========== MODAL ASIGNAR CUENTA DE PAGO (solo administración; el servidor revalida) ========== -->
+  <div class="modal-overlay hidden" id="modalAsignar">
+    <div class="modal">
+      <div class="modal-header">
+        <h2 class="modal-title">Asignar cuenta de pago</h2>
+        <button class="modal-close" type="button" id="modalCloseAsignar" aria-label="Cerrar">✕</button>
+      </div>
+      <form id="formAsignar">
+        <div class="modal-body">
+          <div id="modalAsignarError" class="alert alert-danger hidden" role="alert" style="font-size: 14px;"></div>
+
+          <div id="as_resumen" class="alert alert-info" style="font-size: 14px;"></div>
+
+          <div class="input-group">
+            <label class="input-label" id="as_cuentas_titulo" style="font-size: 14px;">¿En qué cuenta cobra este contrato? *</label>
+            <div id="as_cuentas" role="radiogroup" aria-labelledby="as_cuentas_titulo" style="font-size: 14px;"></div>
+          </div>
+
+          <div class="input-group" id="as_grupo_motivo">
+            <label class="input-label" for="as_motivo" style="font-size: 14px;">Motivo *</label>
+            <textarea class="input" id="as_motivo" rows="2" maxlength="500" aria-describedby="as_motivo_ayuda" placeholder="Ej.: el cliente confirmó por teléfono que cobra en esta cuenta"></textarea>
+            <!-- El motivo queda en la bitácora y lo lee cualquier administrador: sin datos sensibles. -->
+            <p class="text-muted" id="as_motivo_ayuda" style="font-size: 14px; margin: 4px 0 0;">Escribe por qué se asigna esta cuenta. No pongas números de cuenta, CCI ni documentos.</p>
+          </div>
+        </div>
+        <div class="modal-footer">
+          <button type="button" class="btn btn-secondary" id="btnCancelarAsignar" style="font-size: 14px;">Cancelar</button>
+          <button type="submit" class="btn btn-primary" id="btnConfirmarAsignar" style="font-size: 14px;">Asignar cuenta</button>
+        </div>
+      </form>
+    </div>
+  </div>
+
   <!-- ========== MODAL EXPORTAR EXCEL ========== -->
   <div class="modal-overlay hidden" id="modalExportar">
     <div class="modal modal-sm">
@@ -308,7 +341,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/pagos.js?v=45"></script>
+  <script type="module" src="/js/admin/pagos.js?v=46"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
diff --git a/js/admin/cuentas-pago-core.js b/js/admin/cuentas-pago-core.js
index ddb51a3..befa666 100644
--- a/js/admin/cuentas-pago-core.js
+++ b/js/admin/cuentas-pago-core.js
@@ -4,10 +4,22 @@
  * La cuenta de pago es la cuenta vinculada al contrato. Desde el 26/09/2026 (F3) solo
  * cambia por pedido del cliente, con historial; lo ya pagado conserva su cuenta.
  * La ausencia de vínculo exige conciliación antes de pagar o exportar.
+ *
+ * Desde el 01/10/2026 el aviso dice POR QUÉ falta la cuenta: el caso y el texto los decide y
+ * redacta SIEMPRE el servidor (`crm.cuentas_pago_motivos_fn`). Aquí solo se indexa, se elige y
+ * se resume ese texto, y a cada caso se le pone una etiqueta corta para la fila; ninguna de
+ * esas funciones decide un bloqueo ni deduce un caso.
  */
 
 const MONEDAS_SOPORTADAS = new Set(['PEN', 'USD'])
 
+// Aviso fijo de siempre: lo que se muestra cuando no se conoce el motivo (la puerta de motivos
+// no existe todavía, falló o no trajo fila para ese contrato) o su caso no tiene etiqueta aquí.
+export const AVISO_SIN_CUENTA = 'Sin cuenta de pago — requiere conciliación'
+
+// Tope de contratos por llamada de `crm.cuentas_pago_motivos_fn` (el servidor rechaza más).
+export const MAX_CONTRATOS_MOTIVOS = 5000
+
 function exigirObjeto(valor, etiqueta) {
   if (!valor || typeof valor !== 'object' || Array.isArray(valor)) {
     throw new TypeError(`${etiqueta} no tiene un formato válido.`)
@@ -158,6 +170,143 @@ export function motivoRechazoRegistro(cliente, concepto, error) {
 
 // Texto de «Se depositó en:» del modal de pago manual.
 export function textoCuentaDeposito(cuenta) {
-  if (!cuenta) return 'Sin cuenta de pago — requiere conciliación'
+  if (!cuenta) return AVISO_SIN_CUENTA
   return `${cuenta.banco} · ${cuenta.tipo_cuenta} · N°\u00A0${cuenta.numero_cuenta} · CCI\u00A0${cuenta.cci}`
 }
+
+/* ── Motivos: POR QUÉ un contrato no tiene cuenta de pago ─────────────────────────────────── */
+
+/**
+ * Marca del bloqueo por cuenta de pago. Su mensaje ya está redactado para la persona, así que
+ * quien lo atrapa lo muestra tal cual (se reconoce por la clase, no comparando textos).
+ */
+export class ErrorSinCuentaPago extends Error {
+  constructor(mensaje) {
+    super(mensaje)
+    this.name = 'ErrorSinCuentaPago'
+  }
+}
+
+// Misma regla que usa la pantalla para bloquear: sin cuenta, incompleta o inconsistente.
+function sinCuentaCompleta(fila) {
+  try {
+    return !cuentaPagoCompleta(cuentaParaCuota(fila))
+  } catch {
+    return true
+  }
+}
+
+/** La frase que el servidor redactó para el contrato de esa fila; '' si no se conoce. */
+export function mensajeSinCuentaPago(fila) {
+  const mensaje = fila?.motivo_sin_cuenta?.mensaje
+  return typeof mensaje === 'string' ? mensaje.trim() : ''
+}
+
+// Nombre corto de cada caso, para las filas. El caso lo decide SIEMPRE el servidor: aquí no se
+// deduce ninguno, solo se le pone etiqueta al que llega. Ninguna es más larga que el aviso fijo
+// (la fila no crece); si se añade o alarga una, hay que volver a medir la agenda.
+const ETIQUETA_POR_CASO = new Map([
+  ['una_cuenta', 'Falta vincular su cuenta'],
+  ['varias_cuentas', 'Tiene varias cuentas: confirmar cuál'],
+  ['sin_cuenta', 'El cliente no tiene cuenta'],
+  ['cuenta_no_corresponde', 'La cuenta no corresponde'],
+])
+const MONEDA_EN_PALABRAS = new Map([['PEN', 'soles'], ['USD', 'dólares']])
+
+/**
+ * Texto CORTO de la fila: qué falta, según el caso del motivo ({ caso, mensaje }). En
+ * `otra_moneda` nombra la moneda del CONTRATO. Sin motivo, o con un caso que este código no
+ * conoce (uno nuevo del servidor), queda el aviso fijo: la fila nunca se queda en blanco.
+ */
+export function etiquetaSinCuentaPago(motivo, moneda) {
+  const caso = texto(motivo?.caso)
+  if (caso === 'otra_moneda') return `Falta cuenta en ${MONEDA_EN_PALABRAS.get(moneda) ?? 'su moneda'}`
+  return ETIQUETA_POR_CASO.get(caso) ?? AVISO_SIN_CUENTA
+}
+
+function conPuntoFinal(frase) {
+  return /[.!?…]$/.test(frase) ? frase : `${frase}.`
+}
+
+/**
+ * Contratos (sin repetir, en el orden de las filas) cuya cuenta de pago falta o no está
+ * completa: los ÚNICOS por los que se pregunta el motivo, y como mucho MAX_CONTRATOS_MOTIVOS.
+ */
+export function contratosSinCuentaPago(filas) {
+  const ids = new Set()
+  for (const fila of filas) {
+    const contratoId = texto(fila?.contrato_id)
+    if (contratoId && sinCuentaCompleta(fila)) ids.add(contratoId)
+  }
+  return [...ids].slice(0, MAX_CONTRATOS_MOTIVOS)
+}
+
+/**
+ * Respuesta de `crm.cuentas_pago_motivos_fn` ({ contrato_id, caso, mensaje }) → Map de
+ * contrato_id a su motivo { caso, mensaje }. Tolerante a propósito: una respuesta rara o una
+ * fila sin contrato o sin mensaje se ignora y ese contrato se queda con el aviso fijo. La frase
+ * nunca se redacta aquí; el `caso` solo sirve para elegir la etiqueta corta de la fila.
+ */
+export function indexarMotivosSinCuenta(filasMotivo) {
+  const porContrato = new Map()
+  if (!Array.isArray(filasMotivo)) return porContrato
+  for (const fila of filasMotivo) {
+    const contratoId = texto(fila?.contrato_id)
+    const mensaje = typeof fila?.mensaje === 'string' ? fila.mensaje.trim() : ''
+    if (contratoId && mensaje && !porContrato.has(contratoId)) {
+      porContrato.set(contratoId, { caso: typeof fila.caso === 'string' ? fila.caso.trim() : '', mensaje })
+    }
+  }
+  return porContrato
+}
+
+/** Copia de las filas con `motivo_sin_cuenta`: el motivo { caso, mensaje } de su contrato, o null. */
+export function asociarMotivosSinCuenta(filas, motivos) {
+  return filas.map((fila) => {
+    const motivo = motivos.get(texto(fila?.contrato_id))
+    return { ...fila, motivo_sin_cuenta: motivo ? { ...motivo } : null }
+  })
+}
+
+/**
+ * Filas con el motivo del servidor en las que no tienen cuenta de pago. `consultar(contratoIds)`
+ * es la llamada a `crm.cuentas_pago_motivos_fn` (la pone la pantalla): se hace UNA sola vez y
+ * solo con los contratos sin cuenta; si no hay ninguno, ni se llama.
+ * Nunca lanza: la puerta puede no existir todavía o fallar (404, PGRST202, 42501, red…). En ese
+ * caso avisa a `alFallar(error)` y devuelve las MISMAS filas, que se quedan con el aviso fijo.
+ */
+export async function conMotivosSinCuenta(filas, consultar, alFallar) {
+  try {
+    const contratoIds = contratosSinCuentaPago(filas)
+    if (contratoIds.length === 0) return filas
+    return asociarMotivosSinCuenta(filas, indexarMotivosSinCuenta(await consultar(contratoIds)))
+  } catch (error) {
+    try { alFallar?.(error) } catch { /* el aviso tampoco puede romper la pantalla */ }
+    return filas
+  }
+}
+
+/** Aviso COMPLETO de una fila sin cuenta: la frase del servidor o, si no se conoce, el fijo. */
+export function textoSinCuentaPago(fila) {
+  return mensajeSinCuentaPago(fila) || AVISO_SIN_CUENTA
+}
+
+/**
+ * Una sola frase para VARIAS filas (error del pago manual, de la importación y aviso de
+ * exportación): el primer motivo conocido y, si hay más contratos sin cuenta, «Y N contratos
+ * más sin cuenta de pago.». Mira solo las filas sin cuenta completa y cuenta CONTRATOS, no
+ * cuotas. Sin ningún motivo conocido devuelve el aviso fijo de siempre.
+ */
+export function resumenSinCuentaPago(filas) {
+  const motivos = new Map()   // contrato sin cuenta → la frase de su motivo ('' si no se conoce)
+  for (const fila of filas) {
+    if (!sinCuentaCompleta(fila)) continue
+    const contratoId = texto(fila?.contrato_id)
+    if (!motivos.get(contratoId)) motivos.set(contratoId, mensajeSinCuentaPago(fila))
+  }
+  const primero = [...motivos.values()].find(Boolean)
+  if (!primero) return `${AVISO_SIN_CUENTA}.`
+  const otros = motivos.size - 1
+  if (otros === 0) return conPuntoFinal(primero)
+  return `${conPuntoFinal(primero)} Y ${otros} contrato${otros === 1 ? '' : 's'} más sin cuenta de pago.`
+}
diff --git a/js/admin/pagos.js b/js/admin/pagos.js
index a0eed7e..8f2de24 100644
--- a/js/admin/pagos.js
+++ b/js/admin/pagos.js
@@ -32,11 +32,22 @@ import {
   cciDeclaradoDeFila,
   motivoRechazoRegistro,
   textoCuentaDeposito,
-} from './cuentas-pago-core.js?v=4'
+  conMotivosSinCuenta,
+  etiquetaSinCuentaPago,
+  mensajeSinCuentaPago,
+  textoSinCuentaPago,
+  resumenSinCuentaPago,
+  ErrorSinCuentaPago,
+} from './cuentas-pago-core.js?v=5'
 import { POR_PAGINA_POR_TRAMO, planPagina, etiquetaPagina } from './agenda-paginas-core.js?v=1'
 import {
   PAGE_SIZE_TABLA, parametrosTabla, mapearFilaResumen, totalDeRespuesta, paginaFueraDeRango, ultimaPagina,
 } from './pagos-tabla-core.js?v=1'
+import { cargarCuentasCliente, textoCuenta } from './cuentas-cliente-core.js?v=5'
+import {
+  filaAdmiteAsignarCuenta, textoContratoAsignacion, cuentasParaAsignar, textoSinCuentasParaAsignar,
+  validarAsignacion, fallaDeAsignacion, textoExitoAsignacion,
+} from './asignar-cuenta-core.js?v=1'
 
 const MS_DIA = 86400000
 
@@ -61,6 +72,8 @@ let MODAL_PROGRAMADO = 0            // monto programado de la cuota abierta (fue
 let MODAL_MONEDA = 'PEN'           // moneda de la cuota abierta
 let ULTIMO_PAGO       = null        // datos del último pago registrado (para botón WhatsApp en el toast)
 let CUENTAS_PAGO_LISTAS = false   // ninguna operación de pago sin consultar los vínculos contractuales
+let ROL_USUARIO       = null        // rol del perfil con el que se entró; solo decide qué se OFRECE (el servidor revalida)
+let ASIGNACION        = null        // ventana «Asignar cuenta de pago» abierta: { solicitudId, contratoId, … }
 
 /* ============================================
    NOTIFICAR AL CLIENTE (pago realizado)
@@ -186,12 +199,49 @@ async function consultarCuentasContractuales(contratoIds) {
   return data || []
 }
 
+// El motivo solo mejora el texto del aviso: no merece dejar la pantalla esperando. Si la puerta
+// tarda más que esto, la consulta se corta y se sigue con el aviso fijo.
+const ESPERA_MOTIVOS_MS = 3000
+
+/**
+ * POR QUÉ no se pueden pagar esos contratos, redactado por el servidor: filas
+ * { contrato_id, caso, mensaje } solo de los que no tienen cuenta de pago válida.
+ * Lanza si la puerta falla; quien decide qué hacer con eso es `motivosSinCuenta`.
+ */
+async function consultarMotivosSinCuenta(contratoIds) {
+  const ctrl = new AbortController()
+  const espera = setTimeout(() => ctrl.abort(), ESPERA_MOTIVOS_MS)
+  try {
+    const { data, error } = await supabase
+      .schema('crm')
+      .rpc('cuentas_pago_motivos_fn', { p_contrato_ids: contratoIds })
+      .abortSignal(ctrl.signal)
+    if (error) throw error
+    return data
+  } finally {
+    clearTimeout(espera)
+  }
+}
+
+/**
+ * Las mismas filas, con el motivo en las que no tienen cuenta de pago (`motivo_sin_cuenta`).
+ * UNA llamada por carga o verificación y solo con los contratos sin cuenta. Es solo texto: no
+ * decide ningún bloqueo. La puerta puede no existir todavía (el portal y el servidor se publican
+ * por separado) o fallar: entonces no se rompe nada y se muestra el aviso fijo de siempre.
+ */
+function motivosSinCuenta(filas) {
+  return conMotivosSinCuenta(filas, consultarMotivosSinCuenta, (error) => {
+    console.warn('[pagos] no se pudo consultar el motivo de las cuentas de pago; se muestra el aviso fijo:', error)
+  })
+}
+
 async function verificarCuentasParaCuotas(cuotas) {
   const ids = [...new Set(cuotas.map(c => c.contrato_id).filter(Boolean))]
   const filas = await consultarCuentasContractuales(ids)
   const asociadas = asociarCuentasPagoContrato(cuotas, filas)
   if (asociadas.some(c => !cuentaPagoCompleta(cuentaParaCuota(c)))) {
-    throw new Error('Sin cuenta de pago — requiere conciliación.')
+    // El bloqueo ya está decidido con las cuentas recién consultadas; el motivo solo redacta el aviso.
+    throw new ErrorSinCuentaPago(resumenSinCuentaPago(await motivosSinCuenta(asociadas)))
   }
   return asociadas
 }
@@ -334,7 +384,7 @@ async function asociarCuentasPagina(contratos) {
   if (contratos.length === 0) return contratos
   try {
     const filas = await consultarCuentasContractuales([...new Set(contratos.map(c => c.id))])
-    return asociarCuentasPagoPantalla([], contratos, filas).contratos
+    return await motivosSinCuenta(asociarCuentasPagoPantalla([], contratos, filas).contratos)
   } catch (error) {
     console.error('[pagos] no se pudieron resolver las cuentas de la página:', error)
     mostrarError('Se cargó la tabla, pero no se verificaron las cuentas de depósito de esta página. Recarga para poder registrar pagos aquí.')
@@ -481,6 +531,9 @@ function renderAgenda() {
   cont.querySelectorAll('[data-action="pagar-agenda"]').forEach(btn => {
     btn.addEventListener('click', onPagarDesdeAgenda)
   })
+  cont.querySelectorAll('[data-action="asignar-agenda"]').forEach(btn => {
+    btn.addEventListener('click', onAsignarDesdeAgenda)
+  })
   cont.querySelectorAll('[data-action="pagina"]').forEach(btn => {
     btn.addEventListener('click', onPaginaTramoAgenda)
   })
@@ -506,10 +559,39 @@ function cuentaDisponible(cuota) {
   }
 }
 
+const cuentasVerificadas = (cuota) => CUENTAS_PAGO_LISTAS && !cuota?.cuentas_sin_verificar
+const AVISO_SIN_VERIFICAR = 'No se pudo verificar la cuenta de pago — recarga la página'
+
+// Aviso CORTO de las filas (agenda y tabla por contrato): qué falta, con la etiqueta del caso
+// que dijo el servidor; sin motivo, el texto fijo de siempre. Son textos de aquí, no del servidor.
 function avisoCuentaPago(cuota) {
-  return CUENTAS_PAGO_LISTAS && !cuota?.cuentas_sin_verificar
-    ? 'Sin cuenta de pago — requiere conciliación'
-    : 'No se pudo verificar la cuenta de pago — recarga la página'
+  return cuentasVerificadas(cuota)
+    ? etiquetaSinCuentaPago(cuota?.motivo_sin_cuenta, cuota?.moneda)
+    : AVISO_SIN_VERIFICAR
+}
+
+// Aviso COMPLETO, para los avisos de bloque: dice POR QUÉ falta la cuenta si el servidor lo
+// dijo. Es texto del servidor: quien lo meta en `innerHTML` lo pasa por escapeHtml.
+function avisoCuentaPagoConMotivo(cuota) {
+  return cuentasVerificadas(cuota) ? textoSinCuentaPago(cuota) : AVISO_SIN_VERIFICAR
+}
+
+// En las FILAS la frase completa del servidor va en `title` (se lee al pasar el cursor): metida
+// entera en la celda recortaba el nombre del cliente en pantallas de hasta 960 px.
+function tituloMotivo(cuota) {
+  const mensaje = cuentasVerificadas(cuota) ? mensajeSinCuentaPago(cuota) : ''
+  return mensaje ? ` title="${escapeHtml(mensaje)}"` : ''
+}
+
+// La alerta del cronograma vive dentro de una tabla que en móvil no parte líneas y mide lo que
+// mida su contenido: con la frase larga la ensanchaba. Con esto parte líneas y no aporta ancho
+// propio (ocupa el del panel); en escritorio se ve igual que sin él.
+const ESTILO_ALERTA_CRONOGRAMA = 'white-space: normal; width: 0; min-width: 100%;'
+
+// «Asignar cuenta»: solo administración y solo donde asignar desbloquea la fila (lo decide el
+// núcleo). El servidor revalida todo; esto solo evita ofrecer un botón que rebotaría.
+function asignable(fila) {
+  return cuentasVerificadas(fila) && filaAdmiteAsignarCuenta(ROL_USUARIO, fila)
 }
 
 function renderFilaAgenda(a) {
@@ -520,6 +602,12 @@ function renderFilaAgenda(a) {
       ? `<span class="badge badge-new badge-concepto">PAGO DE INTERESES</span>`
       : `<strong>Cuota #${a.numero_cuota}</strong>`
   const pagable = cuentaDisponible(a)
+  // Fila bloqueada que administración puede desbloquear: «Asignar cuenta» va debajo de la etiqueta,
+  // ENCIMA del «Marcar pagado» apagado, que se queda como estaba (la fila crece lo que mide el botón).
+  // Letra de 14 px también en el móvil, donde `.btn-sm` baja a 12,5 px.
+  const botonAsignar = !pagable && asignable(a)
+    ? `<button type="button" class="btn btn-secondary btn-sm" data-action="asignar-agenda" data-cuota-id="${a.cuota_id}" style="font-size: 14px;">Asignar cuenta</button>`
+    : ''
   // El aviso de cuenta va en su propia línea (.aviso-cuenta) dentro de una columna de
   // ancho fijo: antes se metía inline y ensanchaba la columna del botón, desalineando la fila.
   return `
@@ -533,8 +621,8 @@ function renderFilaAgenda(a) {
         <div class="agenda-row-urgencia">${chipUrgencia({ estado: 'pendiente', fecha_programada: a.fecha_programada })}</div>
         <div class="agenda-row-monto tabular">${formatearMoneda(a.monto_programado, a.moneda)}</div>
         <div class="agenda-row-accion">
-          ${pagable ? '' : `<span class="aviso-cuenta">${avisoCuentaPago(a)}</span>`}
-          <button class="btn btn-primary btn-sm" data-action="pagar-agenda" data-cuota-id="${a.cuota_id}" ${pagable ? '' : 'disabled'}>
+          ${pagable ? '' : `<span class="aviso-cuenta"${tituloMotivo(a)}>${escapeHtml(avisoCuentaPago(a))}</span>`}
+          ${botonAsignar}<button class="btn btn-primary btn-sm" data-action="pagar-agenda" data-cuota-id="${a.cuota_id}" ${pagable ? '' : 'disabled'}>
             Marcar pagado
           </button>
         </div>
@@ -543,6 +631,14 @@ function renderFilaAgenda(a) {
   `
 }
 
+function onAsignarDesdeAgenda(e) {
+  const a = AGENDA_CACHE.find(x => x.cuota_id === e.currentTarget.dataset.cuotaId)
+  if (!a) return
+  abrirModalAsignar(a, {
+    contratoId: a.contrato_id, numeroContrato: a.numero_contrato, moneda: a.moneda, cliente: a.cliente, clienteId: a.cliente_id,
+  })
+}
+
 function onPagarDesdeAgenda(e) {
   const cuotaId = e.currentTarget.dataset.cuotaId
   const a = AGENDA_CACHE.find(x => x.cuota_id === cuotaId)
@@ -562,6 +658,7 @@ function onPagarDesdeAgenda(e) {
     moneda: a.moneda,
     cliente: a.cliente,
     cuenta_pago_contrato: a.cuenta_pago_contrato,
+    motivo_sin_cuenta: a.motivo_sin_cuenta,
   }
   abrirModalPago(cuota, contrato)
 }
@@ -653,7 +750,7 @@ function actualizarResumenExport() {
     const clientes = [...new Set(sinBank.map(({ cuota }) => cuota.cliente))]
     btnGen.disabled = true
     warnEl.innerHTML = `⚠️ <strong>${sinBank.length} cuota${sinBank.length === 1 ? '' : 's'}</strong>: ` +
-      `Sin cuenta de pago — requiere conciliación. La exportación está bloqueada.<br>` +
+      `${escapeHtml(resumenSinCuentaPago(sinBank.map(({ cuota }) => cuota)))} La exportación está bloqueada.<br>` +
       `Clientes: ${clientes.slice(0,3).map(cliente => escapeHtml(cliente)).join(', ')}${clientes.length > 3 ? `, …` : ''}`
     warnEl.classList.remove('hidden')
   } else {
@@ -1051,6 +1148,10 @@ function renderTabla() {
   })
   tbody.innerHTML = filas.join('')
 
+  tbody.querySelectorAll('[data-action="asignar-contrato"]').forEach(btn => {
+    btn.addEventListener('click', onAsignarDesdeTabla)
+  })
+
   // Click en fila contrato → toggle expand sin re-render (para que la transición CSS corra)
   tbody.querySelectorAll('.row-contrato').forEach(tr => {
     tr.addEventListener('click', (e) => {
@@ -1147,9 +1248,16 @@ function pintarCronogramaExpandido(contratoId) {
 
 function renderFilaContrato(c, idx = 0) {
   const expanded = EXPANDIDO === c.id
-  const avisoPago = !cuentaDisponible(c)
-    ? `<div class="aviso-cuenta">${avisoCuentaPago(c)}</div>`
+  const sinCuenta = !cuentaDisponible(c)
+  const etiqueta = sinCuenta
+    ? `<div class="aviso-cuenta"${tituloMotivo(c)}>${escapeHtml(avisoCuentaPago(c))}</div>`
     : ''
+  // «Asignar cuenta» va DEBAJO de la etiqueta, solo si queda algo por pagar. Al lado cabría, pero
+  // ensancha esta columna y, con ella, mueve las demás de toda la tabla (medido); debajo solo crece
+  // la fila bloqueada.
+  const avisoPago = sinCuenta && c.proxima && asignable(c)
+    ? `${etiqueta}<button type="button" class="btn btn-secondary btn-sm" data-action="asignar-contrato" data-contrato="${c.id}" style="margin-top: 6px; font-size: 14px;">Asignar cuenta</button>`
+    : etiqueta
   const proximaHTML = c.proxima
     ? `<div class="proxima-cuota">
          <div>#${c.proxima.numero_cuota} · <strong>${formatearMoneda(c.proxima.monto_programado, c.moneda)}</strong></div>
@@ -1267,7 +1375,7 @@ function renderCronogramaContenido(c) {
       <div class="cron-titulo">Cronograma del contrato <span class="font-mono">${escapeHtml(c.numero_contrato)}</span></div>
       <div class="cron-pills">${pills.join('')}</div>
     </div>
-    ${pagable ? '' : `<div class="alert alert-warning">${avisoCuentaPago(c)}</div>`}
+    ${pagable ? '' : `<div class="alert alert-warning" style="${ESTILO_ALERTA_CRONOGRAMA}">${escapeHtml(avisoCuentaPagoConMotivo(c))}</div>`}
     <div class="table-container cron-tabla-wrap">
       <table class="table-dense">
         <thead>
@@ -1305,7 +1413,7 @@ function onAccionCuota(e) {
 
 function abrirModalPago(cuota, contrato) {
   if (!cuentaDisponible(contrato)) {
-    mostrarError(avisoCuentaPago(contrato))
+    mostrarError(avisoCuentaPagoConMotivo(contrato))
     return
   }
   // Guard: una cuota trasladada no se registra como pagada (su capital se roleó al
@@ -1484,7 +1592,8 @@ async function confirmarPago(e) {
     // Sin catch, un fallo real (getSession/red) restauraba el botón pero no
     // avisaba: el admin podía creer que registró el pago. Mostramos el error.
     console.error('[pagos] confirmarPago falló:', err)
-    errEl.textContent = err.message === 'Sin cuenta de pago — requiere conciliación.'
+    // El bloqueo por cuenta de pago ya trae su aviso para la persona (con el motivo, si se conoce).
+    errEl.textContent = err instanceof ErrorSinCuentaPago
       ? err.message : 'No se pudo registrar el pago. Verifica la cuenta contractual y tu conexión antes de reintentar.'
     errEl.classList.remove('hidden')
   } finally {
@@ -1572,6 +1681,144 @@ async function revertirPago(cuota, contrato) {
   }
 }
 
+/* ============================================
+   ASIGNAR CUENTA DE PAGO (solo administración)
+   ============================================ */
+
+/**
+ * Ventana para darle cuenta de pago a un contrato que no la tiene, eligiendo entre las cuentas
+ * que el cliente YA tiene en la moneda del contrato. No registra ningún pago ni relaja el
+ * bloqueo: tras asignar se recargan cuentas y motivos, y pagar sigue pasando por la misma
+ * verificación. Quién puede y qué cuenta vale lo decide el servidor.
+ */
+function abrirModalAsignar(fila, contrato) {
+  if (!asignable(fila)) return   // el botón solo se pinta en estas filas; esto es defensa extra
+  // El id de la solicitud nace UNA vez por ventana: un reintento tras un fallo de red reusa el
+  // mismo y el servidor no asigna dos veces.
+  ASIGNACION = { ...contrato, solicitudId: crypto.randomUUID(), enviando: false, intentada: false }
+  document.getElementById('as_resumen').innerHTML = `<div>
+    <strong style="font-size: 16px;">${escapeHtml(contrato.cliente || '—')}</strong><br>
+    ${escapeHtml(textoContratoAsignacion(contrato.numeroContrato, contrato.moneda))}
+  </div>`
+  document.getElementById('as_motivo').value = ''
+  document.getElementById('modalAsignarError').classList.add('hidden')
+  pintarCuentasAsignar('<p class="text-muted" style="margin: 0;">Consultando las cuentas del cliente…</p>', false)
+  document.getElementById('modalAsignar').classList.remove('hidden')
+  cargarCuentasAsignar(ASIGNACION)
+}
+
+// `elegibles`: hay cuentas entre las que elegir → se muestran el motivo y el botón de asignar.
+function pintarCuentasAsignar(html, elegibles) {
+  document.getElementById('as_cuentas').innerHTML = html
+  document.getElementById('as_grupo_motivo').classList.toggle('hidden', !elegibles)
+  document.getElementById('btnConfirmarAsignar').classList.toggle('hidden', !elegibles)
+}
+
+// La consulta paginada de la tabla por contrato no trae el cliente: se lee al abrir la ventana.
+async function clienteDelContrato(contratoId) {
+  const { data, error } = await supabase.from('contratos').select('cliente_id').eq('id', contratoId).single()
+  if (error || !data?.cliente_id) throw error || new Error('El contrato no tiene cliente.')
+  return data.cliente_id
+}
+
+async function cargarCuentasAsignar(asignacion) {
+  let cuentas
+  try {
+    const clienteId = asignacion.clienteId || await clienteDelContrato(asignacion.contratoId)
+    cuentas = cuentasParaAsignar(await cargarCuentasCliente(supabase, clienteId), asignacion.moneda)
+  } catch (error) {
+    console.error('[pagos] no se pudieron cargar las cuentas del cliente para asignar:', error)
+    if (ASIGNACION !== asignacion) return
+    pintarCuentasAsignar('<div class="alert alert-danger" style="font-size: 14px; margin: 0;">No se pudieron cargar las cuentas del cliente. Cierra la ventana y vuelve a intentar.</div>', false)
+    return
+  }
+  if (ASIGNACION !== asignacion) return   // la ventana se cerró (o se abrió otra) mientras respondía
+  if (cuentas.length === 0) {
+    pintarCuentasAsignar(`<div class="alert alert-warning" style="font-size: 14px; margin: 0;">${escapeHtml(textoSinCuentasParaAsignar(asignacion.moneda))}</div>`, false)
+    return
+  }
+  // Sin preselección: la cuenta se elige a conciencia, aunque haya una sola.
+  pintarCuentasAsignar(cuentas.map(cuenta => `
+    <label style="display: flex; align-items: flex-start; gap: 10px; font-size: 14px; line-height: 1.4; margin-bottom: 10px; cursor: pointer;">
+      <input type="radio" name="as_cuenta" value="${escapeHtml(cuenta.id)}" style="margin-top: 3px; flex: 0 0 auto;">
+      <span>${escapeHtml(textoCuenta(cuenta))}</span>
+    </label>`).join(''), true)
+}
+
+function cerrarModalAsignar() {
+  if (ASIGNACION?.enviando) return   // como «Cambiar cuenta de pago»: no se cierra a mitad del envío
+  const asignacion = ASIGNACION
+  ASIGNACION = null
+  document.getElementById('modalAsignar').classList.add('hidden')
+  // Un envío que no se pudo confirmar pudo aplicarse igual: se recarga para mostrar lo que hay.
+  if (asignacion?.intentada) recargar()
+}
+
+async function confirmarAsignacion(e) {
+  e.preventDefault()
+  const asignacion = ASIGNACION
+  if (!asignacion || asignacion.enviando) return   // doble clic o Enter repetido: una sola llamada
+  const errEl = document.getElementById('modalAsignarError')
+  errEl.classList.add('hidden')
+
+  const cuentaId = document.querySelector('#as_cuentas input[name="as_cuenta"]:checked')?.value || ''
+  const motivo = document.getElementById('as_motivo').value.trim()
+  const falta = validarAsignacion({ cuentaId, motivo })
+  if (falta) {
+    errEl.textContent = falta
+    errEl.classList.remove('hidden')
+    return
+  }
+
+  const btn = document.getElementById('btnConfirmarAsignar')
+  const btnCancelar = document.getElementById('btnCancelarAsignar')
+  asignacion.enviando = true
+  asignacion.intentada = true
+  btn.disabled = true
+  btn.textContent = 'Asignando…'
+  btnCancelar.disabled = true
+  let respuesta
+  try {
+    respuesta = await supabase.schema('crm').rpc('asignar_cuenta_pago_contrato', {
+      p_solicitud_id: asignacion.solicitudId,
+      p_contrato_id: asignacion.contratoId,
+      p_cuenta_id: cuentaId,
+      p_motivo: motivo,
+    })
+  } catch (error) {
+    respuesta = { data: null, error }
+  } finally {
+    asignacion.enviando = false
+    btn.disabled = false
+    btn.textContent = 'Asignar cuenta'
+    btnCancelar.disabled = false
+  }
+
+  const falla = fallaDeAsignacion(respuesta, asignacion.solicitudId)
+  if (falla) {
+    // La ventana sigue abierta con lo escrito; reintentar reusa la misma solicitud.
+    console.error('[pagos] no se pudo asignar la cuenta de pago:', respuesta?.error)
+    errEl.textContent = falla
+    errEl.classList.remove('hidden')
+    return
+  }
+
+  ASIGNACION = null
+  document.getElementById('modalAsignar').classList.add('hidden')
+  // El aviso dice cuál cuenta quedó (banco y últimos 4); entra como texto, nunca como HTML.
+  mostrarExito(textoExitoAsignacion(respuesta.data, asignacion.numeroContrato))
+  await recargar()   // cuentas y motivos frescos: la fila pasa a «Marcar pagado»
+}
+
+// El clic en este botón no despliega el cronograma: la fila ya ignora los clics en botones.
+function onAsignarDesdeTabla(e) {
+  const c = CONTRATOS_PAGINA.find(x => x.id === e.currentTarget.dataset.contrato)
+  if (!c) return
+  abrirModalAsignar(c, {
+    contratoId: c.id, numeroContrato: c.numero_contrato, moneda: c.moneda, cliente: c.cliente, clienteId: null,
+  })
+}
+
 /* ============================================
    INICIALIZACIÓN
    ============================================ */
@@ -1607,6 +1854,13 @@ async function recargar() {
       if (!vigente()) return
       cuentasError = error
     }
+    if (!cuentasError) {
+      // Qué le falta a cada contrato sin cuenta. Cambia el texto VISIBLE de las filas (y su alto),
+      // así que se espera aquí —como mucho ESPERA_MOTIVOS_MS— para pintar la agenda una sola vez.
+      const conMotivos = await motivosSinCuenta(AGENDA_CACHE)
+      if (!vigente()) return
+      AGENDA_CACHE = conMotivos
+    }
     renderMetricas(metricas)
     actualizarResumenAgenda()
     renderAgenda()
@@ -1632,7 +1886,9 @@ async function recargar() {
   const ok = await verificarGestorCartera()
   if (!ok) return
 
-  await setupAdminShell({ welcomeFirstName: false, perfil: ok })
+  // Como en Clientes («Cambiar cuenta de pago»): el rol del perfil decide qué botones se ofrecen.
+  const perfil = await setupAdminShell({ welcomeFirstName: false, perfil: ok })
+  ROL_USUARIO = perfil?.rol ?? null
   await recargar()
 
   // Búsqueda y moneda: la agenda se filtra en memoria al instante; la tabla por
@@ -1715,6 +1971,11 @@ async function recargar() {
   document.getElementById('btnCancelarPago')?.addEventListener('click', cerrarModalPago)
   document.getElementById('formPago')?.addEventListener('submit', confirmarPago)
 
+  // Ventana «Asignar cuenta de pago»
+  document.getElementById('modalCloseAsignar')?.addEventListener('click', cerrarModalAsignar)
+  document.getElementById('btnCancelarAsignar')?.addEventListener('click', cerrarModalAsignar)
+  document.getElementById('formAsignar')?.addEventListener('submit', confirmarAsignacion)
+
   // Cerrar modales al click en overlay o ESC. Los modales con estado en memoria
   // (pago/import/export) se cierran por su función para limpiar las variables
   // (MODAL_CONTRATO_ID, IMPORT_PENDING, …) en vez de solo ocultarse.
@@ -1723,6 +1984,7 @@ async function recargar() {
     if (modal.id === 'modalPago') cerrarModalPago()
     else if (modal.id === 'modalImportar') cerrarModalImportar()
     else if (modal.id === 'modalExportar') cerrarModalExportar()
+    else if (modal.id === 'modalAsignar') cerrarModalAsignar()
     else modal.classList.add('hidden')
   }
   document.querySelectorAll('.modal-overlay').forEach(o => {
```

### SEGUIMIENTO de tu ronda anterior · 20261001233019: inicio del preflight (la guarda de aislamiento)
```sql
do $precondicion$
declare
  v_huella text;
begin
  -- La carga decide con lo que lee DESPUÉS de tomar sus candados. En REPEATABLE READ o
  -- SERIALIZABLE leería una fotografía anterior al candado (podría no ver una segunda cuenta
  -- registrada mientras esperaba) y elegiría a ciegas: no se aplica en otro aislamiento.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REZAGO PREFLIGHT: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
```

### SEGUIMIENTO · ensayo-prod-sin-escribir.sql: bloque final (veredicto PASA / FALLA / INCOMPLETO)
```sql
do $ensayo_fin$
declare
  c_generico constant text := 'Sin cuenta de pago — requiere conciliación';
  v_antes jsonb := current_setting('crm.ensayo_rezago_antes', true)::jsonb;
  v_carga jsonb := current_setting('crm.rezago_vinculos_resultado', true)::jsonb;
  v_despues jsonb;
  v_pagos jsonb := '[]'::jsonb;
  v_identidad jsonb := '[]'::jsonb;
  v_fallos text[] := array[]::text[];
  v_sin_probar text[] := array[]::text[];
  r record;
  v_caso record;
  v_bloqueado record;
  v_quien record;
  v_cuota uuid;
  v_resultado text;
  v_codigo text;
  v_mensaje text;
  v_bien boolean;
  v_probados integer := 0;
begin
  select coalesce(jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_despues
  from (select d.caso, count(*) as n from private.cuenta_pago_diagnostico() d group by d.caso) s;

  if v_antes is distinct from (v_carga -> 'antes') then
    v_fallos := v_fallos || 'el conteo previo hecho sin funciones no coincide con el de la regla nueva'::text;
  end if;

  -- 1) Pagos por conexión directa (sin usuario de la API: se espera el detalle).
  for r in
    (select distinct on (d.caso) d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'bloqueado'::text as que
     from private.cuenta_pago_diagnostico() d
     where d.caso <> 'ok'
       and exists (select 1 from public.cronograma_pagos cp
                   where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
     order by d.caso, d.es_demo, d.numero_contrato)
    union all
    (select d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'vinculado por la carga'
     from private.backfill_cuentas_p0xx b
     join private.cuenta_pago_diagnostico() d on d.contrato_id = b.contrato_id
     where b.tipo = 'vinculo' and b.marca_actor = 'migracion:rezago-vinculos:20261001' and b.insertada_en = now())
    union all
    (select d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'ya estaba bien'
     from private.cuenta_pago_diagnostico() d
     where d.caso = 'ok' and d.estado = 'activo'
       and not exists (select 1 from private.backfill_cuentas_p0xx b
                       where b.tipo = 'vinculo' and b.contrato_id = d.contrato_id and b.insertada_en = now())
       and exists (select 1 from public.cronograma_pagos cp
                   where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
     order by d.es_demo desc, d.numero_contrato
     limit 1)
  loop
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = r.contrato_id and cp.estado in ('pendiente', 'vencido')
    order by cp.fecha_programada, cp.numero_cuota
    limit 1;
    v_codigo := null;
    v_mensaje := null;
    if v_cuota is null then
      v_resultado := 'sin cuota pendiente que probar';
      v_bien := null;
      v_sin_probar := v_sin_probar
        || format('contrato %s (%s): no tiene ninguna cuota pendiente que probar', r.numero_contrato, r.que);
    else
      begin
        update public.cronograma_pagos
             set estado = 'pagado',
                 fecha_pago_real = (now() at time zone 'America/Lima')::date,
                 monto_pagado = monto_programado
           where id = v_cuota;
        v_resultado := 'pagada';
      exception when others then
        v_resultado := 'bloqueada';
        v_codigo := sqlstate;
        v_mensaje := sqlerrm;
      end;
      v_bien := case when r.caso = 'ok' then v_resultado = 'pagada'
                     else v_resultado = 'bloqueada' and v_codigo = '23514' and v_mensaje = r.mensaje end;
      if v_bien is not true then
        v_fallos := v_fallos
          || format('contrato %s (%s, caso %s): %s %s', r.numero_contrato, r.que, r.caso, v_resultado, coalesce(v_mensaje, ''));
      end if;
    end if;
    v_pagos := v_pagos || jsonb_build_object(
      'contrato', r.numero_contrato, 'caso', r.caso, 'que', r.que,
      'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
  end loop;

  -- Cobertura: un ensayo que no pudo probar algo NO es un ensayo que pasó. Cada caso bloqueado
  -- que exista tiene que haberse probado, y también un contrato que ya estaba bien.
  for v_caso in
    select c.caso, c.n
    from (select key as caso, value::text::integer as n from jsonb_each(v_despues)) c
    where c.caso <> 'ok' and c.n > 0
  loop
    if not exists (select 1 from jsonb_array_elements(v_pagos) x
                   where x ->> 'caso' = v_caso.caso and x ->> 'que' = 'bloqueado') then
      v_sin_probar := v_sin_probar
        || format('caso %s: hay %s contratos y ninguno con una cuota pendiente que probar', v_caso.caso, v_caso.n);
    end if;
  end loop;
  if not exists (select 1 from jsonb_array_elements(v_pagos) x where x ->> 'que' = 'ya estaba bien') then
    v_sin_probar := v_sin_probar || 'ningún contrato que ya estaba bien tiene una cuota pendiente que probar'::text;
  end if;

  -- 2) A quién se le dice el detalle. Va AL FINAL: la identidad simulada queda puesta hasta el
  --    error que deshace todo. No cambia de rol: solo los datos de sesión que lee el bloqueo.
  select d.contrato_id, d.numero_contrato, d.caso, d.mensaje into v_bloqueado
  from private.cuenta_pago_diagnostico() d
  where d.caso <> 'ok'
    and exists (select 1 from public.cronograma_pagos cp
                where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
  order by d.es_demo, d.numero_contrato
  limit 1;
  if not found then
    v_sin_probar := v_sin_probar || 'identidad: no hay ningún contrato bloqueado con una cuota pendiente'::text;
  else
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = v_bloqueado.contrato_id and cp.estado in ('pendiente', 'vencido')
    order by cp.fecha_programada, cp.numero_cuota
    limit 1;
    for v_quien in
      (select 'gestor de cartera'::text as papel, p.id, true as detalle
       from public.perfiles p
       where p.rol in ('admin', 'superadmin', 'operaciones') and p.activo
         and not exists (select 1 from crm.equipo e where e.perfil_id = p.id and e.activo is false)
       order by p.id limit 1)
      union all
      (select 'analista (no gestor)', p.id, false
       from public.perfiles p
       where p.rol = 'analista' and p.activo
       order by p.id limit 1)
    loop
      v_probados := v_probados + 1;
      perform set_config('request.jwt.claim.sub', v_quien.id::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims',
        jsonb_build_object('sub', v_quien.id, 'role', 'authenticated')::text, true);
      v_codigo := null;
      v_mensaje := null;
      begin
        update public.cronograma_pagos
             set estado = 'pagado',
                 fecha_pago_real = (now() at time zone 'America/Lima')::date,
                 monto_pagado = monto_programado
           where id = v_cuota;
        v_resultado := 'pagada';
      exception when others then
        v_resultado := 'bloqueada';
        v_codigo := sqlstate;
        v_mensaje := sqlerrm;
      end;
      v_bien := v_resultado = 'bloqueada' and v_codigo = '23514'
                and v_mensaje = case when v_quien.detalle then v_bloqueado.mensaje else c_generico end;
      if v_bien is not true then
        v_fallos := v_fallos
          || format('identidad %s: %s %s', v_quien.papel, v_resultado, coalesce(v_mensaje, ''));
      end if;
      v_identidad := v_identidad || jsonb_build_object(
        'quien', v_quien.papel, 'contrato', v_bloqueado.numero_contrato, 'caso', v_bloqueado.caso,
        'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
    end loop;
    if v_probados < 2 then
      v_sin_probar := v_sin_probar
        || 'identidad: falta un gestor de cartera vigente o un analista activo con quien probar'::text;
    end if;
  end if;

  raise exception 'ENSAYO_DESHECHO >> %', jsonb_build_object(
    'veredicto', case when cardinality(v_fallos) > 0 then 'FALLA'
                      when cardinality(v_sin_probar) > 0 then 'INCOMPLETO'
                      else 'PASA' end,
    'fallos', to_jsonb(v_fallos), 'sin_probar', to_jsonb(v_sin_probar),
    'conexion', jsonb_build_object('session_user', session_user::text, 'current_user', current_user::text),
    'antes_sin_funciones', v_antes, 'carga', v_carga, 'despues', v_despues,
    'pagos', v_pagos, 'identidad', v_identidad,
    'todo_como_se_esperaba', cardinality(v_fallos) = 0 and cardinality(v_sin_probar) = 0);
end;
$ensayo_fin$;
```
