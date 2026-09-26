ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: Portal admin · Clientes — «Cuentas» fuera de «Editar» y cuentas completas para admin (LEVEL 2)

Tu trabajo es REFUTAR: busca fallos reales (fugas de datos bancarios a roles que no deben verlos,
carreras, estados incoherentes, XSS, regresiones de la ficha del analista), no confirmarlo.
Sin hallazgo sin evidencia.

## Contexto

Portal `miavance.com` (vanilla ES modules, Supabase JS v2, sin build). Pantalla `admin/clientes.html` +
`js/admin/clientes.js`, protegida por `verificarGestorCartera()` (roles admin, superadmin y `operaciones`).
El módulo `js/admin/cuentas-cliente-core.js` lo comparten `clientes.js` (importa `?v=2`) y
`js/admin/analista.js` (ficha del analista, importa `?v=1`, NO se modificó y llama
`cargarCuentasCliente(supabase, id)` sin tercer argumento y `pintarCuentasCliente(el, cuentas, moneda)`).

Servidor (NO cambia, transcrito de las migraciones vigentes):
- `crm.cuentas_bancarias_cliente_fn(p_cliente_id, p_moneda)` SECURITY DEFINER: exige
  `private.puede_gestionar_cuentas_cliente(cliente)` (gestor de cartera = `es_admin() OR es_operaciones()`,
  o analista de su cartera, o rol CRM con visibilidad) y devuelve SOLO cuentas activas con columnas
  `cuenta_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, beneficiario_nombre,
  beneficiario_dni, origen, es_cuenta_perfil, creada_en` — números COMPLETOS a todo autorizado.
- `crm.registrar_cuenta_cliente(p_cliente_id, p_cuenta jsonb)` → uuid. Exige lo anterior y además
  `es_gestor_cartera()` o Gerencia CRM o analista dentro de 5 h de crear al cliente. Si ya existe una
  cuenta ACTIVA con el mismo CCI y los mismos datos devuelve su id (idempotente); si mismo CCI con datos
  distintos, la versiona (desactiva la vieja, inserta nueva); CCI distinto → inserta otra cuenta activa.
  No toca `crm.contrato_cuentas_pago` (enlace contrato→cuenta, inmutable por trigger).

Pedido de Miguel (dueño): Gloria (rol `admin`) debe ver número y CCI completos y el titular/beneficiario,
y tener «Añadir cuenta» visible fuera de «Editar cliente»; lo añadido aparece en el CRM. Solo admin y
superadmin ven completo; cualquier otro rol (incluido `operaciones` y analistas) sigue con ••••1234.
Sin cambios de base de datos. Números nunca en logs.

## Cambios

1. `cuentas-cliente-core.js`: `puedeVerCuentasCompletas(rol)`; `cargarCuentasCliente(supabase, id, { completas })`
   desenmascara solo con `completas === true` y añade `titular` solo en ese caso; `textoCuenta(c)` con
   espacio duro tras «N°» y «CCI».
2. `clientes.js`: import `?v=2`; `PUEDE_VER_CUENTAS_COMPLETAS = puedeVerCuentasCompletas(perfil?.rol)` tras
   `setupAdminShell`; «Editar» carga con `{ completas: PUEDE_VER_CUENTAS_COMPLETAS }`; botón «Cuentas» por
   fila (`data-action="cuentas"`, id pasado por `escapeHtml`); modal nuevo con token anti-respuesta-tardía
   (`CUENTAS_MODAL_TOKEN`), validación reutilizada `leerYValidarBancarios('cb', …)` (la misma de «Nuevo»
   y «Editar»: banco, N° `^[A-Za-z0-9-]{1,30}$`, tipo ahorros/corriente, CCI 20 dígitos, beneficiario
   nombre + DNI 8–12 dígitos), `registrarCuentaCliente` y recarga de la lista; botón deshabilitado durante
   el guardado y restaurado en `finally`. El render de la lista usa `textContent` (no innerHTML).
3. `admin/clientes.html`: markup del modal `#modalCuentas` (ids `cb_*`) y `clientes.js?v=50→51`.
   Las utilidades globales ya existentes cierran cualquier `.modal-overlay` con clic en el fondo o ESC.
4. `service-worker.js` `avance-v129→v130` y su pin en un test. Tests nuevos en `tests/cuentas-cliente-core.test.mjs`
   (138/138 PASS; 4 mutantes cazados: operaciones ve completo, flag ambiguo, analista ve beneficiario,
   admin no ve CCI).

Pregunta extra a refutar: `analista.js` sigue importando `cuentas-cliente-core.js?v=1`. Con la CDN
(JS 7 días, el query string forma parte de la clave) puede recibir el archivo viejo o el nuevo bajo `?v=1`.
¿Rompe algo en cualquiera de los dos casos?

## Diff (js)

```diff
diff --git a/js/admin/clientes.js b/js/admin/clientes.js
index 3348da3..a893eb3 100644
--- a/js/admin/clientes.js
+++ b/js/admin/clientes.js
@@ -19,8 +19,8 @@ import { initCampoDocumento } from './documento-ui.js?v=1'
 import { mensajeErrorGuardarCliente } from './clientes-errores-core.js?v=2'
 import { guardarCorreoCliente, validarCorreccionCorreo } from './correo-cliente-core.js?v=1'
 import {
-  cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente
-} from './cuentas-cliente-core.js?v=1'
+  cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente, puedeVerCuentasCompletas
+} from './cuentas-cliente-core.js?v=2'
 
 // CLIENTES_CACHE ahora guarda SOLO la página actual (max PAGE_SIZE filas).
 // El total real está en TOTAL_CLIENTES. Con paginación server-side el cache
@@ -35,6 +35,8 @@ let PUEDE_EDITAR_DOCUMENTO_CLIENTE = false // admin/superadmin; el servidor reva
 let PUEDE_EDITAR_CORREO_CLIENTE = false
 let CUENTAS_EDITAR_CARGADAS = false
 let CUENTAS_EDITAR_TOKEN = 0
+let PUEDE_VER_CUENTAS_COMPLETAS = false // admin/superadmin leen N° y CCI enteros; el resto, ••••1234
+let CUENTAS_MODAL_TOKEN = 0
 /** Mover un cliente de un analista a otro es decision comercial: el asiento
  *  «Operaciones» no lo hace. El corte de verdad esta en el trigger
  *  `proteger_campos_inmutables`, que responde con un error claro; esto evita
@@ -224,7 +226,7 @@ function llenarSelectsBancos() {
       '</optgroup>'
     ).join('') +
     '<option value="Otro">Otro</option>'
-  for (const id of ['n_banco', 'e_banco', 'eu_banco']) {
+  for (const id of ['n_banco', 'e_banco', 'eu_banco', 'cb_banco']) {
     const sel = document.getElementById(id)
     if (sel) sel.innerHTML = opciones
   }
@@ -510,6 +512,7 @@ function renderTabla() {
         <td>
           <div class="table-actions">
             <button class="btn-icon" data-action="editar" data-id="${escapeHtml(c.id)}">Editar</button>
+            <button class="btn-icon" data-action="cuentas" data-id="${escapeHtml(c.id)}" title="Ver y añadir cuentas bancarias">Cuentas</button>
             ${accionToggle}
             <a href="/admin/contratos.html?cliente=${escapeHtml(c.id)}" class="btn-icon" title="Crear nuevo contrato para este cliente">+ Contrato</a>
             ${accionEliminar}
@@ -591,6 +594,7 @@ function onAccion(e) {
   if (!cliente) return
 
   if (action === 'editar') abrirModalEditar(cliente)
+  if (action === 'cuentas') abrirModalCuentas(cliente)
   if (action === 'asignar') abrirModalAsignar(cliente)
   if (action === 'toggle') {
     const activar = e.currentTarget.dataset.activo === 'true'
@@ -599,6 +603,91 @@ function onAccion(e) {
   if (action === 'eliminar') eliminarCliente(cliente)
 }
 
+/* ============================================
+   MODAL: cuentas bancarias (ver y añadir)
+   ============================================ */
+
+function cargarCuentasModal(clienteId) {
+  const token = ++CUENTAS_MODAL_TOKEN
+  const pen = document.getElementById('cb_cuentas_pen')
+  const usd = document.getElementById('cb_cuentas_usd')
+  pen.textContent = 'Cargando cuentas vigentes…'
+  usd.textContent = 'Cargando cuentas vigentes…'
+  void cargarCuentasCliente(supabase, clienteId, { completas: PUEDE_VER_CUENTAS_COMPLETAS }).then((cuentas) => {
+    if (token !== CUENTAS_MODAL_TOKEN) return
+    pintarCuentasCliente(pen, cuentas, 'PEN')
+    pintarCuentasCliente(usd, cuentas, 'USD')
+  }).catch(() => {
+    if (token !== CUENTAS_MODAL_TOKEN) return
+    pen.textContent = 'No se pudieron cargar las cuentas. Vuelve a abrir la ventana.'
+    usd.textContent = ''
+  })
+}
+
+function limpiarFormNuevaCuenta() {
+  for (const campo of ['banco', 'tipo_cuenta', 'numero_cuenta', 'cci', 'beneficiario_nombre', 'beneficiario_dni']) {
+    const el = document.getElementById(`cb_${campo}`)
+    if (el) el.value = ''
+  }
+  document.getElementById('cb_moneda').value = 'PEN'
+  document.getElementById('cb_titular_distinto').checked = false
+  toggleBeneficiario('cb')
+}
+
+function mostrarFormNuevaCuenta(visible) {
+  document.getElementById('cb_nueva_group').classList.toggle('hidden', !visible)
+  document.getElementById('btnMostrarNuevaCuenta').classList.toggle('hidden', visible)
+  document.getElementById('btnGuardarCuenta').classList.toggle('hidden', !visible)
+}
+
+function abrirModalCuentas(cliente) {
+  document.getElementById('cb_clienteId').value = cliente.id
+  document.getElementById('cb_clienteNombre').textContent = cliente.nombre_completo
+  document.getElementById('modalCuentasError').classList.add('hidden')
+  limpiarFormNuevaCuenta()
+  mostrarFormNuevaCuenta(false)
+  cargarCuentasModal(cliente.id)
+  document.getElementById('modalCuentas').classList.remove('hidden')
+}
+
+function cerrarModalCuentas() {
+  CUENTAS_MODAL_TOKEN++
+  document.getElementById('modalCuentas').classList.add('hidden')
+}
+
+async function guardarCuentaNueva(e) {
+  e.preventDefault()
+  const errEl = document.getElementById('modalCuentasError')
+  errEl.classList.add('hidden')
+
+  const clienteId = document.getElementById('cb_clienteId').value
+  const moneda = document.getElementById('cb_moneda').value === 'USD' ? 'USD' : 'PEN'
+  const leido = leerYValidarBancarios('cb', { moneda: moneda === 'USD' ? 'Dólares' : 'Soles' })
+  if (!leido.ok) {
+    errEl.textContent = leido.error
+    errEl.classList.remove('hidden')
+    return
+  }
+
+  const btn = document.getElementById('btnGuardarCuenta')
+  btn.disabled = true
+  btn.textContent = 'Guardando…'
+  try {
+    await registrarCuentaCliente(supabase, clienteId, moneda, leido.datos)
+    limpiarFormNuevaCuenta()
+    mostrarFormNuevaCuenta(false)
+    cargarCuentasModal(clienteId)
+    mostrarExito('Cuenta registrada. Ya aparece también en el CRM.')
+  } catch (error) {
+    // El núcleo ya traduce el error sin repetir los números de la cuenta.
+    errEl.textContent = error.message
+    errEl.classList.remove('hidden')
+  } finally {
+    btn.disabled = false
+    btn.textContent = 'Guardar cuenta'
+  }
+}
+
 /* ============================================
    MINI-MODAL: asignar asesor (acción rápida)
    ============================================ */
@@ -952,7 +1041,7 @@ function abrirModalEditar(cliente) {
   const tokenCuentas = ++CUENTAS_EDITAR_TOKEN
   document.getElementById('e_cuentas_pen').textContent = 'Cargando cuentas vigentes…'
   document.getElementById('e_cuentas_usd').textContent = 'Cargando cuentas vigentes…'
-  void cargarCuentasCliente(supabase, cliente.id).then((cuentas) => {
+  void cargarCuentasCliente(supabase, cliente.id, { completas: PUEDE_VER_CUENTAS_COMPLETAS }).then((cuentas) => {
     if (tokenCuentas !== CUENTAS_EDITAR_TOKEN) return
     pintarCuentasCliente(document.getElementById('e_cuentas_pen'), cuentas, 'PEN')
     pintarCuentasCliente(document.getElementById('e_cuentas_usd'), cuentas, 'USD')
@@ -1718,6 +1807,7 @@ async function recargar() {
   PUEDE_ELIMINAR_CLIENTES = perfil?.rol === 'superadmin' || perfil?.rol === 'admin'
   PUEDE_EDITAR_DOCUMENTO_CLIENTE = PUEDE_ELIMINAR_CLIENTES
   PUEDE_EDITAR_CORREO_CLIENTE = PUEDE_ELIMINAR_CLIENTES
+  PUEDE_VER_CUENTAS_COMPLETAS = puedeVerCuentasCompletas(perfil?.rol)
   PUEDE_ASIGNAR_ANALISTA = perfil?.rol !== 'operaciones'
   // Cargar clientes a granel desde un Excel es una decision de Gloria, no
   // trabajo de cartera: el asiento «Operaciones» da de alta uno a uno.
@@ -1802,6 +1892,13 @@ async function recargar() {
   document.getElementById('e_titular_distinto')?.addEventListener('change', () => toggleBeneficiario('e'))
   document.getElementById('eu_titular_distinto')?.addEventListener('change', () => toggleBeneficiario('eu'))
 
+  // Modal cuentas bancarias (acción «Cuentas» de la fila)
+  document.getElementById('modalCloseCuentas')?.addEventListener('click', cerrarModalCuentas)
+  document.getElementById('btnCerrarCuentas')?.addEventListener('click', cerrarModalCuentas)
+  document.getElementById('btnMostrarNuevaCuenta')?.addEventListener('click', () => mostrarFormNuevaCuenta(true))
+  document.getElementById('formCuentas')?.addEventListener('submit', guardarCuentaNueva)
+  document.getElementById('cb_titular_distinto')?.addEventListener('change', () => toggleBeneficiario('cb'))
+
   // Mini-modal asignar asesor (acción rápida desde la fila)
   document.getElementById('modalCloseAsignar')?.addEventListener('click', cerrarModalAsignar)
   document.getElementById('btnCancelarAsignar')?.addEventListener('click', cerrarModalAsignar)
diff --git a/js/admin/cuentas-cliente-core.js b/js/admin/cuentas-cliente-core.js
index 54b61ef..a401bdc 100644
--- a/js/admin/cuentas-cliente-core.js
+++ b/js/admin/cuentas-cliente-core.js
@@ -1,13 +1,32 @@
 // Fuente bancaria compartida por las fichas de Admin y Analista.
-// La respuesta de la RPC contiene números completos; este módulo solo entrega
-// resúmenes enmascarados a la UI y nunca los escribe en perfiles ni en logs.
+// La respuesta de la RPC contiene números completos; este módulo entrega a la UI
+// resúmenes enmascarados, salvo que la pantalla pida `completas` (solo admin y
+// superadmin), y nunca los escribe en perfiles ni en logs.
 
 export function enmascararCuenta(valor) {
   const ultimos = String(valor ?? '').slice(-4)
   return ultimos ? `••••${ultimos}` : '—'
 }
 
-function resumirCuenta(cuenta) {
+// Pagar al cliente exige leer la cuenta entera: Gloria (admin) y el superadmin
+// la ven completa. Operaciones, analistas y el resto siguen con ••••1234.
+export function puedeVerCuentasCompletas(rol) {
+  return rol === 'admin' || rol === 'superadmin'
+}
+
+function mostrarCompleto(valor) {
+  return String(valor ?? '').trim() || '—'
+}
+
+function describirTitular(cuenta) {
+  if (!cuenta.titular_distinto) return 'Titular: el cliente'
+  const nombre = cuenta.beneficiario_nombre || 'nombre no disponible'
+  return cuenta.beneficiario_dni
+    ? `Beneficiario: ${nombre} (DNI ${cuenta.beneficiario_dni})`
+    : `Beneficiario: ${nombre}`
+}
+
+function resumirCuenta(cuenta, completas) {
   const fecha = cuenta.creada_en
     ? new Date(cuenta.creada_en).toLocaleDateString('es-PE', {
       timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit'
@@ -16,18 +35,27 @@ function resumirCuenta(cuenta) {
   const origen = {
     perfil: 'Perfil migrado', contrato: 'CRM / contrato', portal: 'Ficha de cliente'
   }[cuenta.origen] || 'Origen no disponible'
-  return {
+  const resumen = {
     moneda: cuenta.moneda,
     banco: cuenta.banco || 'Banco no disponible',
     tipo: cuenta.tipo_cuenta || 'Tipo no disponible',
-    numero: enmascararCuenta(cuenta.numero_cuenta),
-    cci: enmascararCuenta(cuenta.cci),
+    numero: completas ? mostrarCompleto(cuenta.numero_cuenta) : enmascararCuenta(cuenta.numero_cuenta),
+    cci: completas ? mostrarCompleto(cuenta.cci) : enmascararCuenta(cuenta.cci),
     origen,
     fecha,
   }
+  if (completas) resumen.titular = describirTitular(cuenta)
+  return resumen
+}
+
+// El espacio duro (\u00A0) evita que «N°» o «CCI» queden en una línea y su
+// número en la siguiente al leer o copiar la cuenta.
+export function textoCuenta(c) {
+  const titular = c.titular ? ` · ${c.titular}` : ''
+  return `${c.banco} · ${c.tipo} · N°\u00A0${c.numero} · CCI\u00A0${c.cci}${titular} · ${c.origen} · ${c.fecha}`
 }
 
-export async function cargarCuentasCliente(supabase, clienteId) {
+export async function cargarCuentasCliente(supabase, clienteId, { completas = false } = {}) {
   const consultar = (moneda) => supabase.schema('crm')
     .rpc('cuentas_bancarias_cliente_fn', { p_cliente_id: clienteId, p_moneda: moneda })
   const [pen, usd] = await Promise.all([consultar('PEN'), consultar('USD')])
@@ -37,7 +65,7 @@ export async function cargarCuentasCliente(supabase, clienteId) {
   return [...pen.data, ...usd.data]
     .sort((a, b) => a.moneda.localeCompare(b.moneda)
       || new Date(b.creada_en).getTime() - new Date(a.creada_en).getTime())
-    .map(resumirCuenta)
+    .map((cuenta) => resumirCuenta(cuenta, completas === true))
 }
 
 export async function registrarCuentaCliente(supabase, clienteId, moneda, datos) {
@@ -71,7 +99,7 @@ export function pintarCuentasCliente(elemento, cuentas, moneda) {
   lista.style.paddingLeft = '20px'
   for (const c of filtradas) {
     const item = document.createElement('li')
-    item.textContent = `${c.banco} · ${c.tipo} · N° ${c.numero} · CCI ${c.cci} · ${c.origen} · ${c.fecha}`
+    item.textContent = textoCuenta(c)
     lista.appendChild(item)
   }
   elemento.appendChild(lista)
```

## Diff (html del modal)

```diff
diff --git a/admin/clientes.html b/admin/clientes.html
index 328c77c..d92b277 100644
--- a/admin/clientes.html
+++ b/admin/clientes.html
@@ -547,6 +547,92 @@
     </div>
   </div>
 
+  <!-- ========== MODAL CUENTAS BANCARIAS (ver y añadir, fuera de «Editar») ========== -->
+  <div class="modal-overlay hidden" id="modalCuentas">
+    <div class="modal">
+      <div class="modal-header">
+        <h2 class="modal-title">Cuentas bancarias</h2>
+        <button class="modal-close" type="button" id="modalCloseCuentas" aria-label="Cerrar">✕</button>
+      </div>
+      <form id="formCuentas" novalidate>
+        <input type="hidden" id="cb_clienteId">
+        <div class="modal-body">
+          <p id="cb_clienteNombre" style="font-weight: 700; font-size: 16px; margin: 0 0 12px;"></p>
+          <div id="modalCuentasError" class="alert alert-danger hidden" role="alert"></div>
+
+          <p style="font-weight: 700; font-size: 14px; margin: 0 0 4px; color: var(--navy);">Soles (PEN)</p>
+          <div id="cb_cuentas_pen" aria-live="polite" style="font-size: 14px;">Cargando cuentas vigentes…</div>
+          <p style="font-weight: 700; font-size: 14px; margin: 8px 0 4px; color: var(--navy);">Dólares (USD)</p>
+          <div id="cb_cuentas_usd" aria-live="polite" style="font-size: 14px;">Cargando cuentas vigentes…</div>
+
+          <button type="button" class="btn btn-secondary" id="btnMostrarNuevaCuenta" style="margin-top: 8px;">+ Añadir cuenta</button>
+
+          <div id="cb_nueva_group" class="hidden" style="margin-top: 14px; padding: 12px; border: 1px solid var(--border); border-radius: var(--radius-sm);">
+            <p style="font-weight: 700; font-size: 14px; margin: 0 0 10px; color: var(--navy);">Nueva cuenta</p>
+            <p class="text-muted" style="font-size: 13px; margin: 0 0 10px;">
+              Se suma a las cuentas del cliente y aparece también en el CRM. No cambia la cuenta de pago de los contratos que ya existen.
+            </p>
+            <div class="form-grid-2">
+              <div class="input-group">
+                <label class="input-label" for="cb_moneda">Moneda</label>
+                <select class="input" id="cb_moneda">
+                  <option value="PEN">Soles (PEN)</option>
+                  <option value="USD">Dólares (USD)</option>
+                </select>
+              </div>
+              <div class="input-group">
+                <label class="input-label" for="cb_banco">Banco</label>
+                <select class="input" id="cb_banco">
+                  <option value="">— Seleccionar banco —</option>
+                </select>
+              </div>
+            </div>
+            <div class="form-grid-2">
+              <div class="input-group">
+                <label class="input-label" for="cb_tipo_cuenta">Tipo de cuenta</label>
+                <select class="input" id="cb_tipo_cuenta">
+                  <option value="">— Seleccionar —</option>
+                  <option value="ahorros">Ahorros</option>
+                  <option value="corriente">Corriente</option>
+                </select>
+              </div>
+              <div class="input-group">
+                <label class="input-label" for="cb_numero_cuenta">N° de cuenta</label>
+                <input type="text" class="input" id="cb_numero_cuenta" maxlength="30" autocomplete="off">
+              </div>
+            </div>
+            <div class="input-group">
+              <label class="input-label" for="cb_cci">CCI — Código Interbancario</label>
+              <input type="text" class="input" id="cb_cci" maxlength="20" minlength="20" pattern="[0-9]{20}" inputmode="numeric" placeholder="20 dígitos" autocomplete="off">
+            </div>
+            <div class="input-group" style="margin-top: 6px;">
+              <label style="display:flex; align-items:center; gap:8px; cursor:pointer; font-size:14px; font-weight:500;">
+                <input type="checkbox" id="cb_titular_distinto" style="width:auto; margin:0;">
+                <span>La cuenta es de un <strong>beneficiario</strong> (no es del socio)</span>
+              </label>
+            </div>
+            <div id="cb_beneficiario_group" class="hidden" style="margin-top: 4px; padding: 12px; background: var(--surface-soft); border-radius: var(--radius-sm);">
+              <div class="form-grid-2">
+                <div class="input-group" style="margin-bottom:0;">
+                  <label class="input-label" for="cb_beneficiario_nombre">Nombre completo del beneficiario</label>
+                  <input type="text" class="input" id="cb_beneficiario_nombre" maxlength="200" style="text-transform:uppercase" autocomplete="off">
+                </div>
+                <div class="input-group" style="margin-bottom:0;">
+                  <label class="input-label" for="cb_beneficiario_dni">DNI del beneficiario</label>
+                  <input type="text" class="input" id="cb_beneficiario_dni" maxlength="20" inputmode="numeric" autocomplete="off">
+                </div>
+              </div>
+            </div>
+          </div>
+        </div>
+        <div class="modal-footer">
+          <button type="button" class="btn btn-secondary" id="btnCerrarCuentas">Cerrar</button>
+          <button type="submit" class="btn btn-primary hidden" id="btnGuardarCuenta">Guardar cuenta</button>
+        </div>
+      </form>
+    </div>
+  </div>
+
   <!-- ========== MODAL IMPORTAR CLIENTES (preview + confirmar) ========== -->
   <div class="modal-overlay hidden" id="modalImportarClientes">
     <div class="modal">
@@ -579,7 +665,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/clientes.js?v=50"></script>
+  <script type="module" src="/js/admin/clientes.js?v=51"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
```

## Tests nuevos

```diff
diff --git a/tests/cuentas-cliente-core.test.mjs b/tests/cuentas-cliente-core.test.mjs
index 4f02e42..7307347 100644
--- a/tests/cuentas-cliente-core.test.mjs
+++ b/tests/cuentas-cliente-core.test.mjs
@@ -1,6 +1,8 @@
 import test from 'node:test'
 import assert from 'node:assert/strict'
-import { cargarCuentasCliente, registrarCuentaCliente } from '../js/admin/cuentas-cliente-core.js'
+import {
+  cargarCuentasCliente, registrarCuentaCliente, puedeVerCuentasCompletas, textoCuenta,
+} from '../js/admin/cuentas-cliente-core.js'
 
 test('la ficha consulta ambas monedas y entrega solo datos bancarios enmascarados', async () => {
   const llamadas = []
@@ -56,3 +58,56 @@ test('registrar cuenta exige el UUID devuelto por la RPC', async () => {
     /No se pudo confirmar la cuenta bancaria/,
   )
 })
+
+function supabaseConCuentas(filasPen) {
+  return { schema: () => ({ rpc: async (_nombre, args) =>
+    ({ data: args.p_moneda === 'PEN' ? filasPen : [], error: null }) }) }
+}
+
+const CUENTA_BENEFICIARIO = {
+  moneda: 'PEN', banco: 'Interbank', tipo_cuenta: 'ahorros',
+  numero_cuenta: '8983001234567', cci: '00389801234567890123',
+  titular_distinto: true, beneficiario_nombre: 'ANA PEREZ ROJAS', beneficiario_dni: '40404040',
+  origen: 'portal', creada_en: '2026-09-26T12:00:00Z',
+}
+
+test('solo admin y superadmin ven las cuentas completas', () => {
+  assert.equal(puedeVerCuentasCompletas('admin'), true)
+  assert.equal(puedeVerCuentasCompletas('superadmin'), true)
+  for (const rol of ['operaciones', 'analista', 'comercial', 'cliente', '', null, undefined]) {
+    assert.equal(puedeVerCuentasCompletas(rol), false, `rol ${rol}`)
+  }
+})
+
+test('admin: número, CCI y beneficiario completos en la ficha', async () => {
+  const [cuenta] = await cargarCuentasCliente(
+    supabaseConCuentas([CUENTA_BENEFICIARIO]), 'cliente', { completas: true })
+  assert.equal(cuenta.numero, '8983001234567')
+  assert.equal(cuenta.cci, '00389801234567890123')
+  assert.equal(cuenta.titular, 'Beneficiario: ANA PEREZ ROJAS (DNI 40404040)')
+  assert.equal(cuenta.origen, 'Ficha de cliente')
+  assert.match(textoCuenta(cuenta), /N°\u00A08983001234567 · CCI\u00A000389801234567890123 · Beneficiario: ANA PEREZ ROJAS/)
+})
+
+test('admin: una cuenta propia del cliente se rotula como tal', async () => {
+  const [cuenta] = await cargarCuentasCliente(
+    supabaseConCuentas([{ ...CUENTA_BENEFICIARIO, titular_distinto: false }]), 'cliente', { completas: true })
+  assert.equal(cuenta.titular, 'Titular: el cliente')
+})
+
+test('analista (sin opción): sigue enmascarado y sin datos del beneficiario', async () => {
+  const [cuenta] = await cargarCuentasCliente(supabaseConCuentas([CUENTA_BENEFICIARIO]), 'cliente')
+  assert.equal(cuenta.numero, '••••4567')
+  assert.equal(cuenta.cci, '••••0123')
+  assert.equal('titular' in cuenta, false)
+  const serializado = JSON.stringify(cuenta) + textoCuenta(cuenta)
+  for (const dato of ['8983001234567', '00389801234567890123', 'ANA PEREZ', '40404040']) {
+    assert.equal(serializado.includes(dato), false, dato)
+  }
+})
+
+test('solo `completas: true` desenmascara; un valor ambiguo no', async () => {
+  const [cuenta] = await cargarCuentasCliente(
+    supabaseConCuentas([CUENTA_BENEFICIARIO]), 'cliente', { completas: 'si' })
+  assert.equal(cuenta.numero, '••••4567')
+})
```
