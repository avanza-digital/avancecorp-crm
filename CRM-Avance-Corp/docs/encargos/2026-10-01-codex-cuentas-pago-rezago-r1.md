ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 1 (LEVEL 3: pagos, trigger SECURITY DEFINER, carga de datos) · Cuentas de pago: motivo del bloqueo y rezago de vínculos

Eres el revisor secundario. Sin base de datos, sin red y sin disco: todo lo que debes juzgar está transcrito abajo. Tu trabajo es REFUTAR. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo, línea o fragmento citado), riesgos y huecos de prueba, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; marca qué es hipótesis. No propongas `git reset --hard`, `git clean`, `rm -rf`, force push, DROP/TRUNCATE ni cambios directos en producción. El PRIMARY (Claude) decide con evidencia; tú asesoras.

## Negocio (decisiones de Miguel, 01/10/2026)
Una cuota del cronograma de un contrato solo puede marcarse «pagado» si el contrato tiene un vínculo en `crm.contrato_cuentas_pago` con una cuenta (`crm.cuentas_bancarias`) del MISMO cliente y la MISMA moneda. Lo impone el trigger `private.exigir_cuenta_pago_cronograma` (23514). La regla es correcta y NO se relaja. Quedaron 23 contratos viejos sin vínculo, y el mensaje era siempre «Sin cuenta de pago — requiere conciliación».

Censo real de producción (01/10/2026 18:24 Lima, 705 contratos): 682 ok · 1 sin vínculo con UNA cuenta activa en su moneda · 7 sin vínculo con DOS · 12 sin vínculo con cuenta solo en la otra moneda · 3 sin ninguna cuenta · 0 vínculos incoherentes · 3 ok cuya cuenta vinculada está inactiva (el bloqueo lo acepta a propósito). Nueve contratos reales ya tienen una cuota de fecha cumplida que no se puede pagar.

Miguel aprobó («dale»): (1) el bloqueo dice el motivo por caso; (2) un diagnóstico que clasifica cada contrato; (3) vincular SOLO donde hay una única cuenta activa posible; con dos o más NO se elige (lo confirma Operaciones); no se inventan cuentas ni se convierte moneda; no se toca el alta de contratos; (4) un cambio mínimo en Pagos del portal para que el motivo se vea (el portal revisa la cuenta ANTES de llamar al servidor y mostraba un texto fijo).

Quién registra pagos: el portal, con sesión de gestor de cartera (admin, superadmin u operaciones), por `crm.registrar_pago_con_cuenta` (INVOKER) → UPDATE de `public.cronograma_pagos` bajo la policy `cronograma_admin_actualiza` (`public.es_gestor_cartera()`).

## Decisiones a refutar
1. UNA regla (`private.cuenta_pago_diagnostico`, INVOKER, sin EXECUTE para nadie) que usan el bloqueo, la puerta y el censo; su caso `ok` debe ser EXACTAMENTE la condición del bloqueo.
2. El bloqueo conserva su consulta `for share of cp, ct`; solo en la rama de rechazo calcula el motivo. El detalle se dice únicamente a: conexión directa (`auth.role()` nulo o vacío Y `session_user` distinto de `authenticator`), rol `service_role`, o gestor de cartera con membresía CRM no revocada. A cualquier otro, el texto genérico de antes. Motivo: en el banco se MIDIÓ que analista, cliente y anon llegan al trigger por INSERT (corre antes de la RLS).
3. Puerta `crm.cuentas_pago_motivos_fn` (INVOKER) → `private.cuentas_pago_motivos_autorizado` (DEFINER) con la compuerta de `crm.cuentas_pago_contratos_fn`; solo devuelve los contratos pedidos que no están `ok`; sin ids no devuelve nada; tope 5000.
4. Carga: INSERT directo dentro de la migración (no existe función que vincule un contrato ya existente), regla «exactamente una cuenta ACTIVA del cliente en la moneda del contrato», `creado_por` NULL, rastro en `private.backfill_cuentas_p0xx` con marca propia, tope de 23, candado EXCLUSIVE sobre `crm.cuentas_bancarias` + contrato FOR SHARE, cancelación si el candidato tiene el perfil legado en conciliación, y postcondiciones que cancelan todo si el antes y el después no cuadran o si diagnóstico y bloqueo discrepan en algún contrato.
5. NO se sellan como «inferido» las cuotas que el contrato ya tenía pagadas antes del vínculo (se pagaron antes de existir; un sello no se borra y rompería la reversa).
6. Reversa completa que se niega si un contrato vinculado por la carga ya tiene un pago sellado, un cambio de cuenta o un PDF; reversa aparte solo del código; carga relanzable aparte (`vincular-rezago.sql`) con otra marca.
7. Ensayo en producción: la migración entera dentro de una transacción que termina SIEMPRE en `raise` (nada queda escrito), con pagos reales de prueba e identidad simulada por `set_config` de los claims.
8. La pantalla de Pagos del portal (que consumirá la puerta) se revisa en otro encargo.

## Preguntas
a. ¿Algún actor no autorizado obtiene el detalle (o un dato de otro cliente) por el bloqueo, por la puerta o por un canal lateral? Mira los NULL (`auth.role()`, `es_gestor_cartera()`, `membresia_crm_revocada()`), `session_user`, roles de API distintos de `authenticated`/`anon`/`service_role`, y el orden de los triggers BEFORE.
b. ¿Existe algún estado en que el bloqueo deje pagar y el diagnóstico no diga `ok`, o al revés?
c. Concurrencia: ¿la carga puede abrazarse con un pago, un alta de contrato con cuenta, un cambio de cuenta (F3) o un retiro (F4)? ¿El modo EXCLUSIVE sobre cuentas tiene un costo o un bloqueo que no vi (p. ej. el FK KEY SHARE del alta, lecturas `for share`)? ¿Hay un camino que escriba el vínculo sin el candado del contrato?
d. ¿Las postcondiciones pueden dar falso verde? ¿Falso rojo en producción que deje a Miguel sin poder aplicar?
e. ¿El preflight/postflight por md5 de `prosrc` puede fallar en producción por algo ajeno al texto (codificación, finales de línea, `create or replace` que normalice)?
f. Reversas: ¿borran de más, dejan algo, o pueden borrar un vínculo ya usado? ¿El criterio de «usado» tiene un hueco?
g. Ensayo de producción: ¿algo puede persistir pese al `raise` final (secuencias, NOTIFY, `set_config` de sesión, pg_net, estadísticas)? ¿Los `set_config` de claims pueden afectar a otra sesión del pooler?
h. ¿La puerta de lectura devuelve algo que la pantalla pueda usar mal (p. ej. el `mensaje` se insertará en HTML: ¿puede contener algo que no controle el servidor, como un `numero_contrato` con etiquetas)?
i. ¿Qué caso falta en las pruebas?

## Evidencia (lo que SÍ se ejecutó; nada en producción)
Banco Docker propio: Postgres 17.6 de Supabase con el ESQUEMA de producción volcado el 01/10/2026 14:59 (sin datos). Paridad de la pieza tocada: `md5(prosrc)` del bloqueo en el banco = `5efb8619e4342763ae77df2ee0bb1f61`, el mismo que devolvió producción en el censo de solo lectura que lanzó Miguel. Siembra ficticia: 15 contratos (`REZAGO-01…15`) que cubren los seis casos, con cuenta inactiva, cuenta de un tercero, contrato demo, vínculo incoherente (2), una cuota ya pagada sin sello, admin, operaciones, admin con membresía CRM revocada, analista y cliente.

- **Medido antes de escribir la migración**: con el bloqueo actual, analista, cliente y anon SÍ llegan al trigger por INSERT de una cuota `pagado` (el BEFORE corre antes de la RLS); por UPDATE y por la RPC no (0 filas).
- **Ciclo completo (`ciclo.sh`)**: 273 pasos, 0 fallos. Siembra → prueba ANTES (1059 comprobaciones) → cancelaciones (conciliación con los dos motivos, tope en 3, cuenta a medio registrar en otra sesión = `lock timeout` a los 5 s, bloqueo vivo alterado): el banco queda en ANTES → migración → prueba DESPUÉS (1496) → migración repetida (no cambia nada) → reversa → ANTES → reaplicar → negativas de la reversa (pago sellado, cambio de cuenta, fila en `contrato_pdf_jobs`, fila en `contrato_pdfs`, cada trigger de sello apagado: no cambia NADA) → reversa solo del código (bloqueo viejo, 3 funciones fuera, vínculos intactos y pagables; después `reversa.sql` todavía borra los no usados) → `vincular-rezago.sql` (en ANTES se niega; tras registrar una cuenta a un `otra_moneda` y a un `sin_cuenta` vincula exactamente esos dos con su marca del día; repetido no hace nada; `reversa.sql` no los toca) → registrador ×2 (1 fila, 1 sentencia, md5 del archivo).
- **Identidad**: conexión directa → detalle; claims de gestor → detalle; claims `service_role` → detalle; sesión real `psql -U authenticator` + `SET ROLE` SIN claims (rol anon, authenticated o service_role) → genérico; gestora revocada, analista, cliente, anon → genérico.
- **Camino feliz**: sustituyendo `private.cuenta_pago_diagnostico` por una versión que solo hace `raise`, pagar un contrato `ok` sigue funcionando (no la invoca). 200 pagos de contratos `ok`, alternando bloqueo anterior y nuevo, 10 series cada uno: 26–33 ms frente a 26–29 ms (ruido).
- **Mutantes** sobre el texto real (74 archivos): 24 los caza el postflight, 7 las postcondiciones de la carga, 3 su `STRICT`, 38 la prueba. Con la huella actualizada (para saltarse el postflight) los caza la prueba: detalle a todos (T3, analista por INSERT), sin `session_user` (T3, API sin claims), camino feliz que llama al diagnóstico (T4b), dejar pasar sin vínculo (T4b), sin `for share` (T4, `xmax` del vínculo), diagnóstico que cuenta inactivas (`STRICT`), `ok` sin mirar moneda o cliente (postcondición «no dicen lo mismo»; doble: T1), carga que elige con varias (postcondición), carga con cuenta inactiva (`STRICT`/rastro), carga sin rastro (postcondición), autorizador sin compuerta / que devuelve `ok` / sin tope (T7), EXECUTE de más o puerta DEFINER (postflight; doble: T7 por catálogo), mensaje con número de cuenta (T1 texto exacto y T9). **Sobrevive uno a las pruebas secuenciales**: quitar el `lock table` (solo lo detecta el tramo de concurrencia: la migración real espera y cae por `lock timeout`; el mutante aplica en 0 s).
- **Trinquetes** (`private.assert_*()` + censo de contadores): idénticos sin y con la migración (38 líneas: 26 pasan, 10 caen igual por falta de datos en el banco).
- **Ensayo de producción corrido contra el banco**, en ANTES y con la migración ya aplicada: termina en `ENSAYO_DESHECHO`, `todo_como_se_esperaba = true`, foto y conteos idénticos antes y después (bitácora incluida). En ANTES: `antes_sin_funciones` = `carga.antes` = `{ok 2, una_cuenta 4, varias_cuentas 2, otra_moneda 2, sin_cuenta 3, cuenta_no_corresponde 2}`; `despues` = `{ok 6, …, una_cuenta 0}`; pagos: los 4 casos bloqueados con `23514` y su mensaje, los 4 vinculados «pagada», un `ok` previo «pagada»; identidad: gestor → detalle, analista → genérico. Si la propia migración se niega dentro del ensayo, el error es el suyo y tampoco queda nada.
- **Auditor interno (auditor-rls)**: CHANGES_REQUESTED sin P0; no encontró camino de fuga ni rotura de la equivalencia. ACEPTADO: ledger con el OK de Miguel; preflight/postflight con md5 de las cuatro funciones y mismo dueño; carga relanzable aparte (`vincular-rezago.sql`) en vez de relanzar la migración; guarda de S1 como cancelación; candado EXCLUSIVE (el SHARE ROW EXCLUSIVE permitía un abrazo con el retiro o el alta: ellos toman la fila de la cuenta FOR UPDATE y luego escriben; la carga pedía KEY SHARE por el FK); `session_user <> 'authenticator'` en la rama sin rol; reversa que también mira PDF y triggers de sello y acepta el bloqueo ya revertido; conteo de discrepancias diagnóstico/bloqueo como postcondición; ensayo con identidad simulada y un pago de contrato `ok`. RECHAZADO: añadir a `test-rls.mjs` casos HTTP del MENSAJE del bloqueo por rol y una sesión `operaciones` (ese gate no se puede correr aquí; un caso sin ejecutar puede dar falso rojo a otras sesiones). Queda como hueco declarado.
- `npm run check:scripts`: PASS. `npm run test:rls:preflight` (variables ficticias, sin conexión): PASS. Matriz HTTP completa (`test-rls.mjs`): NOT RUN.

## Huecos declarados
- Sin prueba a dos sesiones de un pago EN VUELO contra la carga o contra la reversa (solo se probó el candado de la tabla de cuentas).
- `auth.uid()` y `auth.role()` son los de la imagen; no hay PostgREST real (la API se simula por sesión); `anon`/`service_role` sobre la puerta, solo por catálogo.
- Comportamiento previo de F5 que sigue: si se corrige la FECHA de una cuota pagada antes del vínculo, su sello la marca «inferido» en la cuenta vinculada (y desde entonces `reversa.sql` se niega).
- La pantalla de Pagos del portal va en OTRO encargo (junto con una segunda migración, «asignar cuenta de pago»); aquí solo se revisa el servidor de esta.

## Archivos

### supabase/migrations/20261001233019_crm_cuentas_pago_motivo_y_rezago.sql (NUEVA, completa)
```sql
-- Cuentas de pago · el bloqueo dice POR QUÉ, diagnóstico por contrato y carga del rezago (01/10/2026).
--
-- Contexto: desde P-0XX S3 (20260925194026) una cuota solo pasa a 'pagado' si el contrato tiene
-- un vínculo en crm.contrato_cuentas_pago con una cuenta del MISMO cliente y la MISMA moneda. La
-- regla es correcta y NO se relaja. Quedaron 23 contratos viejos sin vínculo y un único mensaje
-- («Sin cuenta de pago — requiere conciliación») que no decía qué faltaba.
--
-- Qué hace:
--   1. private.cuenta_pago_diagnostico: UNA sola regla que clasifica cada contrato y redacta el
--      motivo. La usan el bloqueo (solo al rechazar), la puerta de lectura y el censo.
--        ok · una_cuenta · varias_cuentas · otra_moneda · sin_cuenta · cuenta_no_corresponde
--   2. private.exigir_cuenta_pago_cronograma: mismo bloqueo, mismo 23514, mismos triggers. El pago
--      válido recorre exactamente la consulta de antes y no llama al diagnóstico. Al rechazar dice
--      el motivo, pero solo a quien puede registrar pagos (un BEFORE INSERT corre antes de la RLS:
--      a cualquier otro se le sigue dando el texto genérico, para no contar datos de un cliente).
--   3. crm.cuentas_pago_motivos_fn (puerta INVOKER → private.cuentas_pago_motivos_autorizado,
--      DEFINER): el motivo de los contratos pedidos que no se pueden pagar, con la misma compuerta
--      que crm.cuentas_pago_contratos_fn. La pantalla de Pagos del portal revisa la cuenta ANTES de
--      llamar al servidor; sin esta lectura el mensaje nuevo no llegaría a nadie.
--   4. Carga del rezago: a cada contrato SIN vínculo cuyo cliente tiene EXACTAMENTE UNA cuenta
--      activa en la moneda del contrato le crea el vínculo. Es la regla del backfill S1
--      (20260925153226) y su mismo rastro: creado_por NULL, fila en private.backfill_cuentas_p0xx
--      con marca propia, y la bitácora de siempre (trg_audit_contrato_cuentas_pago →
--      public.audit_log). Con dos o más cuentas NO se elige: el contrato queda como está. No
--      inventa cuentas, no convierte moneda y no usa cuentas inactivas. S1 además apartaba los
--      contratos cuyo perfil legado traía una instrucción inválida o distinta para el mismo CCI:
--      aquí, si un candidato tuviera esa marca, la carga entera se cancela (no se vincula a
--      ciegas). En el censo del 01/10/2026 ninguno de los 23 la tiene.
--
-- Por qué una inserción directa y no una función existente: no hay ninguna que vincule un contrato
-- YA existente. crm.crear_contrato_con_cuenta solo vincula al dar de alta;
-- crm.actualizar_contrato_con_cuenta nunca escribe el vínculo; crm.cambiar_cuenta_pago_contratos
-- rechaza los contratos sin cuenta, y su historial (crm.contrato_cuenta_pago_cambios) exige una
-- cuenta ANTERIOR y un respaldo del cliente: es para cambios pedidos por el cliente, no para un
-- primer vínculo. El único antecedente es el backfill S1, y se sigue su patrón.
--
-- Lo que NO hace: no toca el alta de contratos, ni las cuentas, ni relaja el bloqueo. No sella las
-- cuotas que esos contratos ya tenían pagadas (crm.cuotas_cuenta_pagada): se pagaron antes de que
-- existiera el vínculo y atribuírselas a esta cuenta sería inventar un hecho (y un sello no se
-- borra, así que la carga dejaría de poder revertirse). No crea ni cambia triggers, tablas ni
-- policies. De public solo LEE contratos (con FOR SHARE durante la carga); el bloqueo sigue
-- colgado de los mismos dos triggers de public.cronograma_pagos. OK de Miguel: 01/10/2026.
--
-- Repetirla es inofensivo (no crea vínculos ni rastro nuevos) y se niega si alguna de sus cuatro
-- funciones ya existe con otro cuerpo, para no pisar una migración posterior. Para vincular más
-- adelante los contratos a los que Operaciones les registre su cuenta NO se relanza este archivo:
-- se lanza ../scripts/cuentas-pago-rezago/vincular-rezago.sql (la misma carga, sola).
-- Reversión: ../scripts/cuentas-pago-rezago/reversa.sql (borra solo los vínculos de esta carga y
-- se niega si alguno ya registró un pago, un cambio de cuenta o un PDF) y reversa-solo-codigo.sql.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
declare
  v_huella text;
begin
  select pg_catalog.md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.exigir_cuenta_pago_cronograma()');
  -- La huella de P-0XX S3 (primera vez) o la de esta migración (repetición).
  if v_huella is null
     or v_huella not in ('5efb8619e4342763ae77df2ee0bb1f61', 'd7618dcf85653943e62745513b3c4938') then
    raise exception 'REZAGO PREFLIGHT: el bloqueo de pagos vivo (%) no es el esperado; no se toca',
      coalesce(v_huella, 'no existe');
  end if;
  -- Las otras tres funciones: o no existen todavía, o son exactamente las de esta migración.
  if exists (
    select 1
    from (values
      ('private.cuenta_pago_diagnostico(uuid[])', 'a1dfb0c46b9365df308801bab9d5481a'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', '4c45dbbfd85f5de82372b343b0b1dfc0'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', '45898bb671a3bf536375a0fb5fb33ec6')
    ) as f(firma, huella)
    join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
    where pg_catalog.md5(p.prosrc) <> f.huella
  ) then
    raise exception 'REZAGO PREFLIGHT: alguna función de esta migración ya existe con otro cuerpo; no se pisa';
  end if;
  if pg_catalog.to_regclass('crm.contrato_cuentas_pago') is null
     or pg_catalog.to_regclass('crm.cuentas_bancarias') is null
     or pg_catalog.to_regclass('crm.cuotas_cuenta_pagada') is null
     or pg_catalog.to_regclass('crm.contrato_cuenta_pago_cambios') is null
     or pg_catalog.to_regclass('public.contratos') is null
     or pg_catalog.to_regclass('public.cronograma_pagos') is null
     or pg_catalog.to_regclass('private.backfill_cuentas_p0xx') is null
     or pg_catalog.to_regclass('private.conciliacion_cuentas_p0xx') is null
     or pg_catalog.to_regprocedure('public.es_gestor_cartera()') is null
     or pg_catalog.to_regprocedure('private.membresia_crm_revocada()') is null
     or pg_catalog.to_regprocedure('private.log_audit_crm()') is null
     or pg_catalog.to_regprocedure('auth.role()') is null then
    raise exception 'REZAGO PREFLIGHT: faltan dependencias';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'public.contratos'::regclass and not a.attisdropped
        and a.attname in ('id', 'numero_contrato', 'cliente_id', 'moneda', 'estado', 'es_demo')) <> 6
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.cuentas_bancarias'::regclass and not a.attisdropped
           and a.attname in ('id', 'cliente_id', 'moneda', 'activa')) <> 4
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.contrato_cuentas_pago'::regclass and not a.attisdropped
           and a.attname in ('id', 'contrato_id', 'cuenta_bancaria_id', 'creado_por')) <> 4
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'private.backfill_cuentas_p0xx'::regclass and not a.attisdropped
           and a.attname in ('tipo', 'fila_id', 'cliente_id', 'contrato_id', 'marca_actor',
                             'insertada_en', 'revertida_en')) <> 7
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'private.conciliacion_cuentas_p0xx'::regclass and not a.attisdropped
           and a.attname in ('clase', 'cliente_id', 'moneda', 'motivo')) <> 4 then
    raise exception 'REZAGO PREFLIGHT: alguna tabla no tiene las columnas esperadas';
  end if;
  -- El bloqueo debe seguir colgado de sus dos triggers, habilitados.
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REZAGO PREFLIGHT: los triggers del bloqueo de pagos no están como se espera';
  end if;
  -- La carga confía en estos dos triggers del vínculo: coherencia cliente/moneda y bitácora.
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass
        and t.tgname in ('trg_contrato_cuenta_pago_coherente', 'trg_audit_contrato_cuentas_pago')
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REZAGO PREFLIGHT: faltan los triggers de coherencia o de bitácora del vínculo';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE')
     or not pg_catalog.has_schema_privilege('authenticated', 'crm', 'USAGE') then
    raise exception 'REZAGO PREFLIGHT: authenticated necesita USAGE sobre crm y private para la puerta INVOKER';
  end if;
  -- El diagnóstico es INVOKER y sin EXECUTE para nadie: solo funciona porque el bloqueo, el
  -- autorizador y él tienen el MISMO dueño (quien aplica), que además debe leer contratos,
  -- vínculos y cuentas sin RLS.
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'REZAGO PREFLIGHT: el dueño de las funciones debe tener bypassrls';
  end if;
  if (select pg_catalog.pg_get_userbyid(p.proowner) from pg_catalog.pg_proc p
      where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure)
     is distinct from current_user::text then
    raise exception 'REZAGO PREFLIGHT: quien aplica (%) no es el dueño del bloqueo de pagos', current_user;
  end if;
end;
$precondicion$;

-- ── 1. La regla, una sola vez ────────────────────────────────────────────────────────────────
-- INVOKER y sin EXECUTE para nadie: solo la llaman el bloqueo y el autorizador (ambos DEFINER, del
-- mismo dueño) y quien aplica migraciones (censo). Con NULL clasifica todos los contratos.
create or replace function private.cuenta_pago_diagnostico(p_contrato_ids uuid[] default null)
returns table (
  contrato_id uuid,
  numero_contrato text,
  cliente_id uuid,
  moneda text,
  estado text,
  es_demo boolean,
  caso text,
  cuentas_en_moneda integer,
  cuentas_otra_moneda integer,
  mensaje text
)
language sql
stable
security invoker
set search_path to ''
as $function$
  select
    ct.id,
    ct.numero_contrato,
    ct.cliente_id,
    ct.moneda,
    ct.estado,
    ct.es_demo,
    d.caso,
    q.en_moneda,
    q.otra_moneda,
    case d.caso
      when 'ok' then null
      when 'cuenta_no_corresponde' then pg_catalog.format(
        'Contrato %s: su cuenta de pago no es del cliente o de la moneda del contrato; no se paga hasta corregirla.',
        ct.numero_contrato)
      when 'una_cuenta' then pg_catalog.format(
        'Contrato %s sin cuenta de pago: el cliente ya tiene una cuenta en %s; falta vincularla a este contrato.',
        ct.numero_contrato, m.del_contrato)
      when 'varias_cuentas' then pg_catalog.format(
        'Contrato %s sin cuenta de pago: el cliente tiene %s cuentas en %s; confirma con él en cuál cobra este contrato.',
        ct.numero_contrato, q.en_moneda, m.del_contrato)
      when 'otra_moneda' then pg_catalog.format(
        'Contrato %s sin cuenta de pago: el contrato es en %s y el cliente solo tiene cuenta en %s; pídele una en %s.',
        ct.numero_contrato, m.del_contrato, m.la_otra, m.del_contrato)
      else pg_catalog.format(
        'Contrato %s sin cuenta de pago: el cliente no tiene ninguna cuenta bancaria vigente; pídele una en %s.',
        ct.numero_contrato, m.del_contrato)
    end
  from public.contratos ct
  left join crm.contrato_cuentas_pago cp on cp.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  -- Solo cuentan las cuentas ACTIVAS del cliente: una inactiva no sirve para un vínculo nuevo.
  cross join lateral (
    select (pg_catalog.count(*) filter (where a.moneda = ct.moneda))::integer as en_moneda,
           (pg_catalog.count(*) filter (where a.moneda <> ct.moneda))::integer as otra_moneda
    from crm.cuentas_bancarias a
    where a.cliente_id = ct.cliente_id
      and a.activa is true
  ) q
  -- 'ok' es EXACTAMENTE la condición del bloqueo: hay vínculo y su cuenta (activa o no) es del
  -- mismo cliente y de la misma moneda del contrato.
  cross join lateral (
    select case
      when cp.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
      when cp.id is not null then 'cuenta_no_corresponde'
      when q.en_moneda = 1 then 'una_cuenta'
      when q.en_moneda > 1 then 'varias_cuentas'
      when q.otra_moneda > 0 then 'otra_moneda'
      else 'sin_cuenta'
    end as caso
  ) d
  cross join lateral (
    select case ct.moneda when 'PEN' then 'soles' when 'USD' then 'dólares' else ct.moneda end as del_contrato,
           case ct.moneda when 'PEN' then 'dólares' when 'USD' then 'soles' else 'otra moneda' end as la_otra
  ) m
  where p_contrato_ids is null
     or ct.id = any (p_contrato_ids);
$function$;
revoke all on function private.cuenta_pago_diagnostico(uuid[]) from public, anon, authenticated, service_role;

-- ── 2. El bloqueo: igual de estricto; al rechazar dice el motivo ─────────────────────────────
create or replace function private.exigir_cuenta_pago_cronograma()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rol text;
  v_mensaje text;
begin
  if new.estado is distinct from 'pagado' then
    return new;
  end if;

  -- La cuenta vinculada puede haber sido versionada y estar inactiva: sigue
  -- siendo la instruccion contractual. Bloqueamos la fila del vinculo y del
  -- contrato hasta el COMMIT para no validar una fotografia que se borra o
  -- cambia de cliente/moneda durante el registro del pago.
  perform 1
  from crm.contrato_cuentas_pago cp
  join public.contratos ct on ct.id = cp.contrato_id
  join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  where cp.contrato_id = new.contrato_id
    and cb.cliente_id = ct.cliente_id
    and cb.moneda = ct.moneda
  for share of cp, ct;

  if not found then
    -- Solo aquí, con el pago YA rechazado, se calcula el motivo: el pago válido no llega a esta
    -- rama. El motivo nombra la moneda y cuántas cuentas tiene el cliente, así que se le dice
    -- únicamente a quien puede registrar pagos:
    --   · una conexión directa a la base (sin rol de la API y que NO entra por la API: la API
    --     siempre se conecta como authenticator);
    --   · el rol de servicio;
    --   · un gestor de cartera con la membresía CRM vigente.
    -- A cualquier otro —este trigger corre ANTES de la RLS en un INSERT— se le da el texto
    -- genérico de siempre.
    v_rol := nullif((select auth.role()), '');
    if (v_rol is null and session_user is distinct from 'authenticator')
       or v_rol = 'service_role'
       or ((select public.es_gestor_cartera()) is true
           and (select private.membresia_crm_revocada()) is false) then
      select d.mensaje into v_mensaje
      from private.cuenta_pago_diagnostico(array[new.contrato_id]) d;
    end if;
    raise exception using
      errcode = '23514',
      message = coalesce(v_mensaje, 'Sin cuenta de pago — requiere conciliación');
  end if;
  return new;
end;
$function$;
revoke all on function private.exigir_cuenta_pago_cronograma() from public, anon, authenticated, service_role;

-- ── 3. Lectura del motivo para la pantalla de Pagos ──────────────────────────────────────────
-- DEFINER porque authenticated no tiene permisos sobre vínculos ni cuentas. Misma compuerta que
-- crm.cuentas_pago_contratos_fn: gestor de cartera (admin, superadmin u operaciones) y sin la
-- membresía CRM revocada. Nunca clasifica «todos»: sin ids no devuelve nada.
create or replace function private.cuentas_pago_motivos_autorizado(p_contrato_ids uuid[])
returns table (contrato_id uuid, caso text, mensaje text)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if (select private.membresia_crm_revocada()) is not false
     or (select public.es_gestor_cartera()) is not true then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;
  if coalesce(pg_catalog.cardinality(p_contrato_ids), 0) > 5000 then
    raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  end if;
  if coalesce(pg_catalog.cardinality(p_contrato_ids), 0) = 0 then
    return;
  end if;

  return query
  select d.contrato_id, d.caso, d.mensaje
  from private.cuenta_pago_diagnostico(p_contrato_ids) d
  where d.caso <> 'ok';
end;
$function$;
revoke all on function private.cuentas_pago_motivos_autorizado(uuid[]) from public, anon, authenticated, service_role;
grant execute on function private.cuentas_pago_motivos_autorizado(uuid[]) to authenticated;

create or replace function crm.cuentas_pago_motivos_fn(p_contrato_ids uuid[])
returns table (contrato_id uuid, caso text, mensaje text)
language sql
stable
security invoker
set search_path to ''
as $function$
  select * from private.cuentas_pago_motivos_autorizado(p_contrato_ids);
$function$;
revoke all on function crm.cuentas_pago_motivos_fn(uuid[]) from public, anon, authenticated, service_role;
grant execute on function crm.cuentas_pago_motivos_fn(uuid[]) to authenticated;

comment on function private.cuenta_pago_diagnostico(uuid[]) is 'La regla ÚNICA de la cuenta de pago por contrato: caso (ok, una_cuenta, varias_cuentas, otra_moneda, sin_cuenta, cuenta_no_corresponde), cuántas cuentas ACTIVAS tiene el cliente en la moneda del contrato y en la otra, y el motivo redactado para la persona (sin números de cuenta, CCI ni documentos). ok = la condición exacta del bloqueo de pagos. NULL = todos los contratos (censo). INVOKER y sin EXECUTE para nadie: solo la usan el bloqueo, el autorizador de la puerta y quien aplica migraciones.';
comment on function private.exigir_cuenta_pago_cronograma() is 'Trigger BEFORE en public.cronograma_pagos: una cuota solo pasa a pagado si el contrato tiene vínculo con una cuenta del mismo cliente y moneda (bloquea vínculo y contrato FOR SHARE hasta el COMMIT). Al rechazar (23514) dice el motivo de private.cuenta_pago_diagnostico solo a quien puede registrar pagos (conexión directa que no entra por la API, rol de servicio, o gestor de cartera con membresía CRM vigente); a los demás, el texto genérico. El pago válido no calcula el motivo. SECURITY DEFINER porque quien registra el pago no tiene permisos sobre vínculos ni cuentas.';
comment on function private.cuentas_pago_motivos_autorizado(uuid[]) is 'Motivo por el que no se pueden pagar los contratos pedidos (solo los que NO están ok). Compuerta de crm.cuentas_pago_contratos_fn: gestor de cartera sin la membresía CRM revocada; máximo 5000 ids; sin ids no devuelve nada. SECURITY DEFINER porque authenticated no tiene permisos sobre vínculos ni cuentas.';
comment on function crm.cuentas_pago_motivos_fn(uuid[]) is 'Puerta (INVOKER) del motivo por el que un contrato no se puede pagar: contrato_id, caso y mensaje para la persona. La usa Pagos del portal. Solo gestor de cartera.';

-- ── 4. Carga del rezago: solo donde hay UNA cuenta activa posible ────────────────────────────
-- Candados. La tabla de cuentas en modo EXCLUSIVE, antes que nada: espera a que termine quien
-- esté registrando, cambiando o retirando una cuenta (esos caminos bloquean primero la fila de la
-- cuenta y después escriben; tomar aquí un candado más débil permitiría un abrazo mortal) y,
-- mientras dura la carga, nadie mueve cuentas. Las lecturas siguen permitidas: registrar un pago
-- solo LEE cuentas. Después, cada contrato FOR SHARE —el orden de un pago: contrato → vínculo— y
-- bajo ese candado se vuelve a clasificar. Como en S1, no se toma el candado consultivo del alta.
-- Si la espera pasa de lock_timeout, se cancela todo sin dejar nada a medias.
lock table crm.cuentas_bancarias in exclusive mode;

do $rezago$
declare
  c_marca constant text := 'migracion:rezago-vinculos:20261001';
  -- El rezago conocido es de 23 contratos (censo del 01/10/2026). Más candidatos que eso no es
  -- rezago: es que algo cambió (p. ej. vínculos borrados) y no se vincula a ciegas.
  c_tope constant integer := 23;
  v_antes jsonb;
  v_despues jsonb;
  v_candidatos integer;
  v_hechos integer := 0;
  v_rastro integer;
  v_discrepancias integer;
  v_fila record;
  v_d record;
  v_cuenta uuid;
  v_vinculo uuid;
  v_numeros text[] := '{}';
begin
  select coalesce(pg_catalog.jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_antes
  from (select d.caso, pg_catalog.count(*) as n
        from private.cuenta_pago_diagnostico() d group by d.caso) s;

  v_candidatos := coalesce((v_antes ->> 'una_cuenta')::integer, 0);
  if v_candidatos > c_tope then
    raise exception 'REZAGO: % contratos por vincular y el rezago conocido es de %; no se toca nada',
      v_candidatos, c_tope;
  end if;

  for v_fila in
    select d.contrato_id
    from private.cuenta_pago_diagnostico() d
    where d.caso = 'una_cuenta'
    order by d.contrato_id
  loop
    perform 1 from public.contratos ct where ct.id = v_fila.contrato_id for share;

    select d.cliente_id, d.moneda, d.numero_contrato into v_d
    from private.cuenta_pago_diagnostico(array[v_fila.contrato_id]) d
    where d.caso = 'una_cuenta';
    if not found then
      continue;
    end if;

    -- La guarda de S1: si el perfil legado de ese cliente y moneda quedó marcado con una
    -- instrucción inválida o distinta para el mismo CCI, la única cuenta no es inequívoca.
    if exists (
      select 1 from private.conciliacion_cuentas_p0xx x
      where x.clase = 'perfil' and x.cliente_id = v_d.cliente_id and x.moneda = v_d.moneda
        and x.motivo in ('perfil_invalido', 'mismo_cci_datos_distintos')
    ) then
      raise exception 'REZAGO: el contrato % tiene una sola cuenta, pero su perfil legado quedó en conciliación; no se vincula nada hasta que Operaciones lo confirme',
        v_d.numero_contrato;
    end if;

    -- STRICT: si no es exactamente una, la migración entera se cancela.
    select cb.id into strict v_cuenta
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_d.cliente_id
      and cb.moneda = v_d.moneda
      and cb.activa is true;

    -- El trigger de coherencia cancela toda la migración si la pareja no vale.
    insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id, creado_por)
    values (v_fila.contrato_id, v_cuenta, null)
    returning id into v_vinculo;

    insert into private.backfill_cuentas_p0xx (tipo, fila_id, cliente_id, contrato_id, marca_actor)
    values ('vinculo', v_vinculo, v_d.cliente_id, v_fila.contrato_id, c_marca);

    v_hechos := v_hechos + 1;
    v_numeros := v_numeros || v_d.numero_contrato;
  end loop;

  select coalesce(pg_catalog.jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_despues
  from (select d.caso, pg_catalog.count(*) as n
        from private.cuenta_pago_diagnostico() d group by d.caso) s;

  -- Nada de pérdida silenciosa: si el antes y el después no cuadran, se cancela todo.
  if v_hechos <> v_candidatos then
    raise exception 'REZAGO: había % contratos por vincular y se vincularon %', v_candidatos, v_hechos;
  end if;
  if coalesce((v_despues ->> 'una_cuenta')::integer, 0) <> 0 then
    raise exception 'REZAGO: quedaron contratos con una sola cuenta posible sin vincular: %', v_despues;
  end if;
  if coalesce((v_despues ->> 'ok')::integer, 0) <> coalesce((v_antes ->> 'ok')::integer, 0) + v_hechos then
    raise exception 'REZAGO: los contratos ok no subieron en lo vinculado (antes %, después %, vinculados %)',
      v_antes, v_despues, v_hechos;
  end if;
  if (v_despues - 'ok' - 'una_cuenta') is distinct from (v_antes - 'ok' - 'una_cuenta') then
    raise exception 'REZAGO: cambió un caso que la carga no debía tocar (antes %, después %)', v_antes, v_despues;
  end if;
  select pg_catalog.count(*) into v_rastro
  from private.backfill_cuentas_p0xx b
  join crm.contrato_cuentas_pago l on l.id = b.fila_id and l.contrato_id = b.contrato_id
  join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id and cb.cliente_id = b.cliente_id and cb.activa is true
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and b.insertada_en = pg_catalog.now();
  if v_rastro <> v_hechos then
    raise exception 'REZAGO: el rastro (%) no coincide con los vínculos creados (%)', v_rastro, v_hechos;
  end if;
  -- La regla vive en dos sitios (la consulta del bloqueo y el caso 'ok' del diagnóstico): con los
  -- contratos reales delante, no puede haber ni uno en que digan cosas distintas.
  select pg_catalog.count(*) into v_discrepancias
  from private.cuenta_pago_diagnostico() d
  where (d.caso = 'ok') is distinct from exists (
    select 1
    from crm.contrato_cuentas_pago cp
    join public.contratos ct on ct.id = cp.contrato_id
    join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
    where cp.contrato_id = d.contrato_id
      and cb.cliente_id = ct.cliente_id
      and cb.moneda = ct.moneda);
  if v_discrepancias <> 0 then
    raise exception 'REZAGO: en % contratos el diagnóstico y el bloqueo no dicen lo mismo', v_discrepancias;
  end if;

  -- Para la última sentencia del archivo (después del COMMIT): el conteo antes y después.
  perform pg_catalog.set_config('crm.rezago_vinculos_resultado',
    pg_catalog.jsonb_build_object('antes', v_antes, 'despues', v_despues,
      'vinculados', v_hechos, 'contratos', pg_catalog.to_jsonb(v_numeros), 'marca', c_marca)::text, false);
  raise notice 'REZAGO: antes % · después % · vinculados % %', v_antes, v_despues, v_hechos, v_numeros;
end;
$rezago$;

-- ── 5. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  for v_f in
    select * from (values
      ('private.exigir_cuenta_pago_cronograma()', null, true, 'v', 'd7618dcf85653943e62745513b3c4938'),
      ('private.cuenta_pago_diagnostico(uuid[])', null, false, 's', 'a1dfb0c46b9365df308801bab9d5481a'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', 'authenticated', true, 's', '4c45dbbfd85f5de82372b343b0b1dfc0'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', 'authenticated', false, 's', '45898bb671a3bf536375a0fb5fb33ec6')
    ) as f(firma, rol, definer, volatilidad, huella)
  loop
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure
                     and pg_catalog.md5(p.prosrc) = v_f.huella
                     and p.prosecdef = v_f.definer and p.provolatile = v_f.volatilidad
                     and pg_catalog.pg_get_userbyid(p.proowner) = current_user::text) then
      raise exception 'REZAGO POSTFLIGHT: cuerpo, DEFINER/INVOKER, volatilidad o dueño inesperados en %', v_f.firma;
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
      raise exception 'REZAGO POSTFLIGHT: EXECUTE, search_path o comentario inesperados en %', v_f.firma;
    end if;
  end loop;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REZAGO POSTFLIGHT: los triggers del bloqueo de pagos no quedaron como estaban';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

-- Constancia del conteo por caso antes y después de ESTA corrida (queda en la salida).
select pg_catalog.current_setting('crm.rezago_vinculos_resultado', true)::jsonb as rezago_vinculos;
```

### supabase/scripts/cuentas-pago-rezago/reversa.sql (NUEVA, completa; incluye el cuerpo ANTERIOR del bloqueo, byte a byte de 20260925194026)
```sql
-- REVERSA COMPLETA de 20261001233019_crm_cuentas_pago_motivo_y_rezago.sql: datos y código. GENERADA por generar-derivados.py.
--   · Borra SOLO los vínculos que creó la carga de la migración (marca 'migracion:rezago-vinculos:20261001'
--     en private.backfill_cuentas_p0xx) y les pone revertida_en. La bitácora (public.audit_log)
--     guarda el borrado. Los vínculos de cargas posteriores (vincular-rezago.sql, otra marca) no se tocan.
--   · Repone el bloqueo anterior y quita las tres funciones nuevas (si el código ya se revirtió
--     con reversa-solo-codigo.sql, esta parte no cambia nada).
-- Se NIEGA, sin cambiar nada, si algún contrato vinculado por la carga ya registró un pago
-- (crm.cuotas_cuenta_pagada), un cambio de cuenta (crm.contrato_cuenta_pago_cambios) o un PDF de
-- contrato (su fotografía lleva la cuenta): desde ese momento el vínculo es una instrucción usada
-- y no se borra. Para volver solo al mensaje anterior sin tocar vínculos: reversa-solo-codigo.sql.
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
declare
  v_huella text;
begin
  select pg_catalog.md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.exigir_cuenta_pago_cronograma()');
  -- El de la migración, o el anterior si el código ya se revirtió.
  if v_huella is null or v_huella not in ('d7618dcf85653943e62745513b3c4938', '5efb8619e4342763ae77df2ee0bb1f61') then
    raise exception 'REVERSA: el bloqueo vivo (%) no es el de la migración 20261001233019 ni el anterior; no se toca',
      coalesce(v_huella, 'no existe');
  end if;
  if exists (
    select 1
    from (values
      ('private.cuenta_pago_diagnostico(uuid[])', 'a1dfb0c46b9365df308801bab9d5481a'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', '4c45dbbfd85f5de82372b343b0b1dfc0'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', '45898bb671a3bf536375a0fb5fb33ec6')
    ) as f(firma, huella)
    join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
    where pg_catalog.md5(p.prosrc) <> f.huella
  ) then
    raise exception 'REVERSA: alguna función de la migración cambió después; no se toca';
  end if;
end;
$precondicion$;

do $datos$
declare
  c_marca constant text := 'migracion:rezago-vinculos:20261001';
  v_usado text;
  v_esperados integer;
  v_borrados integer;
begin
  if pg_catalog.to_regclass('crm.cuotas_cuenta_pagada') is null
     or pg_catalog.to_regclass('crm.contrato_cuenta_pago_cambios') is null
     or pg_catalog.to_regclass('private.contrato_pdf_jobs') is null
     or pg_catalog.to_regclass('private.contrato_pdfs') is null then
    raise exception 'REVERSA: faltan las tablas con las que se sabe si un vínculo ya se usó; no se borra nada';
  end if;
  -- El criterio «ya registró un pago» depende de que cada pago selle su cuenta.
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert',
                         'trg_cronograma_pagos_20_sellar_cuenta_update')
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REVERSA: los triggers que sellan la cuenta de cada pago no están habilitados; no se puede saber si un vínculo ya se usó';
  end if;

  -- Candados en el orden de un pago: el contrato primero (FOR UPDATE, por id). Un pago en curso
  -- termina antes; uno nuevo espera y, al seguir, ya no encuentra el vínculo y se rechaza.
  perform 1
  from public.contratos ct
  where ct.id in (select b.contrato_id from private.backfill_cuentas_p0xx b
                  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null)
  order by ct.id
  for update;

  select ct.numero_contrato into v_usado
  from private.backfill_cuentas_p0xx b
  join public.contratos ct on ct.id = b.contrato_id
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and (exists (select 1 from crm.cuotas_cuenta_pagada q where q.contrato_id = b.contrato_id)
         or exists (select 1 from crm.contrato_cuenta_pago_cambios c where c.contrato_id = b.contrato_id)
         or exists (select 1 from private.contrato_pdf_jobs j where j.contrato_id = b.contrato_id)
         or exists (select 1 from private.contrato_pdfs p where p.contrato_id = b.contrato_id))
  order by ct.numero_contrato
  limit 1;
  if v_usado is not null then
    raise exception 'REVERSA: el contrato % ya registró un pago, un cambio de cuenta o un PDF con su vínculo; no se borra nada. Para volver solo al mensaje anterior usa reversa-solo-codigo.sql', v_usado;
  end if;

  -- Se esperan tantos borrados como vínculos de la carga cuyo contrato sigue existiendo (un
  -- contrato eliminado ya se llevó su vínculo en cascada).
  select pg_catalog.count(*) into v_esperados
  from private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and exists (select 1 from public.contratos ct where ct.id = b.contrato_id);

  delete from crm.contrato_cuentas_pago l
  using private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and l.id = b.fila_id and l.contrato_id = b.contrato_id;
  get diagnostics v_borrados = row_count;
  if v_borrados <> v_esperados then
    raise exception 'REVERSA: se esperaban % vínculos de la carga y se encontraron %; no se borra nada',
      v_esperados, v_borrados;
  end if;

  update private.backfill_cuentas_p0xx
     set revertida_en = pg_catalog.now()
   where tipo = 'vinculo' and marca_actor = c_marca and revertida_en is null;

  raise notice 'REVERSA: % vínculos de la carga borrados', v_borrados;
end;
$datos$;

-- El bloqueo de antes, byte a byte: texto fuente de 20260925194026 (el postflight lo comprueba por md5).
create or replace function private.exigir_cuenta_pago_cronograma()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.estado is distinct from 'pagado' then
    return new;
  end if;

  -- La cuenta vinculada puede haber sido versionada y estar inactiva: sigue
  -- siendo la instruccion contractual. Bloqueamos la fila del vinculo y del
  -- contrato hasta el COMMIT para no validar una fotografia que se borra o
  -- cambia de cliente/moneda durante el registro del pago.
  perform 1
  from crm.contrato_cuentas_pago cp
  join public.contratos ct on ct.id = cp.contrato_id
  join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  where cp.contrato_id = new.contrato_id
    and cb.cliente_id = ct.cliente_id
    and cb.moneda = ct.moneda
  for share of cp, ct;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Sin cuenta de pago — requiere conciliación';
  end if;
  return new;
end;
$function$;
comment on function private.exigir_cuenta_pago_cronograma() is null;

-- Las tres funciones nuevas (la puerta primero). El portal tolera que la puerta no exista: vuelve
-- al texto genérico.
drop function if exists crm.cuentas_pago_motivos_fn(uuid[]);
drop function if exists private.cuentas_pago_motivos_autorizado(uuid[]);
drop function if exists private.cuenta_pago_diagnostico(uuid[]);

do $postflight$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure)
     is distinct from '5efb8619e4342763ae77df2ee0bb1f61' then
    raise exception 'REVERSA POSTFLIGHT: el bloqueo no volvió al cuerpo anterior';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                   and p.prosecdef and p.proconfig @> array['search_path=""'])
     or exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                  and a.grantee <> p.proowner)
     or (select p.proacl is null from pg_catalog.pg_proc p
         where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure) then
    raise exception 'REVERSA POSTFLIGHT: DEFINER, search_path o EXECUTE del bloqueo no quedaron como antes';
  end if;
  if pg_catalog.to_regprocedure('crm.cuentas_pago_motivos_fn(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuentas_pago_motivos_autorizado(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null then
    raise exception 'REVERSA POSTFLIGHT: quedó alguna función de la migración';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REVERSA POSTFLIGHT: los triggers del bloqueo de pagos no quedaron como estaban';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

### supabase/scripts/cuentas-pago-rezago/vincular-rezago.sql (NUEVA; solo cabecera y precondición: el resto es el bloque «4. Carga» de la migración, con la marca `carga:rezago-vinculos:AAAAMMDD`)
```sql
-- VINCULAR EL REZAGO, otra vez. GENERADO por generar-derivados.py: es la carga de
-- 20261001233019_crm_cuentas_pago_motivo_y_rezago.sql, sola y sin tocar ninguna función.
--
-- Cuándo: cuando Operaciones registre la cuenta que le faltaba a un contrato del rezago (o retire
-- la que sobraba) y ese contrato pase a tener UNA sola cuenta activa en su moneda. Vincula
-- exactamente esos contratos; a los demás no los toca. Lanzarlo sin nada que vincular no cambia nada.
-- Se niega si el bloqueo o el diagnóstico vivos no son los de la migración: la regla que aplica
-- tiene que ser la que se ensayó.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/vincular-rezago.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if (select pg_catalog.count(*)
      from (values
        ('private.exigir_cuenta_pago_cronograma()', 'd7618dcf85653943e62745513b3c4938'),
        ('private.cuenta_pago_diagnostico(uuid[])', 'a1dfb0c46b9365df308801bab9d5481a'),
        ('private.cuentas_pago_motivos_autorizado(uuid[])', '4c45dbbfd85f5de82372b343b0b1dfc0'),
        ('crm.cuentas_pago_motivos_fn(uuid[])', '45898bb671a3bf536375a0fb5fb33ec6')
      ) as f(firma, huella)
      join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
      where pg_catalog.md5(p.prosrc) = f.huella) <> 4 then
    raise exception 'VINCULAR: el bloqueo o el diagnóstico vivos no son los de la migración 20261001233019; no se toca nada';
  end if;
  if pg_catalog.to_regclass('private.backfill_cuentas_p0xx') is null
     or pg_catalog.to_regclass('private.conciliacion_cuentas_p0xx') is null then
    raise exception 'VINCULAR: faltan las tablas de rastro o de conciliación';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass
        and t.tgname in ('trg_contrato_cuenta_pago_coherente', 'trg_audit_contrato_cuentas_pago')
        and t.tgenabled = 'O') <> 2 then
    raise exception 'VINCULAR: faltan los triggers de coherencia o de bitácora del vínculo';
  end if;
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'VINCULAR: quien lo lanza debe poder leer contratos, vínculos y cuentas sin RLS';
  end if;
end;
$precondicion$;
```

### supabase/scripts/cuentas-pago-rezago/ensayo-prod-sin-escribir.sql (NUEVA; se omite la migración pegada en medio, idéntica a la de arriba)
```sql
-- ENSAYO EN PRODUCCIÓN, SIN ESCRIBIR, de 20261001233019_crm_cuentas_pago_motivo_y_rezago.sql.
-- GENERADO por generar-derivados.py con el archivo real de la migración (md5 b3c4035569a4f8f1e8c59e0b7467a908).
--
-- Corre la migración entera dentro de una transacción que TERMINA SIEMPRE en un error a propósito
-- («ENSAYO_DESHECHO»): no queda nada escrito, tampoco si algo falla antes. El resultado se lee en
-- el texto de ese error:
--   antes_sin_funciones / carga / despues : conteo por caso (el «antes» se cuenta dos veces: con
--                                           la regla nueva y con una consulta aparte)
--   pagos      : una cuota REAL marcada como pagada, por conexión directa, en un contrato de cada
--                caso bloqueado, en cada contrato que la carga vinculó y en uno que ya estaba bien
--   identidad  : sobre un contrato bloqueado, qué texto recibe un gestor de cartera (el detalle)
--                y qué texto recibe un analista (el genérico)
--   todo_como_se_esperaba : true si todo lo anterior salió como dicta la regla
-- Si la propia migración se niega (preflight, un candidato en conciliación, el tope, un candado
-- ocupado), el error que verás es el SUYO y no ENSAYO_DESHECHO; tampoco queda nada escrito.
-- Después, para convertir el argumento en un hecho: censo-sin-funciones.sql debe dar lo mismo que antes.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/ensayo-prod-sin-escribir.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $ensayo_antes$
declare
  v jsonb;
begin
  select coalesce(jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v
  from (select c.caso, count(*) as n from (
  select case
           when cp.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
           when cp.id is not null then 'cuenta_no_corresponde'
           when q.en_moneda = 1 then 'una_cuenta'
           when q.en_moneda > 1 then 'varias_cuentas'
           when q.otra_moneda > 0 then 'otra_moneda'
           else 'sin_cuenta'
         end as caso
  from public.contratos ct
  left join crm.contrato_cuentas_pago cp on cp.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  cross join lateral (
    select count(*) filter (where a.moneda = ct.moneda) as en_moneda,
           count(*) filter (where a.moneda <> ct.moneda) as otra_moneda
    from crm.cuentas_bancarias a
    where a.cliente_id = ct.cliente_id and a.activa
  ) q
  ) c group by c.caso) s;
  perform set_config('crm.ensayo_rezago_antes', v::text, true);
end;
$ensayo_antes$;

-- [aquí va la migración entera, sin su begin/commit]
-- ───────────── fin de la migración ─────────────

do $ensayo_fin$
declare
  c_generico constant text := 'Sin cuenta de pago — requiere conciliación';
  v_antes jsonb := current_setting('crm.ensayo_rezago_antes', true)::jsonb;
  v_carga jsonb := current_setting('crm.rezago_vinculos_resultado', true)::jsonb;
  v_despues jsonb;
  v_pagos jsonb := '[]'::jsonb;
  v_identidad jsonb := '[]'::jsonb;
  v_todo boolean := true;
  r record;
  v_bloqueado record;
  v_quien record;
  v_cuota uuid;
  v_resultado text;
  v_codigo text;
  v_mensaje text;
  v_bien boolean;
begin
  select coalesce(jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_despues
  from (select d.caso, count(*) as n from private.cuenta_pago_diagnostico() d group by d.caso) s;

  -- 1) Pagos por conexión directa (sin usuario de la API: se espera el detalle).
  for r in
    (select distinct on (d.caso) d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'bloqueado'::text as que
     from private.cuenta_pago_diagnostico() d
     where d.caso <> 'ok'
       and exists (select 1 from public.cronograma_pagos cp
                   where cp.contrato_id = d.contrato_id and cp.estado = 'pendiente')
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
                   where cp.contrato_id = d.contrato_id and cp.estado = 'pendiente')
     order by d.es_demo desc, d.numero_contrato
     limit 1)
  loop
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = r.contrato_id and cp.estado = 'pendiente'
    order by cp.fecha_programada, cp.numero_cuota
    limit 1;
    v_codigo := null;
    v_mensaje := null;
    if v_cuota is null then
      v_resultado := 'sin cuota pendiente que probar';
      v_bien := null;
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
        v_todo := false;
      end if;
    end if;
    v_pagos := v_pagos || jsonb_build_object(
      'contrato', r.numero_contrato, 'caso', r.caso, 'que', r.que,
      'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
  end loop;

  if v_antes is distinct from (v_carga -> 'antes') then
    v_todo := false;
  end if;

  -- 2) A quién se le dice el detalle. Va AL FINAL: la identidad simulada queda puesta hasta el
  --    error que deshace todo. No cambia de rol: solo los datos de sesión que lee el bloqueo.
  select d.contrato_id, d.numero_contrato, d.caso, d.mensaje into v_bloqueado
  from private.cuenta_pago_diagnostico() d
  where d.caso <> 'ok'
    and exists (select 1 from public.cronograma_pagos cp
                where cp.contrato_id = d.contrato_id and cp.estado = 'pendiente')
  order by d.es_demo, d.numero_contrato
  limit 1;
  if found then
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = v_bloqueado.contrato_id and cp.estado = 'pendiente'
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
        v_todo := false;
      end if;
      v_identidad := v_identidad || jsonb_build_object(
        'quien', v_quien.papel, 'contrato', v_bloqueado.numero_contrato, 'caso', v_bloqueado.caso,
        'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
    end loop;
  end if;

  raise exception 'ENSAYO_DESHECHO >> %', jsonb_build_object(
    'antes_sin_funciones', v_antes, 'carga', v_carga, 'despues', v_despues,
    'pagos', v_pagos, 'identidad', v_identidad, 'todo_como_se_esperaba', v_todo);
end;
$ensayo_fin$;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260803221622_crm_cuentas_bancarias_por_contrato.sql líneas 171-257 (el vínculo, su candado original y el trigger de coherencia)
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

### ANTECEDENTE vigente en producción · supabase/migrations/20260925153226_p0xx_cuentas_cliente_backfill_lectura.sql líneas 175-213 (tablas de rastro y de conciliación del backfill S1)
```sql
  175  create table if not exists private.backfill_cuentas_p0xx (
  176    tipo text not null check (tipo in ('cuenta', 'vinculo')),
  177    fila_id uuid not null,
  178    cliente_id uuid not null,
  179    contrato_id uuid,
  180    marca_actor text not null default 'migracion:p0xx:s1',
  181    insertada_en timestamptz not null default pg_catalog.now(),
  182    revertida_en timestamptz,
  183    primary key (tipo, fila_id),
  184    check ((tipo = 'cuenta' and contrato_id is null)
  185        or (tipo = 'vinculo' and contrato_id is not null))
  186  );
  187  alter table private.backfill_cuentas_p0xx enable row level security;
  188  revoke all on private.backfill_cuentas_p0xx from public, anon, authenticated;
  189  -- Denegacion explicita: evita exposicion accidental y no deja RLS sin policy.
  190  do $policy$
  191  begin
  192    if not exists (
  193      select 1 from pg_catalog.pg_policies
  194      where schemaname = 'private' and tablename = 'backfill_cuentas_p0xx'
  195        and policyname = 'p0xx_solo_interno'
  196    ) then
  197      create policy p0xx_solo_interno on private.backfill_cuentas_p0xx
  198        as restrictive for all to public using (false) with check (false);
  199    end if;
  200  end;
  201  $policy$;
  202  
  203  create table if not exists private.conciliacion_cuentas_p0xx (
  204    id bigint generated always as identity primary key,
  205    clase text not null check (clase in ('perfil', 'contrato')),
  206    cliente_id uuid not null,
  207    moneda text not null check (moneda in ('PEN', 'USD')),
  208    contrato_id uuid,
  209    motivo text not null check (motivo in (
  210      'perfil_invalido', 'mismo_cci_datos_distintos', 'varias_activas',
  211      'sin_cuenta', 'cuentas_ambiguas', 'perfil_conflictivo')),
  212    observado_en timestamptz not null default pg_catalog.now()
  213  );
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260925153226_p0xx_cuentas_cliente_backfill_lectura.sql líneas 359-408 (el bucle de vínculos del backfill S1 (el patrón que se sigue))
```sql
  359    for v_contrato_id in
  360      select ct.id from public.contratos ct
  361      where not exists (
  362        select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = ct.id)
  363      order by ct.id
  364    loop
  365      select ct.* into v_contrato from public.contratos ct
  366      where ct.id = v_contrato_id for share;
  367      if not found or exists (
  368        select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = v_contrato_id
  369      ) then continue; end if;
  370  
  371      -- Una sola fila CRM no es inequivoca si el perfil trae una instruccion
  372      -- invalida o datos distintos para el mismo CCI. El caso va a operaciones.
  373      if exists (
  374        select 1 from private.conciliacion_cuentas_p0xx x
  375        where x.clase = 'perfil' and x.cliente_id = v_contrato.cliente_id
  376          and x.moneda = v_contrato.moneda
  377          and x.motivo in ('perfil_invalido', 'mismo_cci_datos_distintos')
  378      ) then
  379        insert into private.conciliacion_cuentas_p0xx
  380          (clase, cliente_id, moneda, contrato_id, motivo)
  381        values ('contrato', v_contrato.cliente_id, v_contrato.moneda,
  382                v_contrato.id, 'perfil_conflictivo');
  383        continue;
  384      end if;
  385  
  386      select pg_catalog.count(*), (pg_catalog.array_agg(cb.id))[1]
  387        into v_candidatas, v_cuenta_id
  388      from crm.cuentas_bancarias cb
  389      where cb.cliente_id = v_contrato.cliente_id
  390        and cb.moneda = v_contrato.moneda and cb.activa is true;
  391      if v_candidatas = 1 then
  392        -- El trigger de coherencia aborta toda la migracion si la pareja no vale.
  393        insert into crm.contrato_cuentas_pago
  394          (contrato_id, cuenta_bancaria_id, creado_por)
  395        values (v_contrato.id, v_cuenta_id, null)
  396        returning id into v_vinculo_id;
  397        insert into private.backfill_cuentas_p0xx
  398          (tipo, fila_id, cliente_id, contrato_id)
  399        values ('vinculo', v_vinculo_id, v_contrato.cliente_id, v_contrato.id);
  400      else
  401        insert into private.conciliacion_cuentas_p0xx
  402          (clase, cliente_id, moneda, contrato_id, motivo)
  403        values ('contrato', v_contrato.cliente_id, v_contrato.moneda,
  404                v_contrato.id,
  405                case when v_candidatas = 0 then 'sin_cuenta' else 'cuentas_ambiguas' end);
  406      end if;
  407    end loop;
  408  end;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260821222348_portal_asiento_operaciones.sql líneas 77-84 (public.es_gestor_cartera)
```sql
   77  create or replace function public.es_gestor_cartera()
   78  returns boolean
   79  language sql
   80  stable security definer
   81  set search_path to 'public', 'pg_temp'
   82  as $function$
   83    SELECT public.es_admin() OR public.es_operaciones();
   84  $function$;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260821222348_portal_asiento_operaciones.sql líneas 134-150 (policies de public.cronograma_pagos)
```sql
  134  -- 4.3 cronograma_pagos — la pantalla de Pagos escribe DIRECTO sobre la tabla
  135  --     (registrar un pago y revertirlo son UPDATE), asi que aqui si hace falta.
  136  --     El DELETE sigue siendo de `es_admin()`.
  137  alter policy cronograma_select on public.cronograma_pagos
  138  using (
  139    (exists (
  140      select 1
  141      from public.contratos c
  142      where c.id = cronograma_pagos.contrato_id
  143        and c.cliente_id = (select auth.uid())
  144    ))
  145    or public.es_gestor_cartera()
  146  );
  147  
  148  alter policy cronograma_admin_actualiza on public.cronograma_pagos
  149  using (public.es_gestor_cartera())
  150  with check (public.es_gestor_cartera());
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260821222348_portal_asiento_operaciones.sql líneas 657-710 (la puerta hermana crm.cuentas_pago_contratos_fn)
```sql
  657  create or replace function crm.cuentas_pago_contratos_fn(p_contrato_ids uuid[])
  658   RETURNS TABLE(contrato_id uuid, cuenta_bancaria_id uuid, moneda text, banco text, tipo_cuenta text, numero_cuenta text, cci text, titular_distinto boolean, beneficiario_nombre text, beneficiario_dni text)
  659   LANGUAGE plpgsql
  660   STABLE SECURITY DEFINER
  661   SET search_path TO ''
  662  AS $function$
  663  begin
  664    -- P04 (2026-08-09): bloquea la revocación explícita, no la ausencia de
  665    -- membresía. El poder de gestión de cartera del portal (admin, superadmin
  666    -- u operaciones) sigue siendo condición necesaria.
  667    if (select private.membresia_crm_revocada())
  668       or not (select public.es_gestor_cartera()) then
  669      raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  670    end if;
  671    if coalesce(cardinality(p_contrato_ids), 0) > 5000 then
  672      raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  673    end if;
  674    if coalesce(cardinality(p_contrato_ids), 0) = 0 then
  675      return;
  676    end if;
  677  
  678    if exists (
  679      select 1
  680      from crm.contrato_cuentas_pago ccp
  681      join public.contratos ct on ct.id = ccp.contrato_id
  682      join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  683      where ccp.contrato_id = any(p_contrato_ids)
  684        and (
  685          cb.cliente_id is distinct from ct.cliente_id
  686          or cb.moneda is distinct from ct.moneda
  687        )
  688    ) then
  689      raise exception using
  690        errcode = 'P0001',
  691        message = 'Hay un contrato con cuenta de pago inconsistente; requiere conciliacion antes de pagar';
  692    end if;
  693  
  694    return query
  695    select
  696      ccp.contrato_id,
  697      cb.id as cuenta_bancaria_id,
  698      cb.moneda,
  699      cb.banco,
  700      cb.tipo_cuenta,
  701      cb.numero_cuenta,
  702      cb.cci,
  703      cb.titular_distinto,
  704      cb.beneficiario_nombre,
  705      cb.beneficiario_dni
  706    from crm.contrato_cuentas_pago ccp
  707    join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  708    where ccp.contrato_id = any(p_contrato_ids);
  709  end;
  710  $function$
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260809000530_crm_p04_revocado_vs_ajeno_al_crm.sql líneas 148-167 (private.membresia_crm_revocada)
```sql
  148  create or replace function private.membresia_crm_revocada()
  149  returns boolean
  150  language sql
  151  stable
  152  security definer
  153  set search_path = ''
  154  as $function$
  155    select exists (
  156      select 1
  157      from crm.equipo e
  158      where e.perfil_id = (select auth.uid())
  159        and e.activo is false
  160    );
  161  $function$;
  162  
  163  comment on function private.membresia_crm_revocada() is
  164    'Offboarding CRM explícito: true solo si la persona TIENE fila en crm.equipo y está apagada. Ausencia de fila = ajena al CRM (su rol de portal gobierna), nunca revocación. ⚠️ El offboarding es activo=false, NUNCA DELETE: borrar la fila devuelve el poder de portal. Helper interno que solo resta poder; jamás concede.';
  165  
  166  revoke all on function private.membresia_crm_revocada()
  167    from public, anon, authenticated, service_role;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260926204051_crm_cambio_cuenta_pago.sql líneas 44-53 (F3: orden de candados documentado)
```sql
   44  -- Bloqueos: el núcleo toma los contratos (FOR SHARE, por id) y DESPUÉS los enlaces (FOR UPDATE),
   45  -- el mismo orden que el registro de un pago: su trigger 00 (private.proteger_cronograma_documental
   46  -- → private.bloquear_fila_contrato_pdf) bloquea el contrato FOR UPDATE y su trigger 10
   47  -- (private.exigir_cuenta_pago_cronograma) lee el enlace FOR SHARE. Así un pago y un cambio del mismo
   48  -- contrato se ponen en fila en el contrato: sin abrazo mortal, y el pago que esperaba lee el enlace
   49  -- ya cambiado. El aviso (reclamar) toma su fila de aviso y después los enlaces FOR SHARE: un
   50  -- cambio espera a que termine la reserva de un aviso, y el núcleo rechaza cambiar un contrato con
   51  -- un aviso en curso. Riesgo residual: un registro de pagos en lote que bloquee varios contratos en
   52  -- otro orden podría cruzarse con un cambio de esos mismos contratos; Postgres detecta el abrazo y
   53  -- aborta uno de los dos (falla cerrado, sin dato erróneo; basta con reintentarlo).
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260926204051_crm_cambio_cuenta_pago.sql líneas 328-367 (F3: candado vigente del vínculo)
```sql
  328  create or replace function private.trg_contrato_cuenta_pago_inmutable()
  329  returns trigger
  330  language plpgsql
  331  security definer
  332  set search_path = ''
  333  as $$
  334  begin
  335    if row(new.id, new.contrato_id, new.creado_en)
  336       is distinct from
  337       row(old.id, old.contrato_id, old.creado_en) then
  338      raise exception using
  339        errcode = '22023',
  340        message = 'La cuenta de pago del contrato es historica y no se reemplaza';
  341    end if;
  342    -- La cuenta solo cambia si el mismo cambio quedó escrito en el historial dentro de ESTA
  343    -- transacción (cambiado_en = now() de la transacción). Solo el núcleo del cambio escribe ese
  344    -- historial.
  345    if new.cuenta_bancaria_id is distinct from old.cuenta_bancaria_id
  346       and not exists (
  347         select 1 from crm.contrato_cuenta_pago_cambios c
  348         where c.contrato_id = new.contrato_id
  349           and c.cuenta_anterior_id = old.cuenta_bancaria_id
  350           and c.cuenta_nueva_id = new.cuenta_bancaria_id
  351           and c.cambiado_en = pg_catalog.now()
  352       ) then
  353      raise exception using
  354        errcode = '22023',
  355        message = 'La cuenta de pago del contrato solo cambia con un cambio registrado';
  356    end if;
  357    if new.creado_por is distinct from old.creado_por
  358       and not (
  359         new.creado_por is null
  360         and old.creado_por is not null
  361         and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
  362       ) then
  363      raise exception using errcode = '22023', message = 'La autoria del enlace bancario es inmutable';
  364    end if;
  365    return new;
  366  end;
  367  $$;
```

### ANTECEDENTE vigente en producción · supabase/migrations/20260927020317_crm_cuentas_gloria_motivo_y_cuenta_retirada.sql líneas 155-248 (F3: núcleo del cambio de cuenta (candados y rechazo de contratos sin cuenta))
```sql
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

### ANTECEDENTE vigente en producción · supabase/migrations/20260818200741_crm_contratos_correccion_pdf_eliminacion.sql líneas 602-664 (trigger 00 del cronograma (corre antes que el bloqueo))
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

### DIFF · supabase/scripts/test-rls.mjs y supabase/scripts/p0xx/verify-s3-pagos-sintetico.sql (el diff de la matriz trae también las sondas de una SEGUNDA migración, `asignar_cuenta_pago_contrato`, que se revisa en otro encargo: ignóralas aquí)
```diff
diff --git a/CRM-Avance-Corp/supabase/scripts/p0xx/verify-s3-pagos-sintetico.sql b/CRM-Avance-Corp/supabase/scripts/p0xx/verify-s3-pagos-sintetico.sql
index ac946e61..b35e09db 100644
--- a/CRM-Avance-Corp/supabase/scripts/p0xx/verify-s3-pagos-sintetico.sql
+++ b/CRM-Avance-Corp/supabase/scripts/p0xx/verify-s3-pagos-sintetico.sql
@@ -41,7 +41,9 @@ begin
              fecha_pago_real = (now() at time zone 'America/Lima')::date
        where id = v_cuota_sin;
     exception when check_violation then
-      if sqlerrm <> 'Sin cuenta de pago — requiere conciliación' then raise; end if;
+      -- Desde 20261001233019 el rechazo dice el motivo («Contrato N sin cuenta de pago: …») a una
+      -- conexión directa como esta; antes era siempre el texto genérico. Valen los dos.
+      if sqlerrm not like '%in cuenta de pago%' then raise; end if;
       v_bloqueado := true;
     end;
     if not v_bloqueado then
@@ -57,7 +59,7 @@ begin
               (now() at time zone 'America/Lima')::date, 100,
               'pagado', 100, (now() at time zone 'America/Lima')::date);
     exception when check_violation then
-      if sqlerrm <> 'Sin cuenta de pago — requiere conciliación' then raise; end if;
+      if sqlerrm not like '%in cuenta de pago%' then raise; end if;
       v_bloqueado := true;
     end;
     if not v_bloqueado then
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index a4a1e202..08a7b7fb 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -4778,8 +4778,31 @@ async function testContractBankAccounts(sessions, seed) {
       ['42501'],
       /no autorizado para consultar cuentas de pago/i,
     );
+    await expectExpectedFailure(
+      `${label}: no lee el motivo del bloqueo de pagos`,
+      sessions.vend1.client.schema('crm').rpc('cuentas_pago_motivos_fn', {
+        p_contrato_ids: [seed.legacyContract.id],
+      }),
+      ['42501'],
+      /no autorizado para consultar cuentas de pago/i,
+    );
+    await expectExpectedFailure(
+      `${label}: no asigna la cuenta de pago de un contrato`,
+      sessions.vend1.client.schema('crm').rpc('asignar_cuenta_pago_contrato', {
+        p_solicitud_id: SOLICITUD_ASIGNAR_GATE,
+        p_contrato_id: seed.legacyContract.id,
+        p_cuenta_id: seed.bankAccount.id,
+        p_motivo: 'Motivo de prueba del gate',
+      }),
+      ['42501'],
+      /solo administración puede asignar la cuenta de pago/i,
+    );
   }
 
+  // 20261002005004: una solicitud fija para las sondas de la asignación. Ninguna llega a escribir:
+  // o no pasan la compuerta (42501) o se quedan en la validación del motivo (22023).
+  const SOLICITUD_ASIGNAR_GATE = '00000000-0000-4000-8000-0000000a51a0';
+
   async function assertAdminBankRead(client, label) {
     const listed = await positive(
       `${label}: lista cuentas bancarias`,
@@ -4808,6 +4831,63 @@ async function testContractBankAccounts(sessions, seed) {
         ),
       `${label}: Pagos recibe la fotografia contractual esperada`,
     );
+
+    // 20261001233019: el motivo del bloqueo solo viene para los contratos que
+    // NO se pueden pagar, redactado para la persona y sin datos bancarios.
+    const CASOS_SIN_PAGO = ['una_cuenta', 'varias_cuentas', 'otra_moneda', 'sin_cuenta', 'cuenta_no_corresponde'];
+    const motivos = await positive(
+      `${label}: lee el motivo del bloqueo de pagos`,
+      client.schema('crm').rpc('cuentas_pago_motivos_fn', {
+        p_contrato_ids: [seed.contract.id, seed.legacyContract.id],
+      }),
+    );
+    const filasMotivo = Array.isArray(motivos?.data) ? motivos.data : [];
+    check(
+      !filasMotivo.some((row) => row.contrato_id === seed.contract.id),
+      `${label}: un contrato con cuenta de pago no trae motivo`,
+    );
+    const motivoLegacy = filasMotivo.filter((row) => row.contrato_id === seed.legacyContract.id);
+    check(
+      motivoLegacy.length === 1
+        && CASOS_SIN_PAGO.includes(motivoLegacy[0].caso)
+        && typeof motivoLegacy[0].mensaje === 'string'
+        && motivoLegacy[0].mensaje.includes('cuenta de pago'),
+      `${label}: el contrato legacy sin enlace trae su caso y su motivo`,
+    );
+    check(
+      motivoLegacy.every((row) => !row.mensaje.includes(BANK_CLIENT.cci)),
+      `${label}: el motivo no expone el CCI del cliente`,
+    );
+    const sinIds = await positive(
+      `${label}: sin contratos pedidos no hay motivos`,
+      client.schema('crm').rpc('cuentas_pago_motivos_fn', { p_contrato_ids: [] }),
+    );
+    check(
+      Array.isArray(sinIds?.data) && sinIds.data.length === 0,
+      `${label}: la puerta de motivos nunca clasifica todos los contratos`,
+    );
+    await expectExpectedFailure(
+      `${label}: la puerta de motivos rechaza más de 5000 contratos`,
+      client.schema('crm').rpc('cuentas_pago_motivos_fn', {
+        p_contrato_ids: Array.from({ length: 5001 }, () => seed.contract.id),
+      }),
+      ['22023'],
+      /demasiados contratos en una sola consulta/i,
+    );
+    // 20261002005004: administración PASA la compuerta de la asignación (llega a la validación
+    // del motivo) sin escribir nada: el contrato legacy tiene que seguir sin enlace para el
+    // resto del gate.
+    await expectExpectedFailure(
+      `${label}: la asignación de cuenta de pago llega al núcleo y exige el motivo`,
+      client.schema('crm').rpc('asignar_cuenta_pago_contrato', {
+        p_solicitud_id: SOLICITUD_ASIGNAR_GATE,
+        p_contrato_id: seed.legacyContract.id,
+        p_cuenta_id: seed.bankAccount.id,
+        p_motivo: '   ',
+      }),
+      ['22023'],
+      /escribe el motivo de la asignación/i,
+    );
   }
 
   // El fixture principal usa el rol portal neutro `comercial` para probar que el
@@ -5033,6 +5113,25 @@ async function testContractBankAccounts(sessions, seed) {
       ['42501'],
       /no autorizado para consultar cuentas de pago/i,
     );
+    await expectExpectedFailure(
+      'admin con membresia CRM revocada: la revocacion prevalece sobre el motivo del bloqueo',
+      sessions.directorio.client.schema('crm').rpc('cuentas_pago_motivos_fn', {
+        p_contrato_ids: [seed.legacyContract.id],
+      }),
+      ['42501'],
+      /no autorizado para consultar cuentas de pago/i,
+    );
+    await expectExpectedFailure(
+      'admin con membresia CRM revocada: no asigna la cuenta de pago de un contrato',
+      sessions.directorio.client.schema('crm').rpc('asignar_cuenta_pago_contrato', {
+        p_solicitud_id: SOLICITUD_ASIGNAR_GATE,
+        p_contrato_id: seed.legacyContract.id,
+        p_cuenta_id: seed.bankAccount.id,
+        p_motivo: 'Motivo de prueba del gate',
+      }),
+      ['42501'],
+      /solo administración puede asignar la cuenta de pago/i,
+    );
     // P04 sobre la CORRECCION de contratos por la via admin del Portal
     // (20260809003923). El alta ya estaba gateada para todo actor desde el
     // catalogo; corregir no lo estaba: la rama admin de public.actualizar_contrato
@@ -5170,6 +5269,25 @@ async function testContractBankAccounts(sessions, seed) {
       ['42501'],
       /no autorizado para consultar cuentas de pago/i,
     );
+    await expectExpectedFailure(
+      'admin sin membresia con perfil APAGADO: no lee el motivo del bloqueo de pagos',
+      sessions.directorio.client.schema('crm').rpc('cuentas_pago_motivos_fn', {
+        p_contrato_ids: [seed.legacyContract.id],
+      }),
+      ['42501'],
+      /no autorizado para consultar cuentas de pago/i,
+    );
+    await expectExpectedFailure(
+      'admin sin membresia con perfil APAGADO: no asigna la cuenta de pago de un contrato',
+      sessions.directorio.client.schema('crm').rpc('asignar_cuenta_pago_contrato', {
+        p_solicitud_id: SOLICITUD_ASIGNAR_GATE,
+        p_contrato_id: seed.legacyContract.id,
+        p_cuenta_id: seed.bankAccount.id,
+        p_motivo: 'Motivo de prueba del gate',
+      }),
+      ['42501'],
+      /solo administración puede asignar la cuenta de pago/i,
+    );
     await requireAdmin(
       'banca P04: reactivar el perfil portal de directorio',
       admin.from('perfiles').update({ activo: true }).eq('id', directorProfileId),
@@ -5743,6 +5861,31 @@ async function testContractBankAccounts(sessions, seed) {
           p_contrato_ids: [seed.contract.id],
         }),
       );
+      await expectExplicitAuthorizationDenied(
+        `${key} no lee el motivo del bloqueo de pagos reservado al gestor de cartera`,
+        sessions[key].client.schema('crm').rpc('cuentas_pago_motivos_fn', {
+          p_contrato_ids: [seed.legacyContract.id],
+        }),
+      );
+    }
+    // El propio cliente del contrato tampoco: el motivo cuenta cuántas cuentas tiene y en qué moneda.
+    await expectExplicitAuthorizationDenied(
+      'clientBank no lee el motivo del bloqueo de pagos de su propio contrato',
+      sessions.clientBank.client.schema('crm').rpc('cuentas_pago_motivos_fn', {
+        p_contrato_ids: [seed.legacyContract.id],
+      }),
+    );
+    // Ni el analista, ni un rol global, ni el propio cliente deciden a qué cuenta se le paga.
+    for (const key of ['vend1', 'directorio', 'clientBank']) {
+      await expectExplicitAuthorizationDenied(
+        `${key} no asigna la cuenta de pago de un contrato`,
+        sessions[key].client.schema('crm').rpc('asignar_cuenta_pago_contrato', {
+          p_solicitud_id: SOLICITUD_ASIGNAR_GATE,
+          p_contrato_id: seed.legacyContract.id,
+          p_cuenta_id: seed.bankAccount.id,
+          p_motivo: 'Motivo de prueba del gate',
+        }),
+      );
     }
   } finally {
     // Devolver la bandera de identidad al valor que tenia al entrar (otra sesion
@@ -14614,6 +14757,23 @@ async function testAnon(seed) {
     }),
     ['PGRST202'],
   );
+  await expectExplicitAuthorizationDenied(
+    'anon no lee el motivo del bloqueo de pagos',
+    anon.schema('crm').rpc('cuentas_pago_motivos_fn', {
+      p_contrato_ids: [seed.legacyContract.id],
+    }),
+    ['PGRST202'],
+  );
+  await expectExplicitAuthorizationDenied(
+    'anon no asigna la cuenta de pago de un contrato',
+    anon.schema('crm').rpc('asignar_cuenta_pago_contrato', {
+      p_solicitud_id: '00000000-0000-4000-8000-0000000a51a0',
+      p_contrato_id: seed.legacyContract.id,
+      p_cuenta_id: seed.bankAccount.id,
+      p_motivo: 'Motivo de prueba del gate',
+    }),
+    ['PGRST202'],
+  );
   // C1: las RPC de reparto solo tienen grant para `authenticated`.
   await expectBlockedMutation(
     'anon no puede ver la cola por repartir',
```
