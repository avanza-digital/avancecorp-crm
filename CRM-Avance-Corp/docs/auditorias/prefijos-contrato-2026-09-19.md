# Auditoría de los prefijos de contrato — 19 de septiembre de 2026

El CRM y los dos formularios del portal están publicados para
`2024-01-`, `2025-01-` y `2026-01-`, con seis dígitos manuales y conservación
de ceros iniciales. `2026-01-` continúa como valor inicial del alta. El año de
la numeración no determina fechas, rentabilidad ni período comercial.

Estado: **publicado y verificado el 19/09/2026**.
Miguel autorizó la publicación con `$release-crm` y aprobó el PR #31.
El portal se actualizó primero y el CRM después, desde Main limpio
`4bd3dc1b5d1a71f60ec1abd6192f2dc92a4a1d3e`, alineado con `avancecorp/main`.
[Acta, manifiestos y verificaciones](../publicaciones/prefijos-contrato-2026-09-19/README.md).
No se modificaron contratos reales ni funciones, permisos o esquema de producción.
El SQL añadido al repositorio es un ensayo local con una guarda de base de datos
y `ROLLBACK`; no es una migración para instalar.

**Hallazgo corregido.** Los editores antiguos de `public_html/js/admin/analista.js`
y `public_html/js/admin/contratos.js` solo reconocían `2026-01-`. Al abrir un
contrato de 2024/2025, vaciaban los dígitos; volver a escribirlos reconstruía
el número con 2026 y podía emitir otra revisión PDF con ese número equivocado.
Se corrigieron lectura, edición, alta, búsqueda de duplicados y guardado.
El nuevo núcleo `numero-contrato-core.js` comparte esa regla entre ambos editores.
Las respuestas tardías de duplicados se descartan si cambió el prefijo o el
contrato editado. Los formularios restauran 2026 al iniciar otra alta.

La prueba del fallo se ejecutó sobre el código original: **4 fallos en los
casos de edición de 2024/2025 y 2 éxitos para 2026**. La implementación corregida
pasa los 16 casos de regresión, incluidos cambios de serie, formato inválido,
reinicio de formulario y respuestas asíncronas antiguas.

**Recorridos comprobados**

| Recorrido | Evidencia y resultado |
| --- | --- |
| Alta y corrección del CRM | Selector compartido; prefijo conservado en payload, borrador y revisión. Pruebas de componentes y Playwright. |
| Formularios antiguos del portal | Handlers reales ejecutados con DOM/red simulados; además HTML real en Chromium a 390 y 1280 px. |
| Transporte CRM | `prepararPayloadContrato` conserva el texto completo; los esquemas no fijan un año. |
| Alta con cuenta y PDF | `crm.crear_contrato_con_cuenta_pdf_v2` → `crm.crear_contrato_con_cuenta` → `public.crear_contrato`. Tres altas reales en banco sintético. |
| Unicidad | La restricción UNIQUE usa el número completo. Los mismos seis dígitos pueden existir en tres series; repetir el número completo se rechaza. |
| Concurrencia | Dos procesos SQL con el mismo número: uno confirma, el otro es rechazado; queda un solo contrato. |
| Idempotencia | Misma clave y mismos datos devuelve el mismo contrato. Cambiar el prefijo con la misma clave ya utilizada devuelve P0409. |
| Corrección del analista | `crm.actualizar_contrato_con_cuenta_pdf_v3` conserva 2024 y reserva la revisión PDF 2. Un analista ajeno y un contrato ficticio de más de cinco horas son rechazados. |
| Corrección de gestor | `crm.actualizar_numero_contrato_pdf_v3` cambia la serie y conserva cronograma, cuenta y vínculos de inversión. Actualiza snapshot y nombre del archivo PDF; rechaza duplicados. |
| Nueva inversión | Preparar en 2025, corregir a 2024, rechazar revisión desactualizada, confirmar y reintentar produce el mismo contrato/inversión. |
| Recuperación de duplicado | Confirmar una solicitud con número ocupado falla; corregir esa misma solicitud permite confirmarla con otro número. |
| PDF | Snapshot y nombre de archivo SQL conservan el número; renderer v9 imprime el número completo en la cabecera y genera PDFs reales con las tres series. |
| Renovación, upgrade y pagos | Inspección de funciones vigentes: los enlaces usan UUID; no dependen del año escrito en el número. No se cambió su lógica financiera. |
| Búsquedas y reportes | Barrido de literales y catálogo SQL: sin otra restricción operativa a 2026 en los recorridos inspeccionados. La vista `crm.contratos_cartera` devuelve el texto completo. |

**Verificación**

| Comprobación | Estado |
| --- | --- |
| CRM `npm run check`: lint, tipos, cobertura, build, bundle y demás verificaciones incluidas | PASS: 3.773 tests, 254 archivos; código app idéntico al publicado |
| Componentes de alta/corrección | PASS: 55 tests |
| Playwright de alta CRM con transporte simulado | PASS: 10 recorridos de contratos y 2 de historial |
| Portal `node --test tests/*.test.mjs` | PASS: 104 tests |
| Sintaxis de los módulos del portal y service worker; diff sin errores de espacios | PASS |
| Formularios HTML reales, Chromium, móvil/escritorio | PASS: 4 combinaciones |
| Suite completa del portal con login y servicios remotos | NOT RUN: se ensayaron los handlers y formularios modificados con red externa bloqueada; no se hizo una sesión completa contra producción. |
| Handler y renderer PDF, `deno test --allow-read` | PASS: 48 tests |
| Formato del test del renderer, `deno fmt --check` | PASS |
| Matriz SQL local `supabase/scripts/test-prefijos-contrato-local.sql` | PASS: 14 comprobaciones de recorrido, con ROLLBACK |
| Concurrencia SQL local | PASS: un alta confirmada y un duplicado rechazado |
| Huellas de las funciones restauradas | PASS: 32/32 iguales a las definiciones leídas de producción |
| Núcleo existente de autorización de alta de clientes | PASS: 10 tests |
| Script general `gate:realidad` | NOT RUN: no hay `SUPABASE_URL` configurada para ese comando; no llegó a medir. El catálogo productivo se inspeccionó con el conector en modo lectura. |
| Publicación, caché y archivos servidos | PASS: portal primero y CRM después; caché purgada; 65 archivos CRM y 6 portal comprobados por HTTP 200 y SHA-256 |
| Acceso público en Chromium después de publicar | PASS: CRM y los dos accesos del portal; formularios disponibles, sin errores de página ni recursos fallidos |
| Crear o corregir un contrato real después de publicar | NOT RUN: el smoke productivo usó sesiones vacías y no modificó registros reales |

La suite general del portal detectó una prueba anterior desactualizada:
`asiento-operaciones.test.mjs` buscaba el array de roles dentro de `index.ts`,
aunque la decisión ya vive en `autorizacion.mjs`. Se actualizó para ejecutar el
resolver real y comprobar tanto la autorización de Operaciones como su rechazo
tras revocación. No se cambió la lógica de permisos del producto. Los pines del
test documental también se sincronizaron con las versiones de esta corrección.

**Alcance del ensayo SQL.** Se clonó un banco sintético local en
`prefijos_auditoria_20260919_v2`, conservando dueños y permisos. Se excluyeron cron
y eventos de infraestructura de la restauración. Para ensayar el recorrido actual,
se reprodujeron 32 definiciones obtenidas mediante lecturas de producción,
la columna de origen de solicitud y las restricciones de versión documental v9.
Las llamadas se ejecutaron como `authenticated` con identidades ficticias.
El resto del esquema y sus datos son del banco local: esto no equivale a un
ensayo completo sobre una réplica exacta de producción ni a probar el despliegue.
La prueba de cinco horas usa un contrato sintético antiguo, sin desactivar
triggers ni alterar la protección de `creado_en`.

**Revisión independiente con Claude.** Se usó `scripts/claude-review` como
SECONDARY_REVIEWER, con herramientas deshabilitadas y evidencia adjunta.
Su auditoría ampliada devolvió `CHANGES_REQUESTED`. El PRIMARY contrastó sus
observaciones y resolvió el defecto del portal, la guarda de duplicados y los
huecos de persistencia, PDF, búsquedas y concurrencia con las pruebas anteriores.
No se pidió otra revisión para conseguir un dictamen favorable.

Dos recomendaciones requieren este matiz:

- No se regeneró automáticamente la clave de idempotencia al cambiar el
  prefijo tras un error de red. El diseño existente la conserva para impedir
  una segunda alta cuando el servidor guardó pero la respuesta se perdió.
  La prueba SQL confirma que otra serie con esa misma clave es rechazada.
- La posibilidad de que algún documento antiguo ya se hubiera registrado con
  un prefijo incorrecto no se puede resolver mirando solo el número en la base.
  La consulta agregada encontró 620 contratos con formato 2026 y ninguno con
  formato 2024/2025; cero grupos del mismo cliente y seis dígitos en series
  distintas. Esto no acredita la numeración de los documentos físicos.
  No se renumeró ni se deduplicó ningún registro histórico.

**Publicación completada.** El portal se actualizó antes que
el CRM. Versiones publicadas: `analista.js?v=29`, `contratos.js?v=44`,
`numero-contrato-core.js?v=1` y service worker `avance-v119`.
Se subieron primero los módulos y el núcleo, después sus HTML y el service worker
al final; se purgó la CDN. Las nuevas URLs versionadas se comprobaron después
de subir sus archivos.

El portal tiene recarga al cambiar su service worker. El CRM muestra el aviso de
nueva versión y permite al usuario guardar antes de recargar; su service worker
de notificaciones no almacena el frontend. Una pestaña antigua del CRM conserva
el editor anterior hasta que se recargue. Completar esa actualización
antes de registrar o corregir números de 2024/2025. No se añadió una recarga
forzada que pudiera perder formularios abiertos.

Evidencia local de esta ejecución: `/private/tmp/avancecorp-prefijos-auditoria/`
contiene el dictamen de Claude, logs SQL, huellas, pruebas del portal/PDF y
capturas. Las verificaciones de publicación y los manifiestos también están
versionados en `docs/publicaciones/prefijos-contrato-2026-09-19/`.
Los ZIP y respaldos se conservan en `releases/prefijos-contrato-20260919/`,
carpeta excluida de Git por las reglas del repositorio.
Los logs del gate CRM y sus E2E están en
`/private/tmp/avancecorp-prefijos-check.log` y
`/private/tmp/avancecorp-prefijos-e2e.log`. Los dumps del banco son auxiliares
privados de prueba y no forman parte de la entrega.
