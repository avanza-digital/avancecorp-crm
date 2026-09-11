# Evaluación de las revisiones independientes

Codex actuó como PRIMARY y único escritor. Claude fue SECONDARY_REVIEWER mediante
`scripts/claude-review`, sin herramientas ni acceso de escritura. Riesgo LEVEL 3.
Se obtuvieron dos dictámenes válidos `CHANGES_REQUESTED`; no se presenta a Claude
como una aprobación final. Codex resolvió los hallazgos con la evidencia siguiente.
Una primera ejecución anterior no devolvió un dictamen válido y no se contó como
revisión ni como PASS. No se modificaron los wrappers o ajustes del reviewer.

## Primera revisión

| Observación | Decisión del PRIMARY y evidencia |
| --- | --- |
| El trigger auxiliar puede abortar la solicitud de tasa | Corregido: protección de excepciones recuperables y reconciliación del cron. Inyección de fallo real confirma que la solicitud sobrevive y el aviso se recupera. La cancelación de una consulta permanece como cancelación. |
| Una confirmación fallida abandona todo el lote | Corregido: aislamiento por envío; prueba de siete elementos confirma que se procesan todos y se devuelve `sinConfirmar` con HTTP 503. |
| Cierre de sesión deja avisos activos | Parcialmente aceptado: `signOut(scope:'local')` sí revoca la sesión actual del servidor según documentación Supabase, al contrario de la premisa del review. Aun así, el fallo de red necesitaba refuerzo: interruptor local, retirada del proveedor, RPC independiente, IDs de baja persistentes y reintento por cuenta. |
| La clave cron aparece en la cola de pg_net | Confirmado el permiso SQL mediante lectura de metadatos. La solución final usa una firma HMAC temporal acotada a esta función y proyecto; la clave compartida nunca sale de Vault. Ocho pruebas SQL del contrato cron/firma pasan. |
| Regiones accesibles montadas con contenido | Corregido: status/alert persistentes; prueba de identidad del nodo antes y después de un error. |
| Otro worker cancela una reserva en curso | Corregido: limpieza limitada con `SKIP LOCKED`, excluye reservas vivas; la elegibilidad se vuelve a comprobar al materializar. |
| Historial de dispositivos sin límite | Límite de cien dispositivos históricos y diez activos con sesión viva por cuenta. No se añadió borrado de auditoría. |

Además, Codex detectó y corrigió el orden de bloqueo entre baja del dispositivo y
confirmación 410. Dos transacciones reales verifican que no hay deadlock.

## Segunda revisión

| Observación | Decisión del PRIMARY y evidencia |
| --- | --- |
| Barrido de ocho intentos sin SKIP LOCKED puede bloquear otro worker | Corregido: barrido ordenado y limitado a cien filas con `SKIP LOCKED`. Tercera prueba concurrente comprueba filas simultáneamente inválidas y agotadas. |
| Descartar un push viola userVisibleOnly en Safari | Confirmado con documentación Apple/WebKit. El worker siempre muestra un aviso: los repetidos reemplazan el mismo tag con `silent:true`; tras salir, un mensaje ya en tránsito solo muestra la baja y retira la suscripción. Cache roto/JSON corrupto tienen pruebas específicas. |
| Las bajas pendientes solo se reintentan al consultar el panel | Corregido: `vincularCuentaPushTasa` también las reintenta al entrar. El ensayo no visita Configuración. Se conserva el propietario y se corta el recorrido si cambia de cuenta. |
| REVOKE de net podría no surtir efecto por falta de grant option | Confirmado: en producción la tabla pertenece a `supabase_admin` y `postgres` no puede revocar SELECT. Se eliminó ese DDL; la firma temporal resuelve la exposición de la clave sin cambiar permisos del servicio compartido. Esta decisión posterior fue del PRIMARY, respaldada por las pruebas de firma y permisos. |
| El clic puede navegar una pestaña con un formulario abierto | Corregido: reutiliza solo una ventana que ya está en el destino exacto; en otro caso abre la solicitud sin navegar el formulario. Prueba dedicada. |
| Estado visual inconsistente después de una baja parcial | Corregido: devuelve estado pendiente, retira la activación visible y comunica que confirmará la baja al entrar. Los IDs de reintento se conservan aparte. |
| Falta purga de envíos históricos | No se añadió una purga automática: las reglas del proyecto conservan auditoría y no autorizan borrar filas CRM para esta funcionalidad. La retención se documenta como decisión posterior; no bloquea la entrega. |

Se verificaron las dos dependencias señaladas como evidencia faltante:
`private.log_audit_sin_secretos()` enmascara los campos mediante
`private.enmascarar_claves`, comprobado además con auditoría real en el banco.
`public.verificar_cron_secret(text)` existe y es exclusivo de `service_role`, pero
**la implementación final ya no lo usa**: emplea su verificador HMAC propio.

El último E2E encontró un defecto fuera de esos snapshots: el splash mantenía la
tarjeta inerte durante el intento inicial de foco. Se corrigió usando
`useSplashVisible`. El test unitario y el login completo por enlace pasan.

## Límites restantes

No hubo prueba de entrega APNs/FCM en el teléfono del usuario. Tampoco se ejecutó
el cron gestionado ni el banco remoto/advisors: requieren el SQL autorizado.
Una firma temporal que un actor ya capaz de leer SQL obtenga de pg_net puede
reutilizarse hasta dos minutos para adelantar el procesamiento de la cola; no
autoriza seleccionar destinatarios, ver claves ni ejecutar otros servicios.
Un aviso previamente descartado podría reaparecer silenciosamente tras un
reintento: Web Push no ofrece exactamente una vez y Safari exige visibilidad.

Los dictámenes originales se conservan en `evidencia/claude-inicial.txt` y
`evidencia/claude-segunda.txt`. Las cifras y el estado final de los checks están
en [VERIFICACION.md](VERIFICACION.md).
