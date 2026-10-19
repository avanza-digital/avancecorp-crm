# Instalación y activación verificadas — 19 de octubre de 2026

**Producción activa desde las 09:44:22 de Lima (14:44:22.886326 UTC).** Modo `exigir`, revisión 2. Las primeras conversiones pendientes, antiguas y nuevas, requieren asistencia y entrevista con resultado de la misma cita y ciclo vigente. El frontend ya estaba publicado; no hizo falta otro ZIP web ni n8n.

Miguel aprobó el paquete SQL exacto y su activación: «ok hazlo tienes aprobacion». La actuación técnica quedó auditada con ADMINISTRADOR AVANCE CORP y motivo explícito de esa autorización; no se presenta como un login humano.

## Fase 6 — PASS, 6/6

- Paquete del [PR #332](https://github.com/avanza-digital/avancecorp-crm/pull/332), integrado en `3d5c040d9feac7d15f7c24a037188bb5ac62f148`. Main local y `avancecorp/main` coincidían y el árbol estaba limpio al construirlo.
- ZIP `20261019T134726Z-3d5c040d9fea.zip`, SHA256 `def103d06cc162995e64bb3028a56922dfdcc3ced3d0be16dce5e9ba98d0d822`: 15 migraciones, 27 archivos, integridad y huellas verificadas. Es el paquete SQL aprobado, no un ZIP para Hostinger.
- Preflight productivo PASS: PostgreSQL 17.6, seis contratos anteriores, historial base 509 y núcleo SLA. La rama ensayada conservaba las 15 migraciones exactas. Las 24 Edge Functions coincidían por contenido y configuración antes del merge.
- Instalación mediante merge nativo de la rama Supabase autorizada. El primer postflight se adelantó a la finalización asíncrona y rechazó el historial aún anterior; se esperó a `FUNCTIONS_DEPLOYED`. Postflight final PASS: **524 = 509 + 15**, identidad/nombre/contenido de cada migración, índice válido, 17 huellas de funciones, triggers activos y estado inicial `observacion`, revisión 1, sin fecha.
- Catálogo productivo: 12 funciones nuevas, 5 cuerpos modificados autorizados y 2 tablas nuevas con RLS. Propietarios y permisos anteriores, roles, publicaciones, `public`, Auth y Storage conservados. Las 24 Edge Functions también coincidieron después del merge.
- Guía productiva leída bajo los roles efectivos de gerencia, coordinación, supervisión y vendedor: 12 filas aceptadas por `RecorridosSchema` del frontend publicado. Los dos ámbitos restringidos excluyen un lead ajeno; anónimo y usuario sin ámbito reciben rechazo. Solo lecturas y contexto de rol transaccional, sin login humano ni datos sintéticos.
- Advisors revisados. Las tablas privadas sin policies y RPC autenticadas corresponden al diseño cerrado ya ensayado. El aviso de `pg_net` en `public` es previo al paquete, que no crea extensiones ni modifica `public`; [referencia del linter](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public). Los demás avisos y sus enlaces quedan en la evidencia; no se declaran resueltos problemas ajenos al cambio.

Evidencia: `fase6-preflight-produccion.json`, `fase6-postflight-produccion.json`, `fase6-catalogo-produccion.json`, `fase6-edge-paridad.json`, `fase6-guia-produccion.json` y `fase6-advisors-produccion.json`.

CodeRabbit observó en el PR #333 que la salida guardada del postflight solo mostraba el control inicial: la CLI conservó el último SELECT. Se completó la evidencia mediante una **nueva lectura de producción a las 15:12:19 UTC**, que registra **524 = 509 + 15**, digest de la base y las quince versiones, nombres y huellas observadas, comparadas con el paquete aprobado. Ver [salida productiva detallada](evidencia/fase6-postflight-migraciones-produccion.json) y [SQL de solo lectura reproducible](operacion/06-evidencia-paquete-produccion.sql). La captura identifica el control activo en ese momento; el [registro original](evidencia/fase6-postflight-produccion.json) conserva por separado la observación inicial. La evidencia de la rama de ensayo no se usa como sustituto de esta consulta productiva.

## Fase 7 — PASS, 6/6

Se ejecutó el `03-activar.sql` aprobado después del postflight, mediante la RPC administrativa existente. Control vigente confirmado: modo `exigir`, revisión 2, fecha del servidor **2026-10-19T14:44:22.886326Z** y actor administrativo autorizado.

El guard productivo rechazó **100 leads pendientes sin hechos válidos** con `P0409` y el mensaje «Antes de convertir…». La comprobación tomó locks y leyó filas existentes dentro de una transacción con `ROLLBACK`; no creó inversiones ni acreditó citas. Se añadió únicamente un contador de sesión a la comprobación aprobada para conservar su resultado. La CLI quedó esperando durante su inicialización sin una consulta activa en el servidor; se interrumpió exclusivamente ese proceso y la comprobación se ejecutó por el conector, con resultado PASS.

La guía con exigencia activa volvió a pasar el contrato del frontend en los cuatro roles, 12 filas, dos exclusiones de ajenos y dos rechazos. Las filas operativas consultadas estaban marcadas como exigibles.

El camino positivo con hechos de la misma cita/ciclo, los reintentos y la reversión se acreditan en las matrices locales y hosted previas: **99 comprobaciones en cada entorno**, con las mismas funciones ahora verificadas por huella en producción. La reversión productiva no se ejecutó porque no hubo una incidencia que la requiriera. No se confunde esa prueba aislada con una conversión comercial nueva en producción.

Evidencia: `fase7-activacion-produccion.json`, `fase7-bloqueo-produccion.json`, `fase7-guia-produccion.json` y `fase7-estado-produccion.json`.

## Fase 8 — 4/6; aceptación comercial pendiente

| Subfase | Estado y alcance de la evidencia |
|---|---|
| 8.1 Sin requisitos no convierte | PASS: 100 rechazos del guard productivo, sin escrituras. |
| 8.2 Misma cita y ciclo sí continúa | PASS en banco; **NOT RUN con una primera conversión real en producción**, pendiente de atención real. |
| 8.3 Antiguos incluidos | PASS: alcance global instalado, lectura exigible y rechazo de antiguos en producción; los 2.116 pendientes del censo tenían ciclo anterior al inicio. |
| 8.4 Reintentos sin duplicados | PASS en matrices local y hosted; código instalado idéntico. No se volvió a confirmar dinero real como prueba. |
| 8.5 Evidencia y capacitación | PASS: acta, ledger, [plan Figma](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=72-190) y [capacitación](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=39-190) actualizados; rama temporal eliminada y ausencia verificada. |
| 8.6 Aceptación comercial + cierre final | PENDIENTE de 8.2 y de comprobar el recorrido con el equipo. |

Censo de solo lectura a las **14:49:09 UTC**: 2.116 pendientes, 2.038 incompletos, 78 ambiguos y **0 listos**. Es una fotografía de actividad real, no un total fijo. Los 78 ambiguos no se acreditaron automáticamente. Ya se observaron 12 contextos de actividad capturados por el backend nuevo; no equivalen por sí solos a entrevistas completas.

La regla está instalada y activa. El plan queda en **46/48 subfases (95,8 %), 7/8 fases cerradas**. Para cerrar las dos restantes, un analista deberá registrar una asistencia y entrevista que realmente ocurrieron, confirmar por el flujo normal la primera inversión correspondiente y comprobar que el recibo/reintento conserva una sola operación. No se fabrican visitas ni inversiones para alcanzar el 100 %.

La rama `recorrido-integral-20261019` (`c42dac35-1185-40b9-9e24-5961e9c29981`) fue eliminada y su ausencia verificada a las **14:50:21 UTC**, dentro de las 24 horas autorizadas. Se retiró también el respaldo local de limpieza programada; las otras ramas no se tocaron. Ver `fase8-rama-eliminada.json`.

Prueba manual de navegador/VoiceOver y conversión comercial nueva en producción: **NOT RUN**. Se respetó la instrucción de trabajar sin controlar el navegador. Los 42 E2E Docker y las revisiones de Claude/CodeRabbit conservan su evidencia previa; esta fase no cambió código de producto.
