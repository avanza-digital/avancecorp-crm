ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: Cuentas de Gloria · F2 — historial de cuentas retiradas (LEVEL 3: datos bancarios)

Tu trabajo es REFUTAR: busca fallos reales (fugas entre carteras o a clientes/anon, datos
sensibles a quien hoy no los ve, oráculos, search_path, grants, regresiones del portal,
fechas/zonas, estados incoherentes). Sin hallazgo sin evidencia.

## Contexto

Supabase/Postgres. `crm.cuentas_bancarias` guarda versiones de cuentas del cliente; `activa=false`
+ `desactivada_por`/`desactivada_en` (CHECK: activa=false ⇒ desactivada_en NOT NULL; activa=true ⇒
ambos NULL). authenticated NO tiene grants sobre la tabla. Lectura vigente ya en producción:
`crm.cuentas_bancarias_cliente_fn(p_cliente_id, p_moneda)` (SECURITY DEFINER) que autoriza con
`private.puede_gestionar_cuentas_cliente(uuid)`:
  auth.uid() no nulo, membresía CRM no revocada, y el perfil es rol 'cliente' ACTIVO y además
  (es_gestor_cartera() [admin/superadmin u 'operaciones'] OR analista de su cartera OR rol CRM
  vendedor/supervisor/gerencia con visibilidad) — devuelve boolean; para cliente inexistente → false.
Hoy (26/09) se aplicó en prod el patrón «puerta de pantalla SECURITY INVOKER en esquema expuesto
que delega en un autorizador SECURITY DEFINER en `private` (no expuesto) con EXECUTE a
authenticated» (migración 20260926145330, advisors sin avisos nuevos). authenticated tiene USAGE
sobre private en prod.

Pedido de Miguel: que Gloria (admin) vea en la ventana «Cuentas» del portal las cuentas que tuvo el
cliente: «Retirada el [fecha] por [persona]». Enmascarado por rol en pantalla igual que la F1 (admin
y superadmin completo; resto ••••1234). Tapar números en el servidor es una fase aparte (F2b),
deliberadamente fuera de alcance: el servidor ya entrega números completos a todo autorizado por la
lectura vigente.

## Migración nueva (texto íntegro)

```sql
-- Cuentas de Gloria · F2: historial de cuentas bancarias retiradas del cliente.
--
-- Qué hace: añade UNA lectura nueva, crm.historial_cuentas_cliente_fn(p_cliente_id), que
-- devuelve las versiones INACTIVAS (activa = false) de crm.cuentas_bancarias del cliente,
-- con la fecha de retiro y el nombre de quién la retiró. La ventana «Cuentas» del panel
-- admin del portal (miavance.com) la muestra como «Cuentas anteriores».
--
-- Por qué: Miguel (26/09/2026) pidió que Gloria vea todas las cuentas que tuvo el cliente,
-- sin ninguna oculta. Hoy solo se leen las vigentes (private.cuentas_cliente_vigentes).
-- Plan: tablero «Plan Cuentas Gloria» (FigJam de Pagos, nodo 18:42) y la nota del vault
-- «Cuentas bancarias - Gloria ve y añade cuentas, fase 1 publicada (2026-09-26)».
--
-- Diseño (mismo patrón que 20260926145330_p0xx_cuentas_wrappers_invoker):
--   · private.historial_cuentas_cliente_autorizado: SECURITY DEFINER. Justificación: el
--     cliente API no tiene (ni debe tener) grants sobre crm.cuentas_bancarias; la función
--     comprueba ANTES de leer la misma autorización que crm.cuentas_bancarias_cliente_fn
--     (private.puede_gestionar_cuentas_cliente: gestor de cartera, analista de su cartera
--     o rol CRM con visibilidad; nunca un cliente ni anon). search_path vacío, nombres
--     calificados. No está en un esquema expuesto.
--   · crm.historial_cuentas_cliente_fn: puerta de pantalla SECURITY INVOKER, sin elevar
--     privilegios en el esquema expuesto; solo delega.
-- No cambia ninguna función, política, tabla ni permiso existente. Solo lectura.
-- Datos sensibles: devuelve N° de cuenta, CCI y DNI del beneficiario a quien ya puede
-- leerlos hoy por crm.cuentas_bancarias_cliente_fn; el enmascarado por rol es de pantalla
-- (tapar en el servidor es la fase F2b, aparte).
--
-- Reversión: ../scripts/cuentas-gloria/reversa-historial-cuentas-cliente.sql (borra las dos
-- funciones nuevas; nada más depende de ellas).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $precondicion$
begin
  if to_regclass('crm.cuentas_bancarias') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null then
    raise exception 'HISTORIAL: faltan crm.cuentas_bancarias o private.puede_gestionar_cuentas_cliente(uuid)';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'HISTORIAL: authenticated necesita USAGE sobre private para la puerta INVOKER';
  end if;
  if to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)') is not null
     or to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)') is not null then
    raise exception 'HISTORIAL: las funciones ya existen; no se sobrescriben';
  end if;
end;
$precondicion$;

-- Núcleo: autoriza y lee.
create function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if p_cliente_id is null
     or not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
         cb.numero_cuenta, cb.cci, cb.titular_distinto,
         cb.beneficiario_nombre, cb.beneficiario_dni, cb.origen,
         cb.creado_en, cb.desactivada_en, pr.nombre_completo
  from crm.cuentas_bancarias cb
  left join public.perfiles pr on pr.id = cb.desactivada_por
  where cb.cliente_id = p_cliente_id
    and cb.activa is false
  order by cb.desactivada_en desc nulls last, cb.creado_en desc, cb.id desc;
end;
$function$;

-- Puerta de pantalla: solo delega.
create function crm.historial_cuentas_cliente_fn(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language sql
stable security invoker
set search_path to ''
as $function$
  select h.cuenta_id, h.moneda, h.banco, h.tipo_cuenta,
         h.numero_cuenta, h.cci, h.titular_distinto,
         h.beneficiario_nombre, h.beneficiario_dni, h.origen,
         h.creada_en, h.desactivada_en, h.desactivada_por_nombre
  from private.historial_cuentas_cliente_autorizado(p_cliente_id) h;
$function$;

-- Permisos: solo authenticated; la autorización fina vive en el núcleo.
revoke all on function private.historial_cuentas_cliente_autorizado(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.historial_cuentas_cliente_autorizado(uuid)
  to authenticated;
revoke all on function crm.historial_cuentas_cliente_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.historial_cuentas_cliente_fn(uuid)
  to authenticated;

comment on function private.historial_cuentas_cliente_autorizado(uuid) is
  'Cuentas bancarias RETIRADAS (activa = false) del cliente, con fecha y nombre de quien las retiró. Autoriza con private.puede_gestionar_cuentas_cliente; 42501 si no. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias. DATOS SENSIBLES: N° de cuenta, CCI y DNI del beneficiario.';
comment on function crm.historial_cuentas_cliente_fn(uuid) is
  'Puerta de pantalla (INVOKER) del historial de cuentas retiradas del cliente; delega en private.historial_cuentas_cliente_autorizado. La usa la ventana «Cuentas» del panel admin del portal. DATOS SENSIBLES: el enmascarado por rol lo hace la pantalla.';

do $postflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
  ) or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'crm.historial_cuentas_cliente_fn(uuid)'::regprocedure
      and not p.prosecdef and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'HISTORIAL: modo de seguridad o search_path inesperado';
  end if;
  if pg_catalog.has_function_privilege('anon', 'crm.historial_cuentas_cliente_fn(uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'private.historial_cuentas_cliente_autorizado(uuid)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'crm.historial_cuentas_cliente_fn(uuid)', 'EXECUTE')
     or pg_catalog.has_table_privilege('authenticated', 'crm.cuentas_bancarias', 'SELECT') then
    raise exception 'HISTORIAL: permisos inesperados tras aplicar';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Reversa
```sql
-- REVERSA de 20260926193424_crm_historial_cuentas_cliente.
-- Borra SOLO las dos funciones nuevas (lectura; ninguna otra función, vista ni política las
-- usa). No toca datos. Se niega si algo del catálogo depende de ellas.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if exists (
    select 1 from pg_catalog.pg_depend d
    where d.refobjid in (
      coalesce(to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)')::oid, 0),
      coalesce(to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)')::oid, 0))
      and d.deptype = 'n'
  ) then
    raise exception 'REVERSA: hay objetos que dependen del historial; revisar antes de borrar';
  end if;
end $chk$;
drop function if exists crm.historial_cuentas_cliente_fn(uuid);
drop function if exists private.historial_cuentas_cliente_autorizado(uuid);
notify pgrst, 'reload schema';
commit;
```

## Evidencia del ensayo (banco Docker local, sin datos reales)
- Foto del catálogo (md5 de pg_get_functiondef + proacl de todas las funciones crm/private/public, políticas, ACL de tablas y esquemas) antes vs después: SOLO aparecen las 2 funciones nuevas, ACL {postgres=X, authenticated=X}. Tras la reversa: catálogo idéntico al de antes (969 líneas).
- Prueba SQL (transacción con ROLLBACK, usuarios ficticios): admin 2 · operaciones 2 · analista de la cartera 2 · analista ajeno 42501 · el propio cliente 42501 · anon 42501 · contenido solo retiradas del cliente pedido, orden desactivada_en desc, nombre o NULL · cliente sin retiradas 0 filas · mutante sin autorización CAZADO · mutante sin filtro activa=false CAZADO.
- Gate RLS completo: NOT RUN (la semilla del banco choca con un fixture de otra sesión: DNI 90000001 duplicado).

## Portal (diff)
```diff
diff --git a/admin/clientes.html b/admin/clientes.html
index d92b277..9a67bbe 100644
--- a/admin/clientes.html
+++ b/admin/clientes.html
@@ -564,6 +564,8 @@
           <div id="cb_cuentas_pen" aria-live="polite" style="font-size: 14px;">Cargando cuentas vigentes…</div>
           <p style="font-weight: 700; font-size: 14px; margin: 8px 0 4px; color: var(--navy);">Dólares (USD)</p>
           <div id="cb_cuentas_usd" aria-live="polite" style="font-size: 14px;">Cargando cuentas vigentes…</div>
+          <p style="font-weight: 700; font-size: 14px; margin: 8px 0 4px; color: var(--navy);">Cuentas anteriores</p>
+          <div id="cb_cuentas_anteriores" aria-live="polite" style="font-size: 14px; color: var(--text-secondary);">Cargando cuentas anteriores…</div>
 
           <button type="button" class="btn btn-secondary" id="btnMostrarNuevaCuenta" style="margin-top: 8px;">+ Añadir cuenta</button>
 
@@ -665,7 +667,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/clientes.js?v=51"></script>
+  <script type="module" src="/js/admin/clientes.js?v=52"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
diff --git a/js/admin/clientes.js b/js/admin/clientes.js
index a3a6909..445ada7 100644
--- a/js/admin/clientes.js
+++ b/js/admin/clientes.js
@@ -19,8 +19,9 @@ import { initCampoDocumento } from './documento-ui.js?v=1'
 import { mensajeErrorGuardarCliente } from './clientes-errores-core.js?v=2'
 import { guardarCorreoCliente, validarCorreccionCorreo } from './correo-cliente-core.js?v=1'
 import {
-  cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente, puedeVerCuentasCompletas
-} from './cuentas-cliente-core.js?v=2'
+  cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente, puedeVerCuentasCompletas,
+  cargarHistorialCuentas, pintarCuentasAnteriores
+} from './cuentas-cliente-core.js?v=3'
 
 // CLIENTES_CACHE ahora guarda SOLO la página actual (max PAGE_SIZE filas).
 // El total real está en TOTAL_CLIENTES. Con paginación server-side el cache
@@ -611,8 +612,10 @@ function cargarCuentasModal(clienteId) {
   const token = ++CUENTAS_MODAL_TOKEN
   const pen = document.getElementById('cb_cuentas_pen')
   const usd = document.getElementById('cb_cuentas_usd')
+  const anteriores = document.getElementById('cb_cuentas_anteriores')
   pen.textContent = 'Cargando cuentas vigentes…'
   usd.textContent = 'Cargando cuentas vigentes…'
+  anteriores.textContent = 'Cargando cuentas anteriores…'
   void cargarCuentasCliente(supabase, clienteId, { completas: PUEDE_VER_CUENTAS_COMPLETAS }).then((cuentas) => {
     if (token !== CUENTAS_MODAL_TOKEN) return
     pintarCuentasCliente(pen, cuentas, 'PEN')
@@ -622,6 +625,14 @@ function cargarCuentasModal(clienteId) {
     pen.textContent = 'No se pudieron cargar las cuentas. Vuelve a abrir la ventana.'
     usd.textContent = ''
   })
+  // El historial va aparte: si falla, las cuentas vigentes se siguen viendo.
+  void cargarHistorialCuentas(supabase, clienteId, { completas: PUEDE_VER_CUENTAS_COMPLETAS }).then((cuentas) => {
+    if (token !== CUENTAS_MODAL_TOKEN) return
+    pintarCuentasAnteriores(anteriores, cuentas)
+  }).catch(() => {
+    if (token !== CUENTAS_MODAL_TOKEN) return
+    anteriores.textContent = 'No se pudo cargar el historial. Vuelve a abrir la ventana.'
+  })
 }
 
 function limpiarFormNuevaCuenta() {
diff --git a/js/admin/cuentas-cliente-core.js b/js/admin/cuentas-cliente-core.js
index a401bdc..10f3b09 100644
--- a/js/admin/cuentas-cliente-core.js
+++ b/js/admin/cuentas-cliente-core.js
@@ -55,6 +55,35 @@ export function textoCuenta(c) {
   return `${c.banco} · ${c.tipo} · N°\u00A0${c.numero} · CCI\u00A0${c.cci}${titular} · ${c.origen} · ${c.fecha}`
 }
 
+function describirRetiro(cuenta) {
+  if (!cuenta.desactivada_en) return 'Retirada · fecha no registrada'
+  const fecha = new Date(cuenta.desactivada_en).toLocaleDateString('es-PE', {
+    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit'
+  })
+  return cuenta.desactivada_por_nombre
+    ? `Retirada el ${fecha} por ${cuenta.desactivada_por_nombre}`
+    : `Retirada el ${fecha} · persona no registrada`
+}
+
+// Historial: versiones retiradas (activa = false), la más reciente primero. Mismo
+// enmascarado por rol que las vigentes.
+export async function cargarHistorialCuentas(supabase, clienteId, { completas = false } = {}) {
+  const { data, error } = await supabase.schema('crm')
+    .rpc('historial_cuentas_cliente_fn', { p_cliente_id: clienteId })
+  if (error || !Array.isArray(data)) {
+    throw new Error('No se pudo cargar el historial de cuentas.')
+  }
+  return data.map((cuenta) => ({
+    ...resumirCuenta(cuenta, completas === true),
+    retiro: describirRetiro(cuenta),
+  }))
+}
+
+export function textoCuentaAnterior(c) {
+  const moneda = c.moneda === 'USD' ? 'Dólares' : 'Soles'
+  return `${moneda} · ${textoCuenta(c)} · ${c.retiro}`
+}
+
 export async function cargarCuentasCliente(supabase, clienteId, { completas = false } = {}) {
   const consultar = (moneda) => supabase.schema('crm')
     .rpc('cuentas_bancarias_cliente_fn', { p_cliente_id: clienteId, p_moneda: moneda })
@@ -104,3 +133,21 @@ export function pintarCuentasCliente(elemento, cuentas, moneda) {
   }
   elemento.appendChild(lista)
 }
+
+export function pintarCuentasAnteriores(elemento, cuentas) {
+  if (!elemento) return
+  elemento.replaceChildren()
+  if (cuentas.length === 0) {
+    elemento.textContent = 'Sin cuentas anteriores.'
+    return
+  }
+  const lista = document.createElement('ul')
+  lista.style.margin = '6px 0 12px'
+  lista.style.paddingLeft = '20px'
+  for (const c of cuentas) {
+    const item = document.createElement('li')
+    item.textContent = textoCuentaAnterior(c)
+    lista.appendChild(item)
+  }
+  elemento.appendChild(lista)
+}
```

## Tests nuevos del portal (144/144 PASS)
```diff
diff --git a/tests/cuentas-cliente-core.test.mjs b/tests/cuentas-cliente-core.test.mjs
index 7307347..80046fd 100644
--- a/tests/cuentas-cliente-core.test.mjs
+++ b/tests/cuentas-cliente-core.test.mjs
@@ -2,6 +2,7 @@ import test from 'node:test'
 import assert from 'node:assert/strict'
 import {
   cargarCuentasCliente, registrarCuentaCliente, puedeVerCuentasCompletas, textoCuenta,
+  cargarHistorialCuentas, textoCuentaAnterior,
 } from '../js/admin/cuentas-cliente-core.js'
 
 test('la ficha consulta ambas monedas y entrega solo datos bancarios enmascarados', async () => {
@@ -111,3 +112,67 @@ test('solo `completas: true` desenmascara; un valor ambiguo no', async () => {
     supabaseConCuentas([CUENTA_BENEFICIARIO]), 'cliente', { completas: 'si' })
   assert.equal(cuenta.numero, '••••4567')
 })
+
+function supabaseHistorial(respuesta, llamadas = []) {
+  return { schema: (esquema) => ({ rpc: async (nombre, args) => {
+    llamadas.push([esquema, nombre, args])
+    return respuesta
+  } }) }
+}
+
+const RETIRADA = {
+  ...CUENTA_BENEFICIARIO, moneda: 'USD', origen: 'contrato',
+  desactivada_en: '2026-09-25T15:00:00Z', desactivada_por_nombre: 'GLORIA PRUEBA',
+}
+
+test('historial: una sola RPC de lectura con el id del cliente', async () => {
+  const llamadas = []
+  await cargarHistorialCuentas(supabaseHistorial({ data: [], error: null }, llamadas), 'cli-1')
+  assert.deepEqual(llamadas, [['crm', 'historial_cuentas_cliente_fn', { p_cliente_id: 'cli-1' }]])
+})
+
+test('historial admin: cuenta retirada completa con fecha y persona', async () => {
+  const [c] = await cargarHistorialCuentas(
+    supabaseHistorial({ data: [RETIRADA], error: null }), 'cli', { completas: true })
+  assert.equal(c.numero, '8983001234567')
+  assert.equal(c.retiro, 'Retirada el 25/09/2026 por GLORIA PRUEBA')
+  const texto = textoCuentaAnterior(c)
+  assert.match(texto, /^Dólares · Interbank · ahorros · N°\u00A08983001234567/)
+  assert.match(texto, /Beneficiario: ANA PEREZ ROJAS \(DNI 40404040\)/)
+  assert.match(texto, /CRM \/ contrato · 26\/09\/2026 · Retirada el 25\/09\/2026 por GLORIA PRUEBA$/)
+})
+
+test('historial sin opción: enmascarado y sin beneficiario', async () => {
+  const [c] = await cargarHistorialCuentas(supabaseHistorial({ data: [RETIRADA], error: null }), 'cli')
+  const texto = textoCuentaAnterior(c)
+  for (const dato of ['8983001234567', '00389801234567890123', 'ANA PEREZ', '40404040']) {
+    assert.equal(texto.includes(dato), false, dato)
+  }
+  assert.match(texto, /N°\u00A0••••4567 · CCI\u00A0••••0123/)
+})
+
+test('historial: faltan fecha o persona del retiro', async () => {
+  const [sinFecha, sinPersona] = await cargarHistorialCuentas(supabaseHistorial({ data: [
+    { ...RETIRADA, desactivada_en: null, desactivada_por_nombre: null },
+    { ...RETIRADA, desactivada_por_nombre: null },
+  ], error: null }), 'cli')
+  assert.equal(sinFecha.retiro, 'Retirada · fecha no registrada')
+  assert.equal(sinPersona.retiro, 'Retirada el 25/09/2026 · persona no registrada')
+})
+
+test('historial: la fecha de retiro se lee en hora de Lima', async () => {
+  // 03:00 UTC del 26/09 son las 22:00 del 25/09 en Lima.
+  const [c] = await cargarHistorialCuentas(supabaseHistorial({ data: [
+    { ...RETIRADA, desactivada_en: '2026-09-26T03:00:00Z' },
+  ], error: null }), 'cli')
+  assert.equal(c.retiro, 'Retirada el 25/09/2026 por GLORIA PRUEBA')
+})
+
+test('historial: un error o una respuesta rara no se presenta como vacío', async () => {
+  await assert.rejects(
+    cargarHistorialCuentas(supabaseHistorial({ data: null, error: { code: '42501' } }), 'cli'),
+    /No se pudo cargar el historial/)
+  await assert.rejects(
+    cargarHistorialCuentas(supabaseHistorial({ data: { x: 1 }, error: null }), 'cli'),
+    /No se pudo cargar el historial/)
+})
```
