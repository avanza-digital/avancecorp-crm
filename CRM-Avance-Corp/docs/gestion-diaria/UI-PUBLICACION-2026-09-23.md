# Gestión Diaria — mejora visual publicada el 23/09/2026

La mejora de «Mi día» del analista y «Mi equipo hoy» del supervisor ya está en
[crm.miavance.com](https://crm.miavance.com/#/gestion-diaria), tras fusionarse
[PR #82](https://github.com/avanza-digital/avancecorp-crm/pull/82).
La autorización previa de `$release-crm` sigue vigente. Se verificó el merge
real y su CI antes de publicar; no se evitó ninguna regla de aprobación.

La aceptación de los dos roles en producción sigue **pendiente**. El acceso
autenticado y registro de gerencia están comprobados. Este release no acredita
la primera jornada real de F4 del 24/09.

## Fuente y artefacto

| Dato | Valor |
|---|---|
| Fuente del frontend publicado | `e8e4f35f9ea1bc1b88da469ff45a998d7d40bb91` |
| Rama y remoto al construir y publicar | `main` limpio, igual a `avancecorp/main` |
| Build | `build-20260923T204457952Z` |
| ZIP | `crm-20260923T204458Z-e8e4f35f9ea1.zip` |
| SHA-256 | `ab631a4fac25c53c3d32bd49514c99d92c6420dd2c9b92c1a823a88a46f22de6` |
| Tamaño | 2.260.676 bytes; 114 archivos |
| Destino y operación | `crm.miavance.com`; MCP oficial Hostinger, `hosting_deployStaticWebsite` |
| Cierre de comprobación HTTP | 23/09/2026, 16:03 Lima / 21:03 UTC |

El ZIP, manifiesto y recibos quedan en `CRM-Avance-Corp/releases/` de la copia
aislada `/private/tmp/avancecorp-release.hvdub4/repo`. No se incluyen secretos
ni archivos de entorno. La configuración pública y la exclusión de fixtures
demo del bundle pasaron los gates del release. No hubo SQL, Edge Functions,
datos sintéticos productivos ni cambios de política de cortes en esta entrega.

Se preservó la integración previa de Main, incluidos PR #80 y PR #81. La
migración de conversión de PR #81 pertenece a otra tarea y no se instaló aquí.
Las actas posteriores no cambian el commit fuente del artefacto ni justifican
volver a publicarlo.

## Verificación real

| Comprobación | Resultado y alcance |
|---|---|
| `npm run check`, Main `e8e4f35f` | **PASS**: 280 archivos / 4.179 pruebas, lint, typecheck, cobertura, build, bundle, configuración de release, push tests y duplicación. Cuatro warnings previos en `coverflow-carousel.tsx`, sin errores. |
| CI del PR #82 | **PASS**: `cambios`, `app-check` y `verify`. |
| Suite completa E2E en Docker, antes de corregir fixtures | **FAIL: 228 passed / 6 failed / 26 skipped**, 12,0 min. Los seis fallos pertenecen a `e2e/sla-operacion.spec.ts`. |
| Spec completo con fixtures corregidos | **PASS: 15 passed / 0 failed**, 37,6 s. Contiene todos los fallos anteriores y mantiene idéntico código de producto. |
| `release:crm` y `release:crm:verify` | **PASS**, fuente limpia y ZIP íntegro. |
| Archivos de origen | **PASS**: 113 por HTTPS más `.htaccess` por MCP; coinciden bytes/SHA con el manifiesto. |
| Portada, versión y código en CDN público | **PASS**: portada e `index.html` exactos, build correcto antes/después; los 75 JS/CSS coinciden en bytes/SHA. |
| Imágenes públicas | **Variantes CDN documentadas**: 102 de 113 archivos públicos exactos; 11 PNG con otros bytes, integridad PNG y respuesta HTTP correctas. No se afirma identidad binaria de esas variantes. |
| Smoke de gerencia en Chrome | **PASS**: acceso autenticado, Gestión Diaria y registro con datos después de recargar. DOM carga `index-BQsQUw42.js` y `index-DPXusWJW.css`, correspondientes al artefacto. Sin escrituras productivas. |
| Smoke productivo y aceptación de analista/supervisor | **NOT RUN / pendientes**: la sesión real disponible es gerencia; no se simularon identidades. |
| `npm run gate:realidad` | **NOT RUN** por ausencia de credenciales de servicio en la copia. La lectura SQL parcial descrita abajo no lo sustituye. |
| Figma | **PASS**: actualizado el mismo bloque `2:130`, textos `2:132` y `2:133`; captura inspeccionada, sin desbordamiento. Las 76 casillas por fases conservan su estado. |

El gate integral está en `/private/tmp/gestion-diaria-ui-release-check.log`; la
primera ejecución E2E en `/private/tmp/gestion-diaria-ui-release-e2e.log`. El
spec corregido se ejecutó en Docker con dos workers y recursos identificados
como Gestión Diaria. Los E2E no se ejecutaron en GitHub.

No se suman 228 + 15 como casos únicos: nueve casos del spec ya habían pasado
antes. La evidencia combina la suite inicial y la repetición completa del único
spec modificado; **no se presenta como PASS integral en una sola ejecución**.

## Por qué se corrigieron los fixtures de Seguimiento

PR #80 omite los argumentos opcionales vacíos `p_etapa` y `p_analista_id`.
Los mocks los copiaban como `undefined` a la respuesta; al serializarla faltaban
claves requeridas y el cliente rechazaba el fixture. Una lectura de la función
productiva `crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)` confirmó ambos
`DEFAULT NULL`. Se normalizó la respuesta ficticia con `?? null` y se actualizó
la expectativa del request. `p_cursor: null` se conserva, como envía el cliente.

La corrección `4fd744a3` está en [PR #84](https://github.com/avanza-digital/avancecorp-crm/pull/84).
Antes de añadir esta acta, el diff respecto de Main afectaba únicamente
`CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts`; no modificaba `src`, SQL ni el
bundle. Por eso el ensayo corregido valida el mismo producto publicado desde
Main limpio. Precommit, typecheck y prepush de esa corrección pasaron.

## Diferencia de imágenes en el CDN

La primera comparación estricta de todas las URLs públicas se detuvo en
`aliados/belysh.png`: 257.370 bytes públicos frente a 212.660 del paquete.
Se diagnosticó antes de considerar una repetición o recuperación:

- El servidor de origen entrega exactamente el PNG del ZIP: 3508 × 3253.
- El CDN entrega una variante PNG de 1600 × 1484. Con query nueva de build,
  `x-hcdn-cache-status: MISS` devolvió la misma variante que el HIT; no era
  simplemente una copia antigua de ese archivo.
- El inventario completo del origen coincide. Las once diferencias públicas
  se limitan a PNG; todos los JS/CSS coinciden. Los once PNG recibidos tienen
  firma, chunks, CRC y flujo comprimido válidos.

Estos resultados son coherentes con la [optimización de imágenes documentada
por Hostinger](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/).
La interpretación es una transformación en el CDN, sin evidencia de corrupción
del artefacto. No se cambió la configuración de imágenes, DNS o caché ni fue
necesario volver a desplegar. El ZIP de release no queda accesible en la URL
pública comprobada (HTTP 404).

Recibos con el mismo prefijo del release: `.origen-https-verificado.json`,
`.cdn-https-comparado.json`, `.htaccess-verificado.json` y `.postflight.json`.
Este último conserva dimensiones y SHA públicos de las once variantes. El MCP
omite el LF final de `.htaccess`: contenido más ese LF coincide exactamente,
incluido el tamaño informado de 2.977 bytes y SHA
`c70380da325b9dcc9c18f2f504910694085865a02bb8eae2c6515f3bceef5510`.

## Datos reales y límites

Consulta SQL de solo lectura a las 15:37 Lima: 21 metas publicadas, cero
vendedores sin supervisor, 2.202 leads activos, 15.185 actividades, 1.306 tareas
pendientes, 21 personas en el equipo operativo y cero metas bajo el sello.
También devolvió 291 clientes sin domicilio, fuera del alcance de este cambio.
No se ejecutó la comprobación de alarma de conversión del gate completo;
estos totales son evidencia parcial, no un `gate:realidad PASS`.

La revisión de Claude permanece **CHANGES_REQUESTED** con sus correcciones
evaluadas y aplicadas por Codex; véase [el acta original](UI-REVISION-CLAUDE-2026-09-23.md).
No se pidió otra revisión para obtener un dictamen favorable.

## Recuperación y siguientes pasos

Se conservó y volvió a cotejar antes de publicar el ZIP realmente desplegado
anterior: `crm-20260923T173451Z-8e6f4357feb1.zip`, fuente `8e6f4357`, build
`build-20260923T173450335Z`, SHA-256
`a27c055d974064f9a14042c3b4a184a72c55cb3d5b4dd9b7065cafd8f2ccafc0`.
Es el respaldo para recuperar únicamente el frontend; no revertir SQL ni la
política futura como parte de esa operación.

Queda validar la UI con una sesión real de analista y otra de supervisor.
F4 mantiene pendientes la primera jornada del 24/09 (cortes 11:30 y 16:00),
el recorrido de avisos y el seguimiento del sábado 26/09. Tasa baja NULL/OFF
hasta F5. No se generó actividad ficticia para cerrar estos puntos.

El [plan principal](GESTION-DIARIA.md), el
[mismo tablero](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L) y la nota
del vault «Gestion Diaria - plan vivo en Figma y mejora visual (2026-09-23)»
registran este estado.
