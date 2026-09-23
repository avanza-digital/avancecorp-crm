# F4 — reanudación y ensayo del correctivo autorizado

Miguel reanudó y autorizó el quinto SQL exacto de la
[propuesta](F4-CONFLICTO-HTTP-PROPUESTA-2026-09-23.md). Continúan vigentes los
cuatro SQL anteriores, banco hasta US$1 y `$release-crm`. Producción permanece
v1 OFF. Los cinco SQL ya están instalados solo en el banco sintético;
contratos SQL y 24 mutantes PASS; matriz candidata en ejecución.

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

## Banco sintético actual

Rama `gestion-diaria-f4-correctivo-20260923`, ID
`1a09c7da-5f84-45cf-9c32-d08020ffb686`, ref `zviwoyvtccqhhdfqdang`, creada a
las 14:44:42 UTC, sin datos productivos. Coste US$0,01344/h; tope total US$1
incluyendo los ~US$0,048 estimados del banco anterior ya eliminado. Cerrar al
terminar y antes del 24/09 14:44 UTC. La rama `banco-f7` permanece intacta.

Después de conciliar el historial se ejecutó el rebase nativo de la rama sin
migraciones pendientes: Supabase confirma `FUNCTIONS_DEPLOYED / ACTIVE_HEALTHY`.

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
las seis columnas productivas; al publicar hay que cotejar su conservación.
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
mantienen diferidos. Matriz candidata, HTTP, concurrencia y carga pendientes.

## Recuperación del frontend vigente

Hostinger sirve `build-20260923T020403114Z`. Se respaldaron **114 archivos** y
se verificaron tamaños, contenido HTTPS y estabilidad de `version.json` durante
la captura. `.htaccess` se leyó con el MCP; su API omite el LF final, reconstruido
solo tras cotejar el contenido completo y los 2.977 bytes con el archivo canónico.

ZIP privado:
`releases/private/gd-f4-live-20260923/crm-live-build-20260923T020403114Z.zip`.
SHA-256: `6cecc4a023e01aa3f52610375bc15839b934e5b60c3b6891b1a7ca39a1258d4c`.
Manifiesto al lado: `respaldo.manifest.json`. Es una copia verificable del sitio
servido, no el ZIP original preparado por la otra sesión. No se publica como asset.

Pendientes: terminar matriz candidata, HTTP, concurrencia y carga,
reconfirmar diferencial y merge SQL OFF; Main limpio e igual al remoto,
release y smoke; política futura por gerencia y primera jornada real. La tasa
baja sigue NULL hasta F5; no declarar F4 terminada con pruebas sintéticas.
