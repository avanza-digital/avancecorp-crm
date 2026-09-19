# Conversión e inversiones publicadas — 19/09/2026

**PUBLICADO en https://crm.miavance.com.** El botón «Convertir a cliente»
reconoce la identidad y usa el mismo formulario, validaciones y confirmación de
«Nueva inversión» en Cartera. El lead sólo se convierte al confirmar la inversión;
cerrar conserva el avance y cancelar deja el lead abierto. Los reintentos
conservan una inversión inicial y su atribución al analista.

## Fuente y autorizaciones

Miguel autorizó SQL («HAZLO»), bancos temporales con máximo US$5 y frontend
mediante `$release-crm`. `miguejbs98` aprobó el
[PR #23](https://github.com/avanza-digital/avancecorp-crm/pull/23) a las
18:10:43 UTC y quedó integrado. No se eludió la revisión de GitHub.

Fuente publicada: `29d7aa202492ed7dbd9cbb62d7667953f50a1514`.
Main local de la copia limpia y `avancecorp/main` coincidían. Su árbol
`c592ee305b78e6f5f287936a8cb690db470f2868` es idéntico al de
`b3d385d5ac57b347548b3551c553ec57e7b0a559`, con CI verify, E2E y preflight
PASS. Se reutilizan esos gates y las 3.694 pruebas del mismo código; el build
de publicación y su verificador se ejecutaron sobre Main limpio.

- Artefacto: `crm-20260919T181822Z-29d7aa202492.zip`.
- SHA-256: `0e4624f42a89a319e317ab3ec361b8f074fb9e222f2ac2e6eefac5ad653d412f`.
- Versión servida: `build-20260919T181821426Z`.
- SQL promovido y Edge activos antes de subir el ZIP mediante Hostinger.
- La carpeta original de la otra sesión no se modificó. Las actas posteriores
  no cambian el commit al que pertenece este artefacto.

## Base de datos y Edge

La candidata inmutable
`20260919161807_crm_conversion_inversion_unificada.sql`, 107.472 bytes,
SHA-256 `2a8ce9e9be01ccdbf13871e299858db4a6a90551b195a2369ba14d06ddc4c5f4`,
se promovió mediante `merge_branch` desde la rama exclusiva
`conversion-publicacion-20260919` (`jyinaqutvoijyzoefwsj`).
Su versión efectiva en producción es **`20260919182218`**.

El merge serializó el archivo en 62 sentencias. Se comprobaron una por una
contra el archivo aprobado, en el mismo orden: entre ellas sólo hay espacios
y separadores. No se presenta el hash de la primera sentencia como hash del
archivo. Las 306 migraciones anteriores conservan su huella
`cab8c3b190eb38545e51a01fa2554156`.

Antes: 18 anclas vigentes y cero reservas antiguas bloqueantes. Después: las
671 funciones, definiciones, propietarios y permisos coinciden con el banco
probado; columnas, triggers, policies, RLS, índices y vistas también.
Las tres diferencias de paréntesis en CHECK ya documentadas provienen del
exportado del banco. No se promovieron fixtures, reconstrucción ni configuración.

La Edge `crm-inversion-bienvenida` está ACTIVE y sus dos fuentes descargadas
son idénticas a las versionadas. El empaquetado de Supabase cambia la huella
de su bundle al promoverlo. `crm-tipo-cambio` también fue reempaquetada
con fuentes idénticas; las otras 19 Edge mantienen su hash y configuración JWT.
La bienvenida autentica mediante la RPC de usuario antes de elevar a servicio.

## Verificación y límites

- **PASS:** oráculo económico con ROLLBACK y 284 aserciones bancarias en la
  rama final. El primer intento del gate no arrancó por faltar dependencias
  en la copia limpia; tras `npm ci` (lockfile sin cambios), el gate completo pasó.
- **PASS previo, mismo SQL/código:** 15 pruebas HTTP con Auth/PostgREST/Storage
  reales, nueve aserciones de Edge remota e integración de escritorio/móvil.
- **PASS producción:** ocho aserciones HTTP de CORS, método, tamaño y
  rechazo anónimo; no hubo envíos ni hechos económicos de prueba.
- **PASS publicación:** 92 peticiones HTTP 200, 81 huellas exactas, incluidos
  los 63 JS/CSS y la portada. CSP, no-store y nosniff presentes.
  `.htaccess` coincide como texto (el endpoint omite el salto final), responde
  403 y el ZIP público responde 404.
- **Excepción CDN conocida:** once PNG no conservan su hash HTTP. Seis
  conservan exactamente sus píxeles; cinco logos pasan de 3508×3253 a
  1600×1484. Todos los originales son idénticos al release anterior. Esta
  transformación de Hostinger ya estaba documentada; no se declara PASS de
  igualdad binaria para esos once archivos.
- **PASS conservación:** iguales antes y después los conteos/huellas de
  619 contratos, 5.466 cuotas, 56 inversiones, 512 personas, 25 solicitudes,
  flags y los nueve Cron activos. Son capturas de ese momento.
- **Advisors revisados:** 277→281 avisos de seguridad. Las cuatro altas
  son RPC SECURITY DEFINER autenticadas intencionales, con controles de
  actor/ámbito ya probados. No hay otras altas ni bajas.
  [Criterio del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
  En el banco, las diferencias de rendimiento son sólo `unused_index` INFO.
- **NOT RUN:** navegación autenticada en producción (el navegador integrado
  no dispone de navegador) y entrega real de correo. No se confunden con
  las pruebas completas de escritorio/móvil del banco.

[Recibo estructurado](publicacion-20260919.json) y
[evidencia del ensayo anterior](README.md). Se conservan los fallos iniciales
de diagnóstico; no se reescriben como ejecuciones exitosas.

## Cierre y recuperación

Ambas ramas temporales de esta tarea fueron eliminadas y se confirmó su
ausencia. `banco-f7` permanece intacto. Primera rama: 16:45:02–18:08:22 UTC,
US$0,018665 estimados. Segunda: 18:18:18–18:33:49 UTC, US$0,003477 estimados.
**Total estimado US$0,022142, inferior al límite de US$5**; no sustituye la factura.

Se conserva el ZIP antes publicado
`crm-20260919T162407Z-faccafe040ab.zip`, SHA-256
`cc324ac3f07c058ee4a9df1c8172aa06f48baa4e19677babb209b0f95ba03468`.
La reversa SQL ensayada permanece documentada; no se ejecutó. Recuperar el
frontend anterior por sí solo no restablecería las puertas antiguas que este
SQL cierra: cualquier recuperación debe respetar esa compatibilidad.

Artefactos y recuperación en
`/private/tmp/avancecorp-conversion-publicacion/CRM-Avance-Corp/releases/`.
Logs adicionales sin credenciales en
`/private/tmp/avancecorp-conversion-inversion/remoto-final/`.
