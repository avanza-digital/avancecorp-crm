# Avisos de solicitudes de tasa en la PWA del CRM

**Estado: PUBLICADO Y ACTIVADO el 11/09/2026.**
Proyecto: `dctqcbznekcyxhjujuci`. Frontend: `https://crm.miavance.com`.
Trabajo aislado del frente F7 en `/private/tmp/avancecorp-tasa-lead-real-20260908`.
Migración, Edge, frontend y cron productivos verificados. El banco temporal fue
eliminado. Falta que Miguel active el permiso y reciba una prueba en su teléfono.
Acta y evidencia: [PUBLICACION-2026-09-11.md](PUBLICACION-2026-09-11.md).

## Resultado para Gerencia

En **Hoy → Solicitudes de tasa** y **Configuración** aparece «Avisos en tu teléfono».
Cada dispositivo se activa expresamente con el permiso del navegador. Puede enviar
una prueba y desactivarse. Las solicitudes nuevas, desde lead o cliente, generan
un aviso por dispositivo elegible, salvo los del propio solicitante.
El aviso abre la solicitud concreta y conserva el destino durante el login.
Si ya fue atendida, explica que dejó de estar pendiente.

El texto de la pantalla bloqueada no incluye nombre, DNI, monto ni tasa. El
servidor comprueba Gerencia vigente, perfil activo, sesión Auth existente, revisión
de las claves y solicitud pendiente antes de entregar. Un cierre de sesión afecta
solo ese dispositivo. Los demás teléfonos de Gerencia siguen recibiendo.

## SQL exacto autorizado

Miguel aprobó ambos archivos con «siii» el 11/09/2026 y confirmó la organización
`AVANCECORP- CRM-PORTAL`. Las huellas aprobadas son las de `evidencia/SHA256SUMS`;
los archivos SQL no se modificaron después. Supabase cotizó el banco temporal
en US$0,01344/hora; Miguel respondió «sii hazlo». Se creó el banco exclusivo
`push-tasa-20260911` (`pdummdtfablfkdgrmauo`), que se eliminará al terminar.

- [Migración](../../migrations/20260910225540_crm_notificaciones_push_tasa.sql): dos
  tablas CRM cerradas con RLS/auditoría, ocho RPC con permisos explícitos, helpers
  privados y cron. No modifica tablas, triggers ni policies de `public`.
- [Activación productiva](activar-produccion.sql): agrega únicamente el destino
  de este CRM en Vault. Debe ejecutarse al final, en el proyecto productivo.

La migración queda sin envíos mientras no exista `crm_push_proyecto` válido en
Vault. No copia ni rota las claves VAPID del portal. Los nombres
`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` y `VAPID_SUBJECT` ya existen en producción,
comprobado mediante el listado de nombres/digests, sin leer sus valores.
`CRM_PUSH_PERMITIR_LOCAL` debe permanecer ausente o en `false` en producción.

## Entrega y fallos

- El alta de una solicitud encola sus avisos en la misma transacción. Si el
  auxiliar falla, preserva la solicitud; el cron recupera los avisos faltantes.
  No recupera solicitudes anteriores al opt-in actual de un teléfono.
- Cada minuto, el cron despierta al worker cuando hay trabajo. Procesa diez
  envíos por ejecución, en grupos de tres. La demora normal es aproximadamente
  un minuto más red/proveedor; puede aumentar con cola o fallos de conectividad.
- Reservas de dos minutos, `SKIP LOCKED`, hasta ocho intentos y espera creciente
  de 1–30 minutos. Un 404/410 desactiva la suscripción. El TTL no supera un día ni
  el vencimiento de la solicitud.
- El servidor ofrece entrega con reintentos; HTTP no garantiza exactamente una
  vez. Topic/tag estables reemplazan el aviso existente. El worker recuerda hasta
  cien UUID opacos y pide silencio para reintentos; uno previamente descartado
  podría reaparecer sin sonido, según el sistema operativo.
- Safari exige una notificación visible por cada push recibido. Después de salir,
  un mensaje que ya estaba en tránsito solo muestra un aviso silencioso de baja
  y vuelve a retirar la suscripción; no anuncia actividad nueva del CRM.
- La baja intenta independientemente el interruptor local, la retirada de la
  suscripción y el servidor. Conserva solo IDs pendientes y reintenta al iniciar
  sesión con su propietario. No guarda claves push en localStorage.
- El worker no intercepta `fetch` ni almacena fichas. CacheStorage contiene un
  interruptor y los UUID recientes, sin datos comerciales.

## Firma del cron y seguridad

La cola de `pg_net` es legible por roles de API a nivel SQL en el proyecto, aunque
`net` no está expuesto en PostgREST. Además, `postgres` no tiene grant option sobre
esa tabla, propiedad de `supabase_admin`. Se descartó una revocación que pudiera
no surtir efecto y se eliminó el secreto compartido de las cabeceras.

El cron firma `crm-push-tasa:<proyecto>:<segundos Unix>` con HMAC-SHA256 usando el
secreto de Vault. La Edge valida la firma con una RPC exclusiva de `service_role`,
vigente por 120 segundos y con 30 segundos de tolerancia futura. La firma no
autoriza otros servicios ni proyectos. Quien ya pudiera leer SQL en la cola solo
obtendría una firma temporal que puede adelantar el procesamiento de avisos ya
autorizados durante esa ventana; no permite elegir destinatarios ni obtener
endpoints, claves o datos del negocio. Las reservas impiden reclamar el mismo
envío simultáneamente. La clave compartida nunca sale de Vault.

Las URLs se limitan a los proveedores admitidos (FCM, subdominios de
`push.apple.com`, Mozilla y Windows). HTTP no sigue redirecciones y tiene un
timeout de ocho segundos. La Edge acepta cuerpos de hasta 4 KiB. Los logs y la
auditoría no incluyen claves ni endpoints completos.

## Verificación

Evidencia final en [VERIFICACION.md](VERIFICACION.md) y evaluación de las dos
revisiones independientes en [REVISION-CLAUDE.md](REVISION-CLAUDE.md).

Desde `CRM-Avance-Corp`:

```bash
npm run test:push-tasa
npm run test:edge-preflight
npm --prefix app run check:all
```

El banco SQL exige una **copia local** `crm_push_tasa_*` del fixture F3/tasa lead,
con Auth, Vault y pg_net reales. Cron se sustituye por un registro inerte. Ejemplo
del banco utilizado (cada prueba SQL revierte todos sus cambios):

```bash
docker cp supabase/scripts/push-tasa/test-push-tasa.sql supabase_db_avancecorp-f4-bank:/tmp/crm-push-test.sql
docker exec supabase_db_avancecorp-f4-bank psql -X -U supabase_admin -d crm_push_tasa_release_20260910 -v ON_ERROR_STOP=1 -f /tmp/crm-push-test.sql
```

`concurrencia.mjs` requiere otra copia vacía ya migrada: crea fixtures sintéticos
y los conserva para inspección. No borra ni prepara una base productiva.

```bash
node supabase/scripts/push-tasa/concurrencia.mjs crm_push_tasa_concurrencia_final_20260910
```

## Publicación

1. Los dos SQL exactos y la organización ya están autorizados. Banco
   Supabase exclusivo creado con coste autorizado; el banco de F7 se conserva.
2. Banco completado: 48 SQL, tres carreras, 19 comprobaciones HTTP/Auth y cron
   real PASS. Matriz global: 50 fallos antes y 46 después, sin aserciones nuevas
   fallidas; el detalle conserva la deuda y la variación del fixture de referidos.
   Advisors y tipos verificados. [Ensayo remoto](BANCO-REMOTO-2026-09-11.md).
   Se retiran los secretos de prueba antes del merge.
3. Integrar `avancecorp/main` sin sobrescribir otros cambios; verificar que main
   local y remoto coinciden. Publicar solo un artefacto del commit verificado.
4. Merge autorizado de la migración y despliegue de `crm-notificaciones-tasa`,
   conservando los tres valores VAPID existentes. Publicar el CRM con manifest,
   iconos y `sw-crm.js`, cuyo encabezado de caché debe ser `no-store`.
5. Ejecutar `activar-produccion.sql` en `dctqcbznekcyxhjujuci`. Verificar el estado
   desde una cuenta Gerencia real. El usuario debe conceder permiso desde su PWA
   y usar «Enviar prueba»; una prueba real en su teléfono aún está pendiente.

Reversión operativa sin borrar datos: deshabilitar el cron
`crm-notificaciones-tasa`, poner `activo=false` en los dispositivos de esta
función y cancelar sus envíos pendientes. No eliminar solicitudes de tasa ni
modificar cálculos, contratos, perfiles o claves del portal. Conservar la
auditoría; cualquier política de purga requiere una decisión posterior.

Referencias verificadas: [Web Push de Apple](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers),
[WebKit y userVisibleOnly](https://webkit.org/blog/12945/meet-web-push/),
[sesiones de Supabase](https://supabase.com/docs/guides/auth/sessions),
[alcance de signOut](https://supabase.com/docs/guides/auth/signout).
