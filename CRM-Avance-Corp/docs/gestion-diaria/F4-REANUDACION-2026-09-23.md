# F4 — ensayo, publicación y activación futura verificados

Miguel reanudó y autorizó el quinto SQL exacto de la
[propuesta](F4-CONFLICTO-HTTP-PROPUESTA-2026-09-23.md). Continúan vigentes los
cuatro SQL anteriores, banco hasta US$1 y `$release-crm`. Producción permanece
v1 OFF. **Los cinco SQL se publicaron mediante merge Supabase y quedaron
verificados en producción.** Banco sintético eliminado; frontend publicado desde
Main `6bf0e84a` inicialmente y actualizado a `8e6f4357` con PR #77; política v2
programada para el 24/09, 00:00 Lima. Hoy v1 OFF.
Primera jornada real pendiente; no se declara F4 completa.

## Actualización posterior — PR #77 publicado

El 23/09 a las 12:40 Lima quedó verificado `build-20260923T173450335Z`, fuente
Main `8e6f4357`. Corrección del detalle opcional con recibos anteriores conservados;
4.175 pruebas, 32 E2E focalizados y CI PASS. Los 113 archivos y el smoke de lectura
con gerencia coinciden; política futura intacta. Artefacto, SHA y recuperación en
[acta de la corrección](F4-DETALLE-OPCIONAL-2026-09-23.md).

## Frontend inicial publicado y smoke de gerencia

PR [#76](https://github.com/avanza-digital/avancecorp-crm/pull/76) ya fusionado.
Fuente del artefacto: `6bf0e84a6ea1f9da0477569da312d06a3a2a2064`, Main limpio
e igual a `avancecorp/main` antes de construir y antes de publicar. El código
de `app/` coincide byte a byte con `ba8722a3`, que pasó 4.170 tests y 234 E2E.
La CI de `3e631e01`, cabeza integrada del PR, terminó SUCCESS. No se atribuye
este despliegue a commits posteriores de actas ni se republica por documentación.

- URL: **https://crm.miavance.com**.
- Build: `build-20260923T163253090Z`; JS principal `assets/index-V1spwcHJ.js`.
- Artefacto: `releases/crm-20260923T163254Z-6bf0e84a6ea1.zip`, 2.258.827 bytes.
- SHA-256: `0800772132124f9451c3ca1b9452a979e15957695f60b020014ee6a815d37945`.
- `release:crm`, `release:crm:verify` y despliegue por MCP Hostinger PASS.
  El primer build sin variables públicas se detuvo; se inyectaron únicamente URL
  y anon key productivas al proceso y se repitió con el guard de configuración PASS.
- **113 archivos verificados:** 112 por HTTPS, bytes/SHA y versión estable;
  `.htaccess` por MCP, contenido íntegro y 2.977 bytes. Evidencias junto al ZIP:
  `.https-verificado.json` y `.htaccess-verificado.json` con el mismo basename.
- Smoke Chrome con sesión real de **gerencia PASS**: editor de configuración,
  registro de actividad de Gestión Diaria, publicación futura y persistencia
  tras recarga completa. Sin altas, borrados ni actividades ficticias de prueba.

## Política v2 guardada por gerencia

Creada el **23/09 a las 11:56:55 Lima** mediante el formulario productivo,
con vigencia **24/09/2026, 00:00 Lima** (`2026-09-24T05:00:00Z`).
Actor no nulo con rol gerencia y cadena hacia v1 comprobados por lectura SQL.
Motivo: «Activar cortes F4 desde el 24/09 tras verificar SQL y frontend; tasa
baja desactivada hasta F5.»

| Parámetro | Valor de v2 |
|---|---|
| Cortes | Activos desde el 24/09 |
| Primer corte / mínimo | 11:30 / 3 llamadas |
| Segundo corte / crecimiento | 16:00 / 150 % |
| Piso / techo | 8 / 30 |
| Sábado | Mínimo 3, corte único |
| Contacto Bien / Atención / muestra | 45 % / 25 % / 5 llamadas útiles |
| Tasa muy baja | NULL, desactivada hasta F5 |

Postflight: exactamente dos políticas, v1 vigente hoy y v2 mañana; un único
control inicial, canal habilitado y `private.assert_gestion_diaria()` PASS.
La UI muestra v2 programada y conserva v1 OFF después de recargar.

Observación del smoke: inmediatamente tras Confirmar apareció un aviso transitorio
de versión obsoleta mientras el botón decía Guardando; la siguiente lectura mostró
éxito y v2. No se repitió el envío. SQL confirma una sola inserción y los parámetros
exactos. Sin traza HTTP de ese instante no se atribuye una causa; comprobar si el
aviso reaparece en una futura edición legítima, sin crear versiones para ensayarlo.
Evidencia saneada: `/private/tmp/gd-f4-activacion-verificada-20260923.json`.

## Para cerrar la validación operativa

**NOT RUN: primera jornada real del 24/09.** Con supervisión, comprobar ambos
cortes a las 11:30 y 16:00 Lima, equipo/llamadas, popup/campana/lista,
reconocimiento/aplazamiento único persistentes entre sesiones o dispositivos,
ausencia de duplicados y de reaviso al cierre. Registrar tiempos y errores reales;
no cambiar relojes, identidades ni datos productivos para simular el día.
El sábado 26/09 verificar corte único y mínimo 3 como seguimiento operativo.
F4.1/TypeSafe y F5 quedan fuera; tasa baja OFF. Los avisos de índices conservan
su tratamiento diferido y no impidieron los gates de esta entrega.

## Resultado final del ensayo e instalación SQL

- Matrices remotas: **2.221 PASS / 0 FAIL** antes y después del candidato.
- Contratos SQL, 24 mutantes, Auth/HTTP de seis roles y paridad de dos equipos PASS.
  Dos carreras remotas con dos esperas observadas: una respuesta 200 y otra
  409/PT409 en publicación futura y control del canal; estado del canal restituido.
- Carga: 2.200 leads y 15.400 actividades sintéticas, 120 lecturas. P95 legado
  3.519/2.567 ms y activo 3.350/2.820 ms para los dos equipos. No es p95 de usuarios reales.
- Merge solicitado el 23/09 a las 11:15 Lima. Se esperó la transición nativa
  RUNNING_MIGRATIONS → FUNCTIONS_DEPLOYED; no se repitió la solicitud.
- Producción: seis gates PASS, **346 migraciones / 737 funciones**. Las 341
  entradas anteriores mantienen todas sus seis columnas. El merge nativo divide
  los cinco archivos en 53/21/15/19/6 sentencias: cada byte se cotejó en orden,
  excluyendo únicamente punto y coma y espacios entre sentencias. No se reparó
  ni reescribió el historial después del merge.
- Las 737 funciones coinciden con el candidato; 21 Edge Functions conservan
  versión/JWT/SHA. Política v1 OFF idéntica, tasa baja NULL, cero entregas,
  un control inicial. Diez cron/nueve activos y su huella intactos; 532 Auth
  conservados y cero fixtures de carga en producción.
- Advisors productivos sin ERROR; los seis WARN de RPC y dos de políticas
  internas corresponden a los evaluados en el banco. Los dos INFO originales
  de FK de política siguen registrados para después.
- Banco propio eliminado a las 11:22 Lima y ausencia confirmada. Cargo estimado
  de esta rama ~US$0,022; acumulado con la anterior ~US$0,070 (tope US$1).
  `banco-f7` no se modificó. La tarifa estimada no sustituye la factura.

Evidencia privada final: `gd-f4-merge-verificado-20260923.json`, snapshots
productivos antes/después, `gd-f4-operacion-prod-{antes,despues}-20260923.json`,
advisors y acta de eliminación en `/private/tmp`; ensayos en
`/private/tmp/gd-f4-remoto-20260923/`.

Límite explícito: carreras de presentación/aplazamiento HTTP remoto NOT RUN
con cortes OFF; tres carreras locales reales y horarios/acciones SQL remotos PASS.
La primera jornada real permanece pendiente y no se sustituye por estos fixtures.

## Integración y verificaciones terminadas

- Main avanzó a `8097ca8c` (PR #75, unificación de conversiones). Se integró en
  `ba8722a3`, preservando el cambio ajeno y ambas entradas del índice del vault.
  GitHub confirmó PR #76 MERGEABLE; sus conflictos quedaron resueltos.
- Código de aplicación idéntico al de ese Main: `npm run check` PASS,
  **4.170 tests / 279 archivos**, build, bundle y duplicación incluidos.
  E2E Docker propio: **234 PASS / 26 SKIPPED / 0 FAIL**, 9,3 minutos.
  `check:scripts` y preflight RLS offline PASS.
- La matriz remota descubrió una referencia `num(...)` fuera de alcance en el
  test de métricas recién incorporado desde Main. Se cambió por `Number(... ?? NaN)`:
  sigue comprobando igualdad numérica y los campos ausentes no pasan como cero.
  Un intento posterior recibió HTML transitorio de la API al preparar fixtures;
  tres lecturas de diagnóstico dieron 200 antes de reiniciar la matriz completa.
  Esos intentos fallidos se conservan como FAIL, nunca como PASS.
- La corrida completa posterior terminó con cinco fallos de 2.221 aserciones:
  el domicilio de `clientBank` seguía escrito por el intento abortado. El propio
  bloque `testDomicilioLegal` documenta que esa escritura no es reversible por
  las API normales. Se restauró la semilla desde el respaldo verificado, se
  volvió a cotejar el catálogo y se añadió un preflight que exige el domicilio
  NULL antes de iniciar. Las otras 2.216 comprobaciones no sustituyen un PASS
  de la matriz completa. La repetición limpia terminó **PASS: 2.221 aserciones**
  a las 10:42 Lima. Cada corrida completa deja tres altas `rls.*@example.test`
  y un perfil Auth sin correo; tras dos corridas hay 25 usuarios sintéticos.
  La restauración previa al candidato se detuvo por esperar 21 (rollback sin
  cambios). Se cotejaron esos fixtures con el test y se corrigió ese conteo;
  Auth se conserva completo durante la restauración.
- Los contratos SQL finales exigen `PT409` en ambas RPC. Los cinco archivos de
  migración aprobados conservan exactamente sus SHA; se modificaron los tests,
  no los SQL autorizados.

## Banco sintético utilizado — ya eliminado

Rama `gestion-diaria-f4-correctivo-20260923`, ID
`1a09c7da-5f84-45cf-9c32-d08020ffb686`, ref `zviwoyvtccqhhdfqdang`, creada a
las 14:44:42 UTC, sin datos productivos. Coste US$0,01344/h; tope total US$1
incluyendo los ~US$0,048 estimados del banco anterior. Se eliminó después del
merge y sus verificaciones, dentro del plazo de 24 horas. `banco-f7` permanece intacta.

Después de conciliar el historial se ejecutó el rebase nativo de la rama sin
migraciones pendientes: Supabase confirmó `FUNCTIONS_DEPLOYED / ACTIVE_HEALTHY`.

El replay histórico falló de nuevo; se reconstruyó solo la rama vacía desde
respaldos sintéticos con huella verificada. La semilla parte de siete leads,
cinco tareas y 17 usuarios ficticios. Sus dos cron quedaron apagados mediante
`cron.alter_job`; no se modificaron cron productivos. Las 21 Edge Functions
coinciden en versión, verificación JWT y SHA con el padre.

Después de la alineación inicial, se incorporaron los 14 avances productivos:
diez cuerpos de función, catorce comentarios y tres declaraciones técnicas.
**721 funciones y 341 versiones/nombres/sentencias de migración coinciden.**
Tablas/vistas, RLS, permisos y contratos de Auth/Storage cotejados; únicamente
se normalizan paréntesis de los tres CHECK ya documentados en el ensayo anterior.

El ledger inicial de la rama tenía tres columnas. El padre tiene además
`created_by`, `idempotency_key` y `rollback`: no se copiaron esos metadatos ni
se alteró manualmente la tabla del servicio para agregarlos. Al aplicar los cinco
SQL, el MCP añadió esas columnas de forma nativa. El snapshot privado conserva
las seis columnas productivas; su conservación se cotejó después del merge.
La conciliación productiva de etapa 3 ya terminó y no se repite.

Evidencia privada: `/private/tmp/gd-f4-remoto-20260923/`. La matriz completa
baseline pasó; semilla restaurada y alineación repetida. Cinco archivos con
bytes/SHA exactos, 341 entradas previas intactas y 346 totales. El diferencial
añade 16 funciones F4 y cambia solo los cuerpos de
`crm.alertas_reconocimientos_sellar()` y `private.assert_gestion_diaria()`.
No retira funciones. Sello/exenciones y tope 14 conservados; `actualizado_en`
del tope refleja su restauración en el banco.

Advisors del candidato: cero ERROR nuevos; seis WARN de
[RPC SECURITY DEFINER para authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
esperados para las puertas con validación de rol/ámbito probada. Dos WARN
[auth_rls_initplan](https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan)
en `lectura_interna` de control/entregas, ya documentados como mejora posterior.
Los INFO de índices no usados varían al restaurar estadísticas; no se eliminan
índices por un banco sintético. Los dos INFO originales de FK de política se
mantienen diferidos. Matriz candidata, HTTP, concurrencia y carga terminaron PASS.

## Recuperación del frontend anterior

Antes de publicar, Hostinger servía `build-20260923T020403114Z`. Se respaldaron **114 archivos** y
se verificaron tamaños, contenido HTTPS y estabilidad de `version.json` durante
la captura. `.htaccess` se leyó con el MCP; su API omite el LF final, reconstruido
solo tras cotejar el contenido completo y los 2.977 bytes con el archivo canónico.

ZIP privado:
`releases/private/gd-f4-live-20260923/crm-live-build-20260923T020403114Z.zip`.
SHA-256: `6cecc4a023e01aa3f52610375bc15839b934e5b60c3b6891b1a7ca39a1258d4c`.
Manifiesto al lado: `respaldo.manifest.json`. Es una copia verificable del sitio
servido, no el ZIP original preparado por la otra sesión. No se publica como asset.

El bloqueo previo de revisión de PR #76 ya está superado por su fusión. Se
conserva el respaldo para recuperación; no se revirtió SQL ni auditoría.
La publicación, smoke y política futura están verificados. Resta la jornada real
descrita arriba; la tasa baja sigue NULL hasta F5.
