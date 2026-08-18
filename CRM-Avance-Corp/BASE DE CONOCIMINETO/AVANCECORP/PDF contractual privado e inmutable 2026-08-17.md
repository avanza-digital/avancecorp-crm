# PDF contractual privado e inmutable — 2026-08-17

## Estado

- Implementación v2 desplegada en producción desde la Preview validada
  `contrato-pdf-v2-release-20260817`. La rama se eliminó después del postflight
  para detener su coste.
- El navegador dejó de ser autoridad sobre el documento legal: en el flujo real
  solo envía JSON con `action` y el UUID canónico del contrato. Snapshot,
  plantilla, nombre, ruta, hash y bytes se resuelven en servidor.
- La v1 insegura y su configuración desplegable fueron retiradas. La versión
  productiva es la migración `20260818014534` y la Edge Function
  `crm-contrato-pdf-v2`.
- Relacionado con [[Continuidad CRM 2026-08-06]] y
  [[Configuración operativa CRM 2026-08-07]].

## Domicilio legal

- Alta, edición y conversión comparten una validación: texto con bordes
  normalizados, de 5 a 240 puntos Unicode y sin controles C0/C1.
- La conversión usa una única RPC transaccional,
  `crm.convertir_lead_con_domicilio`. Primero autoriza y convierte; solo después
  completa el domicilio si el perfil deduplicado aún lo tiene en `NULL`.
- El resultado distingue `domicilio_accion = completado | conservado`. Un fallo
  de autorización o conversión revierte también el domicilio, cerrando el IDOR
  que existía cuando la Edge escribía el perfil con `service_role` antes de la
  RPC.
- Los perfiles legacy pueden conservar `NULL` por compatibilidad, pero el alta
  CRM v2 y el snapshot contractual fallan cerrados hasta contar con domicilio.

## Alta y reserva durable

- `crm.crear_contrato_con_cuenta_pdf_v2` crea contrato, cronograma, cuenta,
  vínculo, snapshot y job documental en una sola transacción.
- La fila de `public.contratos` funciona como mutex. La reserva es idempotente y
  la ruta se deriva únicamente de UUID tipados:
  `<contrato_id>/v2/<job_id>/contrato.pdf`.
- Estados durables: `pendiente`, `procesando`, `subido_verificado`, `sellado`,
  `error_reintentable` e `integridad_bloqueada`. Los leases vencidos pueden ser
  retomados; un worker concurrente no adquiere el mismo lease. `solicitado_por`
  conserva la procedencia inicial, pero cualquier actor que siga autorizado
  sobre el contrato puede recuperar el job si el creador fue revocado o quedó
  indisponible. Cada frontera del worker vuelve a comprobar esa autorización;
  un worker tardío tampoco puede marcar error después de vencer su lease.
- Desde la reserva se congelan número, cliente, capital, moneda, tasa, modalidad,
  tipo de interés, fechas, categoría, condición de producto, cronograma
  estructural y cotitulares. Los campos operativos de cobranza siguen editables.
  El trigger SQL es la autoridad incluso frente a RPC administrativas.

## Edge Function y generación legal

- `crm-contrato-pdf-v2` acepta únicamente JSON pequeño y exacto. Rechaza
  multipart, bytes del cliente, claves extra, UUID con mayúsculas y cuerpos sin
  límite efectivo.
- Auth identifica al usuario real y las RPC vuelven a aplicar la autorización de
  cartera. El snapshot se obtiene de SQL después de adquirir el job; nunca se
  acepta uno aportado por el navegador.
- La Edge renderiza con PdfPrinter, Roboto VFS, fondo y firma versionados dentro
  del componente server-side. Fechas de metadata y versión de plantilla quedan
  fijadas por el job, por lo que dos renders del mismo snapshot son idénticos
  byte a byte.
- Flujo: claim/lease → render server-side → subida con `upsert: false` → nueva
  descarga desde Storage → validación de cabecera, SHA-256 y tamaño → marca de
  subida → sello SQL. Un conflicto solo se recupera si el objeto existente es
  idéntico; cualquier divergencia deja un bloqueo de integridad durable.
- La respuesta pública expone solo el estado documental común. Snapshot y token
  de lease nunca salen; la URL firmada se emite únicamente para `sellado` y
  después de verificar nuevamente el objeto.

## Storage privado e integridad

- El bucket `contratos-generados` es privado, limitado a PDF y 10 MiB. Los roles
  del navegador no leen ni escriben objetos o ledger directamente.
- `private.contrato_pdfs` y `private.contrato_pdf_jobs` tienen RLS forzada y
  mutación encapsulada en RPC `SECURITY DEFINER` con `search_path = ''`.
- No se instala un trigger sobre la tabla administrada `storage.objects`. La
  aplicación garantiza primer escritor, ledger insert-only y verificación de
  SHA-256/tamaño en cada entrega. Un poseedor externo de `service_role` o un
  administrador de base aún podría alterar físicamente Storage; v2 detecta la
  divergencia y bloquea la descarga, pero no pretende ser WORM frente a ese
  actor privilegiado.

## Frontend, Mi cartera y demo

- El flujo real ya no importa el generador del navegador. El alta muestra el
  estado durable y “Mi cartera” permite consultar, reintentar y descargar desde
  la Edge sin regenerar bytes localmente.
- Cerrar por Finalizar, Escape u overlay después del commit invalida la cartera
  una sola vez; durante alta, archivo o reintento el cierre queda bloqueado. Una
  respuesta tardía de otro contrato no puede reemplazar el estado visible.
- Demo conserva un renderer separado, sin firma real, con caché por sesión,
  coalescencia de solicitudes concurrentes y epoch de limpieza para que un
  logout no permita repoblar datos de la sesión anterior. Cada creación recibe
  un ID único y los números duplicados se rechazan antes de tocar la caché.
- La firma corporativa salió de `app/public` y no aparece en el bundle
  productivo. El verificador de bundle falla ante pdfmake/VFS, fixtures demo o
  cualquier variante de la ruta/contenido `firma-kirk`.

## Evidencia local reproducible

- Oráculo SQL efímero: `CONTRATO_PDF_V2_SQL_OK` y
  `CONTRATO_PDF_V2_RUNNER_OK`; comprobó ACL/RLS, atomicidad/rollback, freeze,
  carrera de dos sesiones, relevo entre actores autorizados, revocación durante
  el lease, rechazo de workers tardíos, retry, integridad, idempotencia y
  domicilio. La base de prueba fue eliminada al terminar.
- Edge: 17 pruebas, lint, formato, typecheck y carga real en Supabase Edge
  Runtime local. El ESZIP mide 10.065.108 bytes, dentro del límite de 20 MiB del
  CLI usado.
- Golden determinista del contrato `2026-01-000777`: 867.322 bytes y SHA-256
  `d605f4de85fcff084df2fe549298e3eade63439dbfe350ff9790496b7aa9000a`.
- Tres descargas firmadas locales, guardadas como archivos físicos distintos,
  devolvieron HTTP 200 y fueron iguales por SHA-256, tamaño y `cmp`. La lectura
  anónima directa falló y el objeto temporal se eliminó después de la prueba.
- Auditoría visual: 7 páginas A4, fondo en todas las páginas, encabezado y pie,
  Roboto embebida, 17 cláusulas en orden, tabla sin filas partidas, cláusula 17 y
  ambas firmas juntas en la última página, sin placeholders, formularios,
  JavaScript ni cifrado. El PDF de auditoría quedó únicamente en
  `/private/tmp/contrato-pdf-v2-auditoria.iTRI91/`.
- App: suite completa, cobertura, lint, typecheck, build y verificación del
  bundle en verde. E2E local: 86 aprobadas, 42 omitidas por gates existentes y
  cero fallos; el origen Supabase del harness es loopback y no hosted.

## Evidencia Preview de Supabase

- La rama nació con el `MIGRATIONS_FAILED` histórico de ramas sin datos. Se
  reseteó al último punto sano, recibió la semilla mínima y reprodujo las 15
  migraciones siguientes desde el registro exacto de producción. La huella de
  206 funciones `crm/private` quedó idéntica a producción:
  `58148bbd58b3d6724113a4488f294d3b`.
- Supabase registró v2 como `20260818014534_crm_contrato_pdf_v2_reserva`.
  Todos los postflights de bucket, RLS forzada, ACL, `search_path` y ausencia
  de trigger en `storage.objects` dieron verdadero.
- Las tres Edges quedaron `ACTIVE` y con JWT verificado en Preview:
  `crear-cliente`, `crm-convertir-lead` y `crm-contrato-pdf-v2`.
- Un contrato ficticio se creó con reserva atómica y se selló en el runtime
  hosted. El PDF midió 867.519 bytes, SHA-256
  `6fb9de740c6a66c4cf08d7882ed79c3e8f04ae8d12d167fca3e6d83725db4980`;
  ensure, reintento y status devolvieron tres descargas iguales byte a byte.
  Storage directo autenticado y la ruta pública quedaron bloqueados. Los logs
  de Edge no mostraron errores ni límites de CPU/memoria.
- Advisors: cero `ERROR`; seguridad solo añadió la delta explicada de RPC
  authenticated y las dos tablas privadas deny-by-default. Rendimiento no
  añadió ningún `WARN` nuevo.

## Evidencia de producción

- Commit desplegado y publicado: `15774fd55748a8325143018a3d74dafdd09c19db`.
- Supabase quedó `ACTIVE_HEALTHY` con
  `20260818014534_crm_contrato_pdf_v2_reserva` como última migración.
  `crear-cliente` quedó en v28, `crm-convertir-lead` en v11 y
  `crm-contrato-pdf-v2` en v1; las tres están `ACTIVE`, requieren JWT y sus
  16/16 archivos coinciden por SHA-256 con el commit.
- El postflight confirmó bucket privado, RLS forzada, ACL y `search_path`
  correctos, seis triggers activos, RPC v1 revocada y cero huérfanos. Advisors:
  seguridad 18 INFO / 111 WARN / 0 ERROR; rendimiento 50 INFO / 5 WARN /
  0 ERROR. Los logs posteriores no muestran 5xx ni límites de worker.
- CORS responde para `https://crm.miavance.com`; los tres POST sin JWT fallan
  con 401 antes de ejecutar lógica. No se crearon perfiles, leads, contratos,
  jobs ni objetos durante el smoke.
- Frontend vivo: release `crm-20260818T020259Z-15774fd55748`, ZIP de
  1.105.705 bytes, SHA-256
  `9ce985041520c10f19ced653834cf8666302f9552ff472b72585eee129ecb512`.
  HTML/JS/CSS y 68/73 archivos públicos son byte-idénticos al manifest; HCDN
  reencodifica solo cinco PNG conservando tipo y dimensiones. Esto no toca el
  PDF legal porque sus imágenes están embebidas server-side. ZIP,
  `.vite/license.md` y `firma-kirk.png` responden bloqueado/404. El login carga
  sin errores de consola.
- Producción quedó con cero jobs, ledgers y objetos PDF. La igualdad de las tres
  descargas está demostrada en el runtime hosted de Preview; la repetición sobre
  producción ocurrirá con el primer contrato real, sin fabricar fixtures en la
  base viva.

## Alcance de la sesión

- Esta implementación no modificó `public_html`. Durante la verificación se
  detectó que otra sesión cambió su HEAD y dejó modificaciones propias en el
  submódulo; se preservaron sin abrirlas, revertirlas ni incorporarlas.
- El despliegue se hizo sin tocar `public_html`; sus cambios de otra sesión
  permanecen fuera del commit y sin intervención.
