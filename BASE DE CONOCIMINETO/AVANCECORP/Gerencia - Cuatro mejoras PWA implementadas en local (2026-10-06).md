# Cuatro mejoras de la PWA de Gerencia publicadas

Miguel pidió ejecutar las cuatro mejoras restantes del plan. Se implementaron primero en local y se publicaron el 6 de octubre de 2026 a las 09:25 Lima, después de integrar PR #202. La barra queda **Resumen · Citas · Gestión Diaria · Más**, y Metas continúa en Más.

1. **Pendientes de gestión en Resumen**: hasta tres avisos activos, críticas antes que atención, misma fuente que la campana, total y enlace a todos. La carga no anuncia cero; se explican vacío, error parcial y posible desactualización. No se inventa antigüedad ni responsable.
2. **Bandeja móvil**: tarjetas compactas, filtros plegables con indicador activo, búsqueda y consulta en memoria por cuenta/rol. Al regresar se recuperan scroll y foco; si desapareció el aviso, se enfoca la cabecera. Se mantiene el comportamiento previo de los cortes pospuestos para supervisor y escritorio.
3. **Pantallas prioritarias**: equipos de Gestión Diaria con ordenación compacta; Citas recuerda filtros/vista/página; Ranking y Metas compactan fuentes y valores; Facturación contiene su tabla y deja legibles los nombres; Cartera conserva visibles la consulta activa y el conteo. Los avisos de mes cerrado y ninguna fuente elegida permanecen visibles aun con Fuentes plegadas.
4. **PWA**: estado de desconexión, revalidación de proveedores existentes, actualización aplazable con recarga voluntaria, convivencia con Más y diálogos, tratamiento de teclado y viewport sin confundir zoom con teclado. No se añaden permisos, migraciones, dependencias ni otro sistema de push.

Se reutilizó la copia limpia existente `/tmp/avancecorp-navegacion-movil-20261005`, basada en PR 201 (`1d4134e6476f007ac14cbb38df42b84e22fe862f`). La integración preservó el trabajo ajeno de `ResumenGestionesHoy` y `CitasClientes`. Hay backups y hashes de los 37 archivos verificados en `CRM-Avance-Corp/output/pwa-gerencia-cuatro/integracion-final/`.

Verificación: lint, tipos, build, bundle y duplicación PASS. Suite unitaria completa: 6.129 PASS antes de los ajustes finales; después, 249 pruebas específicas PASS y 251 PASS al integrar en el workspace. Docker completo: 354 PASS, cinco con reintento, 26 omitidas y un fallo persistente de aviso de mes cerrado. Ese fallo se corrigió. Revalidación final: 15 PASS sin reintentos, incluidos el caso corregido y los cinco intermitentes; no se debe afirmar que hubo una nueva ejecución completa totalmente verde. El review secundario pidió cambios; Codex evaluó y verificó las correcciones, sin consultar repetidamente para obtener aprobación.

Pendientes para cierre: backend real NOT RUN por falta de `SUPABASE_URL`; PWA instalada, teclado y áreas seguras reales, segundo plano y recepción de push en iPhone/Android físicos NOT RUN por falta de dispositivos. La publicación se completó con autorización de Miguel; Main, artefacto y preflight quedaron verificados. La vista local usa datos demo: <http://127.0.0.1:5184/navegacion-movil.html>.

Acta y evidencia: `CRM-Avance-Corp/output/pwa-gerencia-cuatro/ENTREGA.md`, `verificacion.json`, `review-resolucion.md`, logs, capturas y `cambios.patch`. Plan actualizado: `CRM-Avance-Corp/docs/encargos/2026-10-05-pwa-gerencia-plan-restante.md`.

Relacionadas: [[Gerencia - Plan de cierre PWA y acceso a Gestion Diaria (2026-10-05)]], [[Gerencia - Navegacion inferior movil en vista previa (2026-10-05)]], [[Gerencia - Resumen compacto movil y citas por equipo (2026-10-05)]], [[Notificaciones de tasa - publicadas 2026-09-11]].

## Preparación de publicación — 6 de octubre, 08:54 Lima

Miguel autorizó el deploy. [PR #202](https://github.com/avanza-digital/avancecorp-crm/pull/202) preparado sobre Main publicado `cce54754`; candidato `742034031aaa52117e15a3cfdbb7649ae74055b7`. Check final PASS: 385 archivos, 6.187 pruebas. Docker completo: 358 PASS, 26 omitidas y dos fallos de un E2E obsoleto de eliminación tras PR #200; ese spec se actualizó al flujo vigente y sus dos casos pasaron en Docker, sin reintentos. Código de producto sin cambios por esa corrección. GitHub app-check, verify, preflight y cambios PASS.

**Estado histórico a las 08:54 Lima, resuelto después:** GitHub exigía revisión aprobada para integrar el PR (`REVIEW_REQUIRED`). Se pidió a Miguel aprobar/integrar #202. La autorización de deploy ya existe y no debe volver a pedirse. Tras integrarse: alinear Main sin perder WIP, construir desde ese commit limpio, verificar ZIP/preflight, publicar con el conector hosting habitual y comprobar HTTPS y sesión real. Respaldo vigente `crm-20261006T045841Z-cce54754f4f1.zip` conservado/verificado. Evidencia y reanudación: `CRM-Avance-Corp/output/pwa-gerencia-cuatro/deploy/estado.json` y `PREPARACION.md`.


## Publicación efectiva — 6 de octubre, 09:25 Lima

Publicado en <https://crm.miavance.com> desde Main limpio igual a `avancecorp/main`, commit `ea3b6ed22a9bc37031bd9c01ca54e694cffb3f11`, build `build-20261006T140145431Z`. PR #202 integrado a las 08:57 Lima. Se respetó la pausa solicitada antes del despliegue y se publicó después de «sigue», sin pedir de nuevo autorización.

Artefacto `crm-20261006T140146Z-ea3b6ed22a9b.zip`, SHA-256 `10995f86d0958020362e5dd012eee4b78d52bd1492d98aadd3ef70ba092adda6`. Hostinger, verificación de manifiesto y preflight PASS. HTTPS confirma el build exacto, 139 archivos con hash exacto, 13 imágenes disponibles, `.htaccess` protegido y ZIP público 404. Workspace original alineado conservando WIP; respaldos en la evidencia de integración.

Smoke Gerencia real PASS: Resumen, pendientes y coincidencia del contador con campana, búsqueda con retorno conservando filtro y foco, Citas, Gestión Diaria, Más con Metas y regreso a escritorio. Una consulta de TC incompleta mostró el aviso correcto y se recuperó mediante Reintentar; avisos GSAP de targets ausentes no bloquearon este recorrido. No se crearon ni modificaron operaciones reales para probar.

La evidencia final reemplaza los resultados preliminares para evaluar esta versión: check 6.187 PASS; Docker completo 358 PASS / 2 FAIL / 26 omitidas y repetición focal de los dos casos corregidos 2 PASS, sin cambios de producto ni reintentos. PWA física y gate automatizado de realidad conservan NOT RUN por los motivos ya registrados; no confundir smoke de lectura con esas validaciones.

Acta: `CRM-Avance-Corp/docs/publicaciones/gerencia-pwa-cuatro-mejoras-2026-10-06.md`. Estado y evidencias: `CRM-Avance-Corp/output/pwa-gerencia-cuatro/deploy/`. El ZIP previo `crm-20261006T045841Z-cce54754f4f1.zip` permanece disponible para el procedimiento de recuperación, sin rollback ejecutado. Relacionadas: [[Gerencia - Plan de cierre PWA y acceso a Gestion Diaria (2026-10-05)]] y [[Gerencia - Navegacion inferior movil en vista previa (2026-10-05)]].


## Aclaración y comprobación posterior — 6 de octubre, 09:40 Lima

El bloqueo registrado como falta de entorno era específico del comando `gate:realidad`: espera `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`, y ninguna estaba exportada. La aplicación sí dispone de su conexión mediante las variables `VITE_*`; eso no configura automáticamente este comando administrativo. Había una vía autorizada mediante el conector Supabase que debió revisarse antes de presentar la comprobación como bloqueada.

Se ejecutaron **las nueve mediciones equivalentes por SQL/MCP en una transacción READ ONLY**, sin cambios de negocio: **ocho supuestos sin divergencia y un aviso de calidad de datos**. Los cinco caminos que contrasta la alarma de conversión coincidieron en **2,76 %**. Se observaron **279 clientes activos con `public.perfiles.domicilio IS NULL`**; se registra el estado de ese campo, sin corregirlo ni atribuir su causa al despliegue.

El comando original continúa **NOT RUN** y su configuración automática sigue pendiente. La lectura SQL equivalente está completada; no acredita el transporte HTTP/PostgREST ni sustituye una prueba de permisos o una auditoría completa del backend. Evidencia: `output/pwa-gerencia-cuatro/deploy/realidad-mcp-20261006T1440.json` y `.sql`.

Relacionado: [[Gerencia - Plan de cierre PWA y acceso a Gestion Diaria (2026-10-05)]].


## Mejora posterior: saludo personalizado — preparada en local

Miguel pidió reemplazar «Lo importante, primero.» en el Resumen móvil por «Bienvenido, Carlos», tomando el nombre del usuario. Se implementó `Bienvenido, {primerNombre(yo.nombre_completo)}` usando la sesión que el componente ya recibe y el formateador compartido; para CARLOS VALLES se presenta Carlos. Si falta el nombre, se muestra «Bienvenido» sin coma. Se conserva la fecha y «Tu equipo, de un vistazo».

Estado: **implementado y verificado en local; todavía no publicado**. Alcance solo frontend. Lint, tipos y build PASS; 91 pruebas unitarias de las suites relacionadas y 3 E2E locales en Docker PASS, cero reintentos. El E2E comprueba también un nombre distinto (Gerente) y el retorno con foco al saludo en modo demo (Gerencia). No hizo falta otro review para este cambio pequeño de texto.

Evidencia: `CRM-Avance-Corp/output/saludo-gerencia-local/verificacion.json`, logs y patch. El archivo de producto actualizado es `app/src/screens/hoy/resumen-gerencia-movil.tsx`. La publicación vigente sigue siendo la de PR #202; este cambio requiere su propia publicación. Relacionado: [[Gerencia - Resumen compacto movil y citas por equipo (2026-10-05)]].


### Publicación del saludo pendiente de revisión de GitHub

Miguel autorizó publicar el saludo («publica pues»). Se creó [PR #203](https://github.com/avanza-digital/avancecorp-crm/pull/203), rama `codex/saludo-gerencia-20261006`, commit `f9a29bfa5d32834243c29aa61973fa73d8310f07`. Check integral local PASS (385 archivos, 6.187 pruebas); E2E local en Docker 3 PASS sin reintentos. GitHub exige una revisión aprobada; al cierre, preflight y cambios ya habían pasado y app-check seguía en curso. Miguel respondió **«Lo revisaré después»**. No se publicó el saludo ni se creó el ZIP definitivo desde Main.

La versión viva sigue siendo `build-20261006T140145431Z` de PR #202. No hay que pedir otra autorización de deploy: al retomar, comprobar aprobación/integración y controles del PR, alinear Main conservando WIP, construir y verificar artefacto/preflight, publicar y comprobar HTTPS/saludo. Evidencia y herramientas de reanudación: `CRM-Avance-Corp/output/saludo-gerencia-local/deploy/estado.json`.


## Saludo personalizado publicado — 6 de octubre, 10:30 Lima

**Estado vigente: publicado y verificado.** Miguel retomó con «ya esta el pr». PR #203 se integró a las 10:27 Lima y pasó todos sus controles. Main original, copia limpia y `avancecorp/main` quedaron alineados en `33694da631ac0b073c0b8887dbb62f953130c270`, preservando todo WIP ajeno. El árbol completo coincide con el candidato que obtuvo check 6.187 PASS y Docker 3 PASS; la fuente no cambió al integrar.

Publicado una sola vez en <https://crm.miavance.com> con build `build-20261006T152938176Z`. ZIP `crm-20261006T152939Z-33694da631ac.zip`, SHA-256 `10490092405e959fdbe4a5f879654b40f46e1ad0b333a01c237f376de2011be1`. Release, manifiesto, preflight y Hostinger PASS. HTTPS PASS para 153 archivos (139 exactos, 13 imágenes disponibles, 1 protegido), versión exacta y ZIP público 404.

La sesión real de Gerencia muestra **«Bienvenido, Carlos»** en el Resumen móvil. Captura y smoke PASS a 390 × 844; viewport restaurado. El nombre continúa siendo dinámico y se conserva «Bienvenido» cuando falta. Dispositivo físico NOT RUN; no hubo cambios de negocio durante el smoke. No quedan pasos pendientes de esta publicación.

Acta: `CRM-Avance-Corp/docs/publicaciones/saludo-gerencia-2026-10-06.md`. Evidencia: `CRM-Avance-Corp/output/saludo-gerencia-local/deploy/`. Respaldo vivo previo de PR #202 conservado. Relacionadas: [[Gerencia - Resumen compacto movil y citas por equipo (2026-10-05)]] y [[Gerencia - Navegacion inferior movil en vista previa (2026-10-05)]].


## Sesión cerrada y temporales retirados — 6 de octubre de 2026

Miguel pidió cerrar la sesión y borrar lo innecesario. Se retiraron cuatro copias temporales de `/tmp`, 54 auxiliares, cachés/copias de la antigua vista previa y dos maquetas HTML. El servidor local de 5184 quedó detenido. Antes se consolidó la evidencia faltante y se conservaron siete versiones únicas del respaldo previo de WIP; el workspace, las dependencias compartidas, las actas y los ZIP/manifiestos de publicación/recuperación permanecen disponibles.

Producción revalidada: `build-20261006T152938176Z`. No queda otro deploy ni implementación de estas mejoras. Las rutas temporales citadas antes son históricas y ya no deben usarse para retomar. Seguimiento registrado: prueba en teléfono físico, configuración de validación automática y la observación previa de 279 domicilios vacíos.

Cierre y detalle verificable: `CRM-Avance-Corp/output/cierre-sesion-gerencia-20261006/CIERRE.md` y `resultado.json`. Relacionadas: [[Gerencia - Resumen compacto movil y citas por equipo (2026-10-05)]] y [[Gerencia - Navegacion inferior movil en vista previa (2026-10-05)]].
