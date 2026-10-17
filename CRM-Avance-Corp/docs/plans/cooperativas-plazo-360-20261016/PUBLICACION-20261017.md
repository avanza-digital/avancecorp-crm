# Cooperativas 360: publicado

Estado: **PUBLICADO Y VERIFICADO** en https://crm.miavance.com el 16/10/2026,
23:25–23:27 de Lima (17/10 UTC). La PR [#315](https://github.com/avanza-digital/avancecorp-crm/pull/315)
se fusionó a las 04:18:24 UTC.

## Fuente y artefacto

- Commit publicado: `f1e6f60269b300f300291b64ad0a007788d9a94b`.
- Árbol: `51119623f2bf4872d7fcf131020d7c297b6c0904`, idéntico al candidato probado.
- Main local del clon y del repositorio compartido siguen `avancecorp/main` y
  apuntan a ese commit. La rama y los cambios ajenos del checkout compartido se conservaron.
- ZIP: `crm-20261017T042148Z-f1e6f60269b3.zip`.
- SHA-256: `ec0cd6f70893b19ec11f85bfe92a6cabac25c1bc8893725a977b16fb6ac0ea1c`.
- Build servido: `build-20261017T042147508Z`.
- Artefacto y manifiesto: carpeta `CRM-Avance-Corp/releases/`, preservados también
  en el clon limpio `/private/tmp/avancecorp-coop360-release-20261016`.
- `release:crm` y `release:crm:verify`: PASS. Fuente limpia, configuración pública
  de producción, sin llaves privilegiadas, fixtures demo ni PDFMake.

El primer preflight no encontraba el manifiesto del release vivo, que había
cambiado a `92ae6f94` durante las pruebas. Se recuperaron y verificaron su ZIP
y manifiesto locales. Es ancestro del candidato; el preflight obligatorio pasó
sin modificarlo ni usar una rama de rescate. #313 y #314 quedan incluidas.
Se reconfirmó Main/remoto antes del envío y se publicó una sola vez por MCP
Hostinger con la sesión OAuth existente. No se reconfiguró el conector.

Recuperación preservada: `crm-20261017T032704Z-92ae6f94d3a7.zip`, SHA-256
`4acec75eabfb88ad320ded8ee2d21877b3bd43616f0dfee4292536d8587b62c4`.
Es el release inmediatamente anterior, además del ZIP más antiguo guardado.
No se ejecutó rollback ni una segunda publicación.

## Base de datos

Merge nativo Supabase de la rama `94cba615-4071-46ea-b69a-85c2092041ad`:
aceptado y completado, Main `FUNCTIONS_DEPLOYED` / `ACTIVE_HEALTHY`.
El acuse inicial fue asíncrono; se esperó a comprobar el estado y el catálogo,
sin repetir la operación ni aplicar SQL productivo por otra vía.

Se instalaron exactamente `20261016195003`, `20261016231301` y `20261016232742`,
con 17, 7 y 7 sentencias registradas. SHA y sentencias coinciden con los tres
archivos aprobados. Historial: 487→490; digest de las 487 entradas originales
intacto: `c2bb35ce082c65d2948ca2724548aece`.

- **84/84 contratos históricos conservados**, comparando hash por fila antes y
  después, excluyendo únicamente la nueva columna. Todos quedan `calendario`.
- Nuevas altas: `base_plazo` NOT NULL, default `dias_360`; 12 meses devuelven
  360 días. Correcciones históricas conservan calendario. Ambos CHECK validados.
- Solo cambian la relación `crm.cierres_externos`, cinco cuerpos de función y
  se añade el helper de cuatro argumentos. Los cuerpos coinciden con el banco probado.
- Permisos, owners y configuración de funciones existentes intactos;
  **62 ACL por columna idénticos**. Las **23 Edge Functions sin cambios**.
- Auditores de historial, registro de Gestión Diaria y cola v3: PASS en lectura.
- Advisors productivos: seguridad **381→381**, rendimiento **190→190**,
  cero hallazgos nuevos o retirados.

Evidencia agregada, sin datos personales: [sql-publicacion-verificada.json](sql-publicacion-verificada.json).
No se crearon ni modificaron contratos reales para probar.

## Verificación del sitio

| Control | Resultado |
|---|---|
| Portada y versión sin query de caché | PASS: HTTP 200, SHA exacto del manifiesto |
| JavaScript principal | PASS: `./assets/index-CWTWIlpJ.js` |
| 115 JS y 7 CSS | PASS: HTTP 200, bytes y SHA exactos |
| Otros archivos no PNG | PASS; 148 entradas en total, incluida protección de `.htaccess` |
| 13 PNG | PASS HTTP 200 y tipo imagen; fuentes idénticas al ZIP anterior |
| Comparación literal ampliada | **FAIL literal: 149/161 coincidencias; 12 PNG diferentes** |
| Acceso en Chrome | PASS: Resumen de Gerencia cargado con sesión existente; sin errores de consola |

La diferencia de PNG permanece tras purgar la caché del sitio por MCP y pedir
`Cache-Control: no-cache, no-transform`. Cinco logos pasan de 3508×3253 a
1600×1484; las cabeceras son de `hcdn`. Es compatible con la optimización de
ancho/calidad documentada por [Hostinger](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/)
y con lo observado en el release del 07/10. Se conserva el FAIL literal;
no se atribuye igualdad binaria a esas imágenes ni se modificó la configuración CDN.
El gate de HTML/JS/CSS/versión y el acceso básico están aprobados.

Evidencia: [smoke-publicacion.json](smoke-publicacion.json) y
[diagnostico-assets.json](diagnostico-assets.json).

## Cierre y límites

El banco `qlsukwhdouhgzkjgsebe` se eliminó aproximadamente a las 04:27 UTC;
la consulta posterior confirmó su ausencia y conservó las otras cuatro ramas.
Duración de este tercer banco: unas 2 h 3 min; coste orientativo **US$0,0276**
según US$0,01344/h, no factura. Los bancos anteriores ya estaban eliminados.

Credenciales temporales, mapa privado de filas, exportaciones de esquema e
historial y carpeta CLI temporal retirados. La sesión OAuth global se conservó.
Constancia: [limpieza-publicacion.json](limpieza-publicacion.json).

Los gates completos, revisión y salvedades se conservan en
[ACTA-RELEASE.md](ACTA-RELEASE.md) y [RETOMA-20261017.md](RETOMA-20261017.md):
7.000 pruebas de app, 4.059 aserciones RLS, E2E completo con 438 passed / 1 flaky
/ 26 skipped y sonda corregida 9/9. La revisión adicional de auditoría quedó
NOT RUN; dos divergencias de datos preexistentes permanecen documentadas.

Las sesiones/PWA abiertas deben actualizarse para usar el formulario nuevo.
Los borradores anteriores no se reescriben; el servidor rechaza fechas nuevas
que no respeten 30 días por mes. El cambio no altera la tasa anual.

Esta acta posterior no cambia el commit fuente del manifiesto ni requiere
volver a publicar.

## Verificación del cierre documental

JSON, frontmatter YAML, enlaces Markdown, wikilinks y SHA del parche histórico:
PASS. `git diff --check` pasa para los documentos finales. La comprobación
global señala espacios preservados dentro de `release-pausado-desde-1170.patch`:
se conserva ese artefacto histórico byte por byte, con la huella de la pausa,
incluidos los espacios propios de su diff y sus salidas de consola.
No se repiten las pruebas de producto para este cierre exclusivamente documental.
