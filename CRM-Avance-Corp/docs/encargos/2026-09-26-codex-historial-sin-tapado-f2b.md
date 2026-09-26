ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: Cuentas de Gloria · F2b — quien ve la cuenta la ve completa (LEVEL 3: datos bancarios)

Tu trabajo es REFUTAR fallos reales: que el público crezca (más roles/clientes que antes), que la
autorización o el filtro se degraden, oráculos, permisos, reversa que no restaure, regresiones de las
pantallas (clientes.js/analista.js), caché/versiones. Sin hallazgo sin evidencia.

## Decisión de negocio (NO es un hallazgo)

Miguel (dueño) decidió el 26/09, tras ver el mapa de exposición: «quiero que el analista también vea
las cuentas» y eligió «todos los que ya ven la cuenta la ven completa» (admin, superadmin, Operaciones
y analistas), como el CRM, que ya deja COPIAR el N° completo a vendedores/supervisores/gerencia.
Por eso esta fase quita el tapado que en la F2 se añadió por tu P1 de la R1: el público autorizado es
el MISMO que ya lee las cuentas VIGENTES completas por crm.cuentas_bancarias_cliente_fn (sin cambios).
No se discute esa decisión; sí que el cambio no amplíe el público ni rompa nada.

## Estado vivo en producción (antes)

`private.historial_cuentas_cliente_autorizado` = versión de 20260926193424 (md5(prosrc)
22019f9bee83548f756ef3de03157b1a), con tapado por `public.es_admin()`. Puerta INVOKER
`crm.historial_cuentas_cliente_fn` delega en ella. EXECUTE = {postgres, authenticated}.

## Migración nueva (texto íntegro)

```sql
-- Cuentas de Gloria · F2b: el historial de cuentas retiradas deja de tapar datos.
--
-- Qué hace: recrea private.historial_cuentas_cliente_autorizado (de 20260926193424) SIN el
-- tapado por rol. Misma firma, misma autorización (private.puede_gestionar_cuentas_cliente),
-- mismo filtro activa = false, mismo join de personal. Todo autorizado recibe N°, CCI y
-- beneficiario (nombre y DNI) completos.
--
-- Por qué: decisión de Miguel (26/09/2026) tras ver el mapa de las 4 vías: «quiero que el
-- analista también vea las cuentas»; eligió «todos los que ya ven la cuenta la ven completa»
-- (admin, superadmin, Operaciones y analistas; igual que el CRM, que ya deja copiar el N°).
-- Esto revierte a propósito el tapado que se añadió por la revisión de Codex (R1 P1): aquella
-- «fuga» dejó de serlo porque el negocio decide que ese público debe ver los datos.
-- El público NO cambia: el mismo gate que ya lee las cuentas vigentes completas por
-- crm.cuentas_bancarias_cliente_fn. Permisos, firma y puerta crm.* sin cambios.
--
-- Reversión: ../scripts/cuentas-gloria/reversa-historial-sin-tapado.sql (repone el cuerpo
-- exacto de 20260926193424, con huella md5(prosrc) 22019f9bee83548f756ef3de03157b1a).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $precondicion$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)'))
     is distinct from '22019f9bee83548f756ef3de03157b1a' then
    raise exception 'SIN_TAPADO: el núcleo vivo no es la versión de 20260926193424; no se toca';
  end if;
end;
$precondicion$;

create or replace function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
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

  -- Decisión de Miguel (26/09): quien puede ver la cuenta la ve completa; sin tapado.
  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
         cb.numero_cuenta, cb.cci, cb.titular_distinto,
         cb.beneficiario_nombre, cb.beneficiario_dni, cb.origen,
         cb.creado_en, cb.desactivada_en, pr.nombre_completo
  from crm.cuentas_bancarias cb
  -- Solo se resuelve el nombre de personal (nunca el de un cliente) bajo DEFINER.
  left join public.perfiles pr on pr.id = cb.desactivada_por and pr.rol <> 'cliente'
  where cb.cliente_id = p_cliente_id
    and cb.activa is false
  order by cb.desactivada_en desc nulls last, cb.creado_en desc, cb.id desc;
end;
$function$;

comment on function private.historial_cuentas_cliente_autorizado(uuid) is
  'Cuentas bancarias RETIRADAS (activa = false) del cliente, con fecha y nombre (solo de personal) de quien las retiró. Autoriza con private.puede_gestionar_cuentas_cliente; 42501 si no. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias. DATOS SENSIBLES: N° de cuenta, CCI y beneficiario (nombre y DNI) completos para todo autorizado (decisión de Miguel 26/09/2026).';
comment on function crm.historial_cuentas_cliente_fn(uuid) is
  'Puerta de pantalla (INVOKER) del historial de cuentas retiradas del cliente; delega en private.historial_cuentas_cliente_autorizado. La usa la ventana «Cuentas» del panel admin del portal. DATOS SENSIBLES: completos para todo autorizado.';

do $postflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and pg_catalog.strpos(p.prosrc, 'es_admin') = 0
  ) then
    raise exception 'SIN_TAPADO: modo de seguridad, search_path o cuerpo inesperado';
  end if;
  -- EXECUTE exactamente a authenticated (create or replace conserva la ACL; se comprueba).
  if exists (
    select 1
    from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
    where p.oid in ('crm.historial_cuentas_cliente_fn(uuid)'::regprocedure,
                    'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure)
      and a.privilege_type = 'EXECUTE'
      and a.grantee not in ('authenticated'::regrole::oid, p.proowner)
  ) or not pg_catalog.has_function_privilege('authenticated', 'private.historial_cuentas_cliente_autorizado(uuid)', 'EXECUTE') then
    raise exception 'SIN_TAPADO: permisos inesperados tras aplicar';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Reversa
```sql
-- REVERSA de 20260926200757_crm_historial_cuentas_sin_tapado: repone EXACTAMENTE el núcleo de
-- 20260926193424 (con tapado por rol). Huella esperada al terminar: 22019f9bee83548f756ef3de03157b1a.
begin;
set local lock_timeout = '5s';
create or replace function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
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
declare
  v_completo boolean;
begin
  if p_cliente_id is null
     or not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  v_completo := coalesce((select public.es_admin()), false);

  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
         -- El N° admite de 1 a 30 caracteres: se muestran como mucho 4 y nunca más de la
         -- mitad, para que un número corto no salga entero (revisión Codex R2).
         case when v_completo then cb.numero_cuenta
              else '••••' || pg_catalog.right(cb.numero_cuenta,
                     least(4, pg_catalog.length(cb.numero_cuenta) / 2)) end,
         case when v_completo then cb.cci
              else '••••' || pg_catalog.right(cb.cci, 4) end,
         cb.titular_distinto,
         case when v_completo then cb.beneficiario_nombre end,
         case when v_completo then cb.beneficiario_dni end,
         cb.origen,
         cb.creado_en, cb.desactivada_en, pr.nombre_completo
  from crm.cuentas_bancarias cb
  -- Solo se resuelve el nombre de personal (nunca el de un cliente) bajo DEFINER.
  left join public.perfiles pr on pr.id = cb.desactivada_por and pr.rol <> 'cliente'
  where cb.cliente_id = p_cliente_id
    and cb.activa is false
  order by cb.desactivada_en desc nulls last, cb.creado_en desc, cb.id desc;
end;
$function$;

comment on function private.historial_cuentas_cliente_autorizado(uuid) is
  'Cuentas bancarias RETIRADAS (activa = false) del cliente, con fecha y nombre de quien las retiró. Autoriza con private.puede_gestionar_cuentas_cliente; 42501 si no. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias. DATOS SENSIBLES: N° de cuenta, CCI y beneficiario (nombre y DNI) salen completos solo para public.es_admin(); al resto, N° y CCI tapados y beneficiario NULL.';
comment on function crm.historial_cuentas_cliente_fn(uuid) is
  'Puerta de pantalla (INVOKER) del historial de cuentas retiradas del cliente; delega en private.historial_cuentas_cliente_autorizado. La usa la ventana «Cuentas» del panel admin del portal. DATOS SENSIBLES: el núcleo los tapa para quien no es admin/superadmin.';
do $chk$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = 'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure)
     is distinct from '22019f9bee83548f756ef3de03157b1a' then
    raise exception 'REVERSA: la huella repuesta no es la de 20260926193424';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;
```

## Evidencia del ensayo (banco Docker, usuarios ficticios, ROLLBACK)
- Estado prod reproducido (huella 22019f9b…). Tras aplicar: catálogo antes/después difiere SOLO en la línea del núcleo privado (md5 de pg_get_functiondef); ACL idéntica. Huella nueva md5(prosrc) 0806cc1937c1c5899362f69dd829a60a.
- Prueba: admin 2 · operaciones 2 · analista de cartera 2 · analista ajeno 42501 · cliente 42501 · anon 42501 · inexistente/no-cliente/inactivo/NULL mismo 42501 y mismo mensaje · admin, Operaciones y analista reciben N°, CCI y DNI completos · N° corto completo · mutantes CAZADOS: sin autorización, sin filtro activa=false, CON tapado.
- Reversa: huella vuelve exactamente a 22019f9b…; catálogo idéntico al estado F2.

## Portal (diff)
```diff
diff --git a/admin/analista.html b/admin/analista.html
index fbdcb44..f7b61f3 100644
--- a/admin/analista.html
+++ b/admin/analista.html
@@ -485,6 +485,6 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/analista.js?v=31"></script>
+  <script type="module" src="/js/admin/analista.js?v=32"></script>
 </body>
 </html>
diff --git a/admin/clientes.html b/admin/clientes.html
index 9a67bbe..eafe46c 100644
--- a/admin/clientes.html
+++ b/admin/clientes.html
@@ -667,7 +667,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/clientes.js?v=52"></script>
+  <script type="module" src="/js/admin/clientes.js?v=53"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
diff --git a/js/admin/analista.js b/js/admin/analista.js
index 917c26c..4a42528 100644
--- a/js/admin/analista.js
+++ b/js/admin/analista.js
@@ -39,7 +39,7 @@ import { normalizarTitulares, etiquetaDocumento } from './titulares-core.js?v=1'
 import { crearSelectorCuentaContrato } from './cuenta-contrato-ui.js?v=1'
 import {
   cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente
-} from './cuentas-cliente-core.js?v=1'
+} from './cuentas-cliente-core.js?v=4'
 
 // Editor de co-titulares del modal de contrato (instanciado una vez en la init).
 let EDITOR_TITULARES = null
diff --git a/js/admin/clientes.js b/js/admin/clientes.js
index 445ada7..ff06221 100644
--- a/js/admin/clientes.js
+++ b/js/admin/clientes.js
@@ -19,9 +19,9 @@ import { initCampoDocumento } from './documento-ui.js?v=1'
 import { mensajeErrorGuardarCliente } from './clientes-errores-core.js?v=2'
 import { guardarCorreoCliente, validarCorreccionCorreo } from './correo-cliente-core.js?v=1'
 import {
-  cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente, puedeVerCuentasCompletas,
+  cargarCuentasCliente, pintarCuentasCliente, registrarCuentaCliente,
   cargarHistorialCuentas, pintarCuentasAnteriores
-} from './cuentas-cliente-core.js?v=3'
+} from './cuentas-cliente-core.js?v=4'
 
 // CLIENTES_CACHE ahora guarda SOLO la página actual (max PAGE_SIZE filas).
 // El total real está en TOTAL_CLIENTES. Con paginación server-side el cache
@@ -36,7 +36,6 @@ let PUEDE_EDITAR_DOCUMENTO_CLIENTE = false // admin/superadmin; el servidor reva
 let PUEDE_EDITAR_CORREO_CLIENTE = false
 let CUENTAS_EDITAR_CARGADAS = false
 let CUENTAS_EDITAR_TOKEN = 0
-let PUEDE_VER_CUENTAS_COMPLETAS = false // admin/superadmin leen N° y CCI enteros; el resto, ••••1234
 let CUENTAS_MODAL_TOKEN = 0
 /** Mover un cliente de un analista a otro es decision comercial: el asiento
  *  «Operaciones» no lo hace. El corte de verdad esta en el trigger
@@ -616,7 +615,7 @@ function cargarCuentasModal(clienteId) {
   pen.textContent = 'Cargando cuentas vigentes…'
   usd.textContent = 'Cargando cuentas vigentes…'
   anteriores.textContent = 'Cargando cuentas anteriores…'
-  void cargarCuentasCliente(supabase, clienteId, { completas: PUEDE_VER_CUENTAS_COMPLETAS }).then((cuentas) => {
+  void cargarCuentasCliente(supabase, clienteId).then((cuentas) => {
     if (token !== CUENTAS_MODAL_TOKEN) return
     pintarCuentasCliente(pen, cuentas, 'PEN')
     pintarCuentasCliente(usd, cuentas, 'USD')
@@ -626,7 +625,7 @@ function cargarCuentasModal(clienteId) {
     usd.textContent = ''
   })
   // El historial va aparte: si falla, las cuentas vigentes se siguen viendo.
-  void cargarHistorialCuentas(supabase, clienteId, { completas: PUEDE_VER_CUENTAS_COMPLETAS }).then((cuentas) => {
+  void cargarHistorialCuentas(supabase, clienteId).then((cuentas) => {
     if (token !== CUENTAS_MODAL_TOKEN) return
     pintarCuentasAnteriores(anteriores, cuentas)
   }).catch(() => {
@@ -1064,7 +1063,7 @@ function abrirModalEditar(cliente) {
   const tokenCuentas = ++CUENTAS_EDITAR_TOKEN
   document.getElementById('e_cuentas_pen').textContent = 'Cargando cuentas vigentes…'
   document.getElementById('e_cuentas_usd').textContent = 'Cargando cuentas vigentes…'
-  void cargarCuentasCliente(supabase, cliente.id, { completas: PUEDE_VER_CUENTAS_COMPLETAS }).then((cuentas) => {
+  void cargarCuentasCliente(supabase, cliente.id).then((cuentas) => {
     if (tokenCuentas !== CUENTAS_EDITAR_TOKEN) return
     pintarCuentasCliente(document.getElementById('e_cuentas_pen'), cuentas, 'PEN')
     pintarCuentasCliente(document.getElementById('e_cuentas_usd'), cuentas, 'USD')
@@ -1830,7 +1829,6 @@ async function recargar() {
   PUEDE_ELIMINAR_CLIENTES = perfil?.rol === 'superadmin' || perfil?.rol === 'admin'
   PUEDE_EDITAR_DOCUMENTO_CLIENTE = PUEDE_ELIMINAR_CLIENTES
   PUEDE_EDITAR_CORREO_CLIENTE = PUEDE_ELIMINAR_CLIENTES
-  PUEDE_VER_CUENTAS_COMPLETAS = puedeVerCuentasCompletas(perfil?.rol)
   PUEDE_ASIGNAR_ANALISTA = perfil?.rol !== 'operaciones'
   // Cargar clientes a granel desde un Excel es una decision de Gloria, no
   // trabajo de cartera: el asiento «Operaciones» da de alta uno a uno.
diff --git a/js/admin/cuentas-cliente-core.js b/js/admin/cuentas-cliente-core.js
index 4abaa0d..d2aa181 100644
--- a/js/admin/cuentas-cliente-core.js
+++ b/js/admin/cuentas-cliente-core.js
@@ -1,21 +1,7 @@
-// Fuente bancaria compartida por las fichas de Admin y Analista.
-// La respuesta de la RPC contiene números completos; este módulo entrega a la UI
-// resúmenes enmascarados, salvo que la pantalla pida `completas` (solo admin y
-// superadmin), y nunca los escribe en perfiles ni en logs.
-
-export function enmascararCuenta(valor) {
-  const texto = String(valor ?? '')
-  // El historial ya llega tapado desde el servidor para quien no es admin.
-  if (texto.startsWith('••••')) return texto
-  const ultimos = texto.slice(-4)
-  return ultimos ? `••••${ultimos}` : '—'
-}
-
-// Pagar al cliente exige leer la cuenta entera: Gloria (admin) y el superadmin
-// la ven completa. Operaciones, analistas y el resto siguen con ••••1234.
-export function puedeVerCuentasCompletas(rol) {
-  return rol === 'admin' || rol === 'superadmin'
-}
+// Fuente bancaria compartida por las fichas de Admin, Operaciones y Analista.
+// Decisión de Miguel (26/09/2026): quien puede ver la cuenta la ve completa —
+// N°, CCI y titular/beneficiario—, igual que el CRM. Nunca se escriben en
+// perfiles ni en logs.
 
 function mostrarCompleto(valor) {
   return String(valor ?? '').trim() || '—'
@@ -29,7 +15,7 @@ function describirTitular(cuenta) {
     : `Beneficiario: ${nombre}`
 }
 
-function resumirCuenta(cuenta, completas) {
+function resumirCuenta(cuenta) {
   const fecha = cuenta.creada_en
     ? new Date(cuenta.creada_en).toLocaleDateString('es-PE', {
       timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit'
@@ -42,12 +28,12 @@ function resumirCuenta(cuenta, completas) {
     moneda: cuenta.moneda,
     banco: cuenta.banco || 'Banco no disponible',
     tipo: cuenta.tipo_cuenta || 'Tipo no disponible',
-    numero: completas ? mostrarCompleto(cuenta.numero_cuenta) : enmascararCuenta(cuenta.numero_cuenta),
-    cci: completas ? mostrarCompleto(cuenta.cci) : enmascararCuenta(cuenta.cci),
+    numero: mostrarCompleto(cuenta.numero_cuenta),
+    cci: mostrarCompleto(cuenta.cci),
+    titular: describirTitular(cuenta),
     origen,
     fecha,
   }
-  if (completas) resumen.titular = describirTitular(cuenta)
   return resumen
 }
 
@@ -68,16 +54,15 @@ function describirRetiro(cuenta) {
     : `Retirada el ${fecha} · persona no registrada`
 }
 
-// Historial: versiones retiradas (activa = false), la más reciente primero. Mismo
-// enmascarado por rol que las vigentes.
-export async function cargarHistorialCuentas(supabase, clienteId, { completas = false } = {}) {
+// Historial: versiones retiradas (activa = false), la más reciente primero.
+export async function cargarHistorialCuentas(supabase, clienteId) {
   const { data, error } = await supabase.schema('crm')
     .rpc('historial_cuentas_cliente_fn', { p_cliente_id: clienteId })
   if (error || !Array.isArray(data)) {
     throw new Error('No se pudo cargar el historial de cuentas.')
   }
   return data.map((cuenta) => ({
-    ...resumirCuenta(cuenta, completas === true),
+    ...resumirCuenta(cuenta),
     retiro: describirRetiro(cuenta),
   }))
 }
@@ -87,7 +72,7 @@ export function textoCuentaAnterior(c) {
   return `${moneda} · ${textoCuenta(c)} · ${c.retiro}`
 }
 
-export async function cargarCuentasCliente(supabase, clienteId, { completas = false } = {}) {
+export async function cargarCuentasCliente(supabase, clienteId) {
   const consultar = (moneda) => supabase.schema('crm')
     .rpc('cuentas_bancarias_cliente_fn', { p_cliente_id: clienteId, p_moneda: moneda })
   const [pen, usd] = await Promise.all([consultar('PEN'), consultar('USD')])
@@ -97,7 +82,7 @@ export async function cargarCuentasCliente(supabase, clienteId, { completas = fa
   return [...pen.data, ...usd.data]
     .sort((a, b) => a.moneda.localeCompare(b.moneda)
       || new Date(b.creada_en).getTime() - new Date(a.creada_en).getTime())
-    .map((cuenta) => resumirCuenta(cuenta, completas === true))
+    .map((cuenta) => resumirCuenta(cuenta))
 }
 
 export async function registrarCuentaCliente(supabase, clienteId, moneda, datos) {
diff --git a/service-worker.js b/service-worker.js
index 442bcd7..7c6b8f7 100644
--- a/service-worker.js
+++ b/service-worker.js
@@ -14,7 +14,7 @@
  * viejo en `activate` y los clientes reciben la versión fresca al recargar.
  */
 
-const CACHE_VERSION = 'avance-v131'
+const CACHE_VERSION = 'avance-v132'
 
 // Solo pre-cacheamos las páginas del cliente. Las del /admin/* las cachea el
 // SW cuando un admin las visita (network-first con stale fallback). Pre-cachear
```

## Tests del portal: 141/141 PASS; mutantes (N° tapado, CCI tapado, sin titular) CAZADOS.
