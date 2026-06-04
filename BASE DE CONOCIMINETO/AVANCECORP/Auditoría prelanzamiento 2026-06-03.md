---
tags: [auditoria, seguridad, prelanzamiento, analista]
actualizado: 2026-06-03
veredicto: lanzar-con-reservas
---

# Auditoría de prelanzamiento — 2026-06-03

Auditoría **multi-agente exhaustiva** (45 agentes, verificación adversarial de cada hallazgo) de los **últimos cambios sin commitear** del portal en la rama `auditoria-prelanzamiento`: el [[Rol Analista]] + Bandeja, el flujo reset-password, el timer de inactividad, y los diffs grandes de `pagos.js` / `clientes.js` / `contratos.js`. El backend se verificó **en vivo** contra Supabase (RLS, RPCs, triggers, advisors), en solo lectura.

## Veredicto: **LANZAR CON RESERVAS**
- **0 críticas · 1 alta · 4 medias · 7 bajas · 13 info.**
- Hay **un único bloqueante** (el XSS de abajo). Arreglarlo (es barato y central) y se puede lanzar.

## Bloqueante (arreglar antes de lanzar)

### XSS almacenado analista → admin por `escapeHtml` ciego a comillas — ALTA
- **Dónde:** `escapeHtml` en `js/admin/_helpers.js:47` (y las copias cliente `js/novedades.js:25`, `js/perfil.js:155`).
- **Qué es:** `escapeHtml` usa el truco `textContent → innerHTML`, que escapa `< > &` pero **no las comillas** (`"` `'`). Su salida se mete dentro de atributos `data-label="…"` en los buscadores del admin → un valor con `"` rompe el atributo e inyecta un manejador de evento (`onmouseover`).
- **Sinks confirmados:** `js/admin/contratos.js:948`, `js/admin/documentos.js:133`, `js/admin/novedades.js:487`.
- **Vía de ataque:** el [[Rol Analista]] crea clientes con nombre de **texto libre** (la edge `crear-cliente` solo hace `.trim()`). Un nombre trampa como `x" onmouseover="…` queda guardado literal. Cuando un **admin/superadmin** abre el combobox, el JS se ejecuta en su sesión → puede robar el token de Supabase (vive en `localStorage`) y actuar como admin. **Cruza la frontera analista→admin que la RLS protege.** La CSP mantiene `'unsafe-inline'`, así que no lo frena.
- **Arreglo (1 cambio central):** que `escapeHtml` reemplace también `"`→`&quot;` y `'`→`&#39;`, en `_helpers.js` y las copias cliente. Cubre los 4 sinks de golpe (incl. `imagen_url` en `src="…"`). Defensa extra: normalizar/rechazar comillas en el nombre al dar de alta. Subir `?v` de los archivos tocados.

## Medias (recomendado antes de lanzar; baratas)

1. **Límites de capital/tasa solo en el navegador** (`js/admin/analista.js:555-587`). El servidor (RPC `crear_contrato`/`actualizar_contrato`, tabla `contratos`) **no valida rangos**: un analista podría llamar la RPC directo y crear un contrato con tasa/capital absurdos. Además **crear contrato no tiene la ventana de 5 h** que sí tiene corregir → superficie de fraude (acotada: solo sus clientes, queda en `audit_log`/bandeja). *Arreglo:* `RAISE EXCEPTION` de rango + `CHECK` en `contratos`; idealmente recalcular el cronograma dentro de la RPC.
2. **El aviso de "pago parcial" no salta desde la Agenda** (`js/admin/pagos.js:1133-1140`, `:396`). La guarda lee el monto programado de `CRONOGRAMA_CACHE`, que solo se llena al **expandir** una fila en otras pestañas; desde la Agenda (vista por defecto) el monto queda en 0 y el aviso nunca aparece → se puede cerrar una cuota como pagada por menos de lo programado sin rastro del faltante. *Arreglo:* pasar el monto programado al modal por variable/campo oculto y validar el parcial también en el servidor.
3. **`reset-password.html` muestra el formulario para cualquier sesión activa** (`js/reset-password.js:33-37`), no solo para enlaces de recovery. *Atenuante fuerte:* Supabase tiene "require reauthentication" activado, así que el guardado real falla desde una sesión normal. Riesgo real **bajo, condicionado** a que ese ajuste siga encendido. *Arreglo:* exigir contexto de recovery (hash o evento `PASSWORD_RECOVERY`); confirmar el ajuste en el dashboard de Supabase.
4. **(4ª media)** El analista puede **crear contratos sin límite de tiempo** para cualquier cliente que registró (es la cara "crear" del punto 1; mismo arreglo).

## Bajas y observaciones (no bloquean)
- Crear contrato del **admin no es atómico** (`contratos.js:901-911`): 2 escrituras con rollback manual → puede dejar un contrato huérfano. Ya existe la solución: migrar a la RPC `crear_contrato` (la usa el analista).
- **`revertirPago` sin la guarda anti-carrera** que sí tiene `confirmarPago` (`pagos.js:1258-1268`).
- **Import de pagos no valida rango de fecha** (`pagos.js:661`): acepta fechas futuras/absurdas → distorsiona reportería.
- **Primer-ingreso:** baja `debe_cambiar_password` en un `try/catch` vacío (`reset-password.js:240-247`); si falla, posible bucle "crea tu contraseña".
- **Accesibilidad pantallas nuevas del analista:** modales sin cierre con **Escape**, sin `role=dialog`/`aria-modal`/trap de foco, y botones < 44px táctiles en móvil.
- **"Recibirás al final" (interés simple)** sobre-cuenta ~1 día cuando el contrato cruza un 29-feb (deriva año bisiesto vs cronograma; ~0,03%). El compuesto coincide exacto. Ver [[Interés compuesto]].
- **La bandeja filtra por el rol ACTUAL** (`bandeja.js:125`): si a un analista se le **cambia el rol**, su historial sale de la vista (los datos siguen en `audit_log`). *Refutado:* **desactivarlo NO lo borra** (la consulta no mira `activo`). Ver [[Rol Analista]].
- **`resilientFetch` reintenta también mutaciones** (`supabase.js:81`) — riesgo bajo (UNIQUEs lo atrapan).
- **Pre-cache del SW con rutas sin `?v`** que nunca matchean (`service-worker.js:33`) — descarga muerta, sin impacto funcional.
- **Interés simple con vencimiento "Personalizado"**: un tramo final parcial no devenga cuota (`contratos.js:299-310`) — decisión de negocio a confirmar con Miguel.

## Lo que se verificó SÓLIDO (fortalezas)
- **La seguridad la impone el servidor, no el navegador:** el analista no tiene escritura directa en `contratos`/`cronograma`; escribe solo por RPC `SECURITY DEFINER` que validan dueño + ventana de 5 h. Ver [[Rol Analista]].
- **El reloj de 5 h no se puede resetear** (trigger `proteger_campos_inmutables` congela `id/creado_en/creado_por`).
- **No hay escalada de rol:** `crear-admin` revalida superadmin y normaliza cualquier rol inesperado a `admin`; el selector "Nuevo miembro" solo existe para superadmin (verificado front + edge).
- **`bandeja_actividad` exige `es_admin()`** → un cliente no lee el `audit_log` por esa vía.
- **Modelo financiero del cliente idéntico al del admin** (interés compuesto byte-a-byte; 100k al 12% a 3 años = 140.492,80 en ambos). Ver [[Interés compuesto]].
- **Fix de fechas UTC** bien aplicado en todas las pantallas. Ver [[Bug de fechas UTC]].
- **CSP enforcing cubre todos los orígenes reales** + cabeceras de seguridad completas (HSTS, X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy, COOP).
- **Manejo de pagos sólido:** anti-carrera al confirmar, neutralización de fórmulas al exportar Excel, validación de montos contra BD al importar, totales por moneda, idempotencia de [[Notificaciones de pagos]].
- **Barrido de secretos limpio:** ninguna `service_role`/JWT/VAPID privada/contraseña en el frontend (solo la anon key esperada).
- **La propagación del Service Worker (v37→v68) sirve el `auth.js` nuevo** pese a mantener su `?v=17`; Realtime sin fugas (la app es multipágina).

## Nota de cobertura
El finder automático de la dimensión `clientes.js`/`contratos.js` falló (devolvió un resumen vacío); se **rellenó con un pase manual enfocado** que confirmó esa área sólida (importador, selector de rol, cronograma) salvo el sink XSS de `contratos.js:948` (mismo bloqueante).

## Notas relacionadas
[[Auditorías del portal]] · [[Rol Analista]] · [[Arquitectura del portal]] · [[Clave temporal = DNI]] · [[Interés compuesto]] · [[Notificaciones de pagos]] · [[Bug de fechas UTC]] · [[Inicio]]
