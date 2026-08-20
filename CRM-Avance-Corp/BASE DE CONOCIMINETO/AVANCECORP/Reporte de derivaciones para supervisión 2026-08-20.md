# Reporte de derivaciones para supervisión — 2026-08-20

Relacionado con [[Historial de derivaciones de Coordinacion]] y [[Centro de rescate de descartes 2026-08-20]].

## Propósito

El módulo independiente **Derivar leads** permite al supervisor repartir con
criterio justo: ver cuántos leads derivó ayer o en un rango de fechas, el
capital estimado que movió hacia cada asesor y lo que ya está preparando para
repartir hoy. **Gestión de equipo** queda enfocada en seguimiento, cola y
desempeño, sin controles para derivar.

## Fuente de verdad y alcance

- El reporte histórico usa `crm.lead_asignaciones`, no el monto actual del
  lead. Cada episodio conserva la fotografía de monto y moneda que recibió el
  asesor; por eso el capital de ayer y el de siete días no se alteran si el
  lead se edita después.
- La tarjeta incluye solo asesores activos del equipo directo vigente del
  supervisor. El período se calcula en `America/Lima` y puede ser ayer,
  últimos siete días o un rango inclusivo de hasta 366 días.
- Las RPC entregan únicamente nombre del lead, asesor, monto/moneda y hora para
  las operaciones reversibles de hoy. Nunca exponen teléfono, correo, DNI o
  notas libres.

## Experiencia de uso

- La pantalla **Derivar leads** conserva el lenguaje visual del CRM y concentra
  en un solo lugar el reporte por asesor, los filtros, el borrador de reparto y
  las devoluciones del día. Al elegir un rango cambian todas las cifras de sus
  tarjetas: derivados, capital derivado, sin gestión y contactabilidad.
- `Hoy N · borrador` significa que el supervisor ya eligió leads para ese
  asesor, pero todavía no guardó. Puede cambiar el destino, quitar un lead o
  descartar todo el borrador sin modificar ningún dueño.
- Guardar envía el lote completo: se aplica entero o no se aplica. Al guardar,
  los contadores de hoy pasan a evidencia persistida.
- La sección **Derivaciones guardadas hoy** permite devolver un lead a la
  bandeja del supervisor solo mientras el asesor no haya registrado gestión.
  Cualquier actividad o tarea creada por el asesor cuenta como gestión. Si ya
  hubo gestión, no se reescribe la historia ni se permite la devolución.
- **Guardadas hoy** muestra cinco movimientos por página y usa la paginación
  compartida del CRM. Así conserva el total del día y el orden más reciente
  primero sin alargar indefinidamente la pantalla ni crear un segundo scroll.
- Una devolución válida **descuenta** el lead, el capital y el contador de hoy
  de la tarjeta del asesor. El episodio cerrado sigue en el ledger para
  auditoría, pero no pesa en la decisión de reparto justo porque el asesor ya
  no conserva esa carga.

## Auditoría y seguridad

`crm.derivar_leads_equipo_fn` y `crm.revertir_derivacion_equipo_fn` no crean
una bitácora paralela. Actualizan `crm.leads`; los triggers existentes crean la
actividad de reasignación y abren o cierran el episodio del ledger. Ambas
operaciones validan supervisor activo, equipo directo activo, propiedad de la
bandeja y el candado **No Insista**. Las tres RPC usan `security definer`,
`search_path` vacío, revocación explícita a `public`/`anon` y `grant execute`
solo a `authenticated`. Un guard `before insert` hace que registrar gestión y
devolver compitan por el mismo lock del lead y revalida al dueño después de
cualquier espera: puede ganar una de las dos operaciones, nunca ambas. El
guard sella en el servidor, después de obtener el lock, la hora de cualquier
gestión manual para que un timestamp atrasado o una espera concurrente no
oculten trabajo ya realizado. Un
segundo guard impide que el supervisor eluda la regla de devolución con un
`PATCH` directo sobre el dueño del lead: esa transición solo se habilita dentro
de la RPC, después de validar que no exista actividad ni tarea. Guardado y
devolución toman primero el advisory lock compartido de la jerarquía y luego
bloquean en el orden `lead → supervisor → asesor`, revalidando el roster bajo
lock. Así tampoco forman un ciclo con una baja o traslado concurrente del
equipo.

## Despliegue y evidencia de producción

La migración
`20260820174320_crm_reporte_derivaciones_equipo_supervisor.sql` se aplicó en
Supabase producción antes de publicar el frontend. El oráculo transaccional
`supabase/scripts/test-reporte-derivaciones-equipo.sql` prueba permisos,
atomicidad, equipo directo, snapshot de capital, bloqueo tras cualquier
actividad o tarea, payloads con hora atrasada, bypass por `PATCH`, arrays no
canónicos y que devolver deshaga las cifras sin borrar la auditoría. La
migración, su postflight y el oráculo pasaron primero en PostgreSQL 17 local y
después en la rama temporal de Supabase. El gate RLS completo aprobó 1.109
aserciones. La sonda destructiva
`supabase/scripts/test-reporte-derivaciones-concurrencia.mjs` debe correr al
final del gate de esa branch: fuerza que una gestión empiece antes, la
derivación confirme en medio y comprueba que la hora sellada quede después del
episodio y que la devolución siga bloqueada. La sonda ya pasó en PostgreSQL 17
local y en la rama hospedada (`REPORTE_DERIVACIONES_CONCURRENCIA_OK`).

Producción quedó con 116 migraciones, las tres RPC, las dos guardas privadas,
los tres triggers activos y los dos índices válidos. ACL, `security definer` y
`search_path = ''` se comprobaron directamente; una lectura autenticada con un
supervisor real devolvió el contrato versionado del reporte. La huella conjunta
de funciones `crm/private` coincide con la rama aprobada:
`b6f92b7ec502a5b4e13a977546f32e95`. Los advisors no añadieron errores ni
avisos de rendimiento; los tres avisos de seguridad nuevos corresponden
exactamente a las RPC autenticadas y gateadas. La rama temporal se eliminó al
terminar para detener el coste.

El frontend inicial se publicó con el reporte dentro de **Gestión de equipo** y
fue reemplazado el mismo día por el módulo independiente `#/derivaciones`. El
release vigente en `https://crm.miavance.com` es
`crm-20260820T215921Z-9be13cf1e74a.zip`, SHA-256
`f2293550b79cd5fbcc6bc7628e5f21a5477bd38caa1df5282e7772d5192eb575`.
El artefacto aislado excluyó Rescate, cambios de PDF y régimen documental; pasó
lint, typecheck, build, verificación de bundle y 2.110 pruebas. Después de la
limpieza de caché, `index.html`, JS/CSS principal, `derivaciones-Ck9wUbJf.js`,
`equipo-DtzNCieX.js` y `version.json` respondieron HTTP 200 y coincidieron byte
a byte con el manifiesto.

El primer artefacto del módulo independiente se compiló por error sin
`VITE_SUPABASE_URL` ni `VITE_SUPABASE_ANON_KEY`: el worktree aislado no tenía
el `.env` ignorado por Git. Esto dejó `HAY_SUPABASE=false`, deshabilitó el botón
de ingreso y mostró «El acceso con cuenta aún no está disponible aquí» a todos
los roles; no fue una falla de cuentas ni de Supabase. Se reconstruyó el mismo
alcance inyectando la configuración pública de producción, se comprobó que el
bundle contiene exactamente la URL y la clave pública esperadas, se desplegó
el artefacto corregido y se purgó la caché. El smoke final en producción
confirmó que el botón **Entrar** está habilitado, que el aviso ya no aparece y
que los archivos servidos coinciden con el release corregido.

El release también incorpora detección de versión para sesiones abiertas:
`version.json` y `index.html` se sirven con `no-store`; el navegador comprueba
al abrir, cada 60 segundos, al recuperar foco y al volver la conexión. Si hay
un despliegue posterior o un chunk antiguo, muestra **Ya guardé, actualizar** y
conserva la ruta actual. No recarga solo porque podría borrar formularios o un
borrador de reparto. Las pestañas abiertas antes de este primer release del
detector necesitan una última recarga; desde esta versión, los despliegues
siguientes se anunciarán dentro del CRM.

## Commits de implementación

- `11cec51` — backend, migración y oráculos del reparto seguro.
- `e802f48` — corrección aislada del arnés RLS para el límite autoritativo de recordatorios.
- `ae4960b` — módulo independiente **Derivar leads**, navegación y pruebas.
- `a23a237` — detección de una versión publicada y control de caché.
