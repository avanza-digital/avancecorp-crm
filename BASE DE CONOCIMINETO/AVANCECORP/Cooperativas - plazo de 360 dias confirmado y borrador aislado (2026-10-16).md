---
tags: [crm, cooperativas, contratos, plazo]
estado: publicado
actualizado: "2026-10-17"
---

# Cooperativas: plazo de 360 días publicado

> Estado vigente: PUBLICADO en crm.miavance.com desde Main f1e6f602; 84 históricos conservados y bancos temporales eliminados. Detalle al final.

## Preparación inicial — registro histórico

Miguel confirmó 12 meses = 360 días corridos para Qorilazo y Prodelco;
cada mes equivale a 30 días. La tasa anual no cambia. Los contratos anteriores
conservan calendario, aun al agregar/corregir condiciones. Nuevos usan dias_360.

SQL exacto aprobado, SHA256 518641adaee9ca85d8eecf50cfe09dd50d79af377cee3613af6a96bac0acd363.
Implementación y evidencia persistidas en
`CRM-Avance-Corp/docs/plans/cooperativas-plazo-360-20261016/README.md`.
No integrado en Main, instalado en producción ni publicado. Copia aislada
porque el checkout compartido contenía trabajo ajeno. No se cambió su rama.

PASS: lint, TypeScript, build, 6.998 unitarias, 29 E2E Docker F5/F6, replay
SQL/reversa, 95 casos Auth/RPC/Storage reales, check:scripts y preflight Edge PASS. Preflight de solo lectura:
74 registros productivos, 49 con condiciones, 0 incompatibles con CHECK nuevo.
Advisors sin hallazgos nuevos: seguridad 380→380, rendimiento 345→332.
Dos reviews Claude CHANGES_REQUESTED; el PRIMARY cerró sus verificaciones con
evidencia, sin pedir un dictamen favorable adicional. Gerencia lee revisión
real del servidor y el cliente ya acepta Prodelco USD con etiqueta correcta.

Miguel aprobó US$0,01344/h en la organización de PortalAvanceCorp. Banco remoto
creado 16/10/2026 20:33:34 UTC y eliminado 22:01:02 UTC, ausencia verificada.
Coste estimado por tarifa ~US$0,02. Sin clientes copiados ni producción alterada.
El historial viejo de rama falló; se reconstruyó a paridad y se eliminó, sin merge.

Pendiente integrar sobre Main vigente, gate RLS integral y E2E completo y
publicación coordinada mediante invocación humana `$release-crm`/`/release-crm`.
Las PWA antiguas pueden aplazar actualización: detener altas durante ventana,
actualizar sesiones y editar/revisar solicitudes antiguas. Recontar tres
solicitudes preparadas observadas antes; no se reescriben automáticamente.

Relacionadas: [[F8 - ajustes de cartera y condiciones COOPAC preparados (2026-09-14)]] ·
[[Upgrade cooperativo separado de reinversion (2026-10-06)]] ·
[[Cierres en cooperativas Qorilazo y Prodelco - plan]].

## Pausa del release — 16/10/2026, 23:45 UTC

Miguel invocó `$release-crm` y aprobó corregir el control de auditoría antiguo. Después pidió «cuando sea seguro pausamos porfa». Se pausó sin merge SQL, sin push a Main y sin publicar; producción conserva las 487 migraciones y el helper anterior.

El segundo banco temporal (coopac360-release-20261016, oneyeeplsvfgwzfgixhb) se eliminó a las 23:45:54 UTC y se verificó su ausencia. Coste estimado por tarifa US$0,0182, no factura. Credenciales temporales y exportaciones privadas retiradas. Pruebas detenidas, checkout compartido preservado.

Gates nuevos: check integral de app PASS (6.998 pruebas), E2E completo Docker PASS (439 passed,26 skipped), scripts/preflights/tipos PASS; tres auditores de lectura OK y 43 mutantes oficiales más4 propios detectados. RLS integral quedó INCOMPLETO (1.677 positivas,3 fallos antiguos identificados y corregidos en pruebas/fixture, sin repetición final). No declarar release aprobado.

Trabajo guardado en `CRM-Avance-Corp/docs/plans/cooperativas-plazo-360-20261016/PAUSA.md`, `ACTA-RELEASE.md` y `release-pausado-desde-1170.patch` (huella en pausa-huellas.json). Clone en /private/tmp/avancecorp-coop360-release-20261016: commit local d4d47502087b2ebd394c64456bee28a656317079 y ajustes adicionales preparados sin commit. El parche permite recuperar también esos ficheros nuevos contra Main1170a5e3.

Al retomar, recrear banco con configuración/catálogos de migraciones, repetir RLS completo, integrar Main vigente y reconstruir desde commit limpio sincronizado. El ZIP d4d4750 quedó preparado y nunca publicado. La autorización previa se conserva; los gates pendientes siguen siendo obligatorios.


## Retoma y PR #315 — 17/10/2026 UTC

Miguel reanudó con «sigamos!!!». Main remoto incorporó #313 y #314; ambos
se integraron sin conflictos y se conservaron. Gates cerrados: app integral
7.000 pruebas / 435 archivos; RLS 4.059 aserciones sin fallos; E2E Docker
438 passed, 1 flaky y 26 skipped. La carrera de la sonda al cambiar a móvil
se corrigió sin cambiar producto y pasó 9/9 adicionales sin reintentos.
Mutantes 43 + 4 rechazados; catálogo final y 62 ACL por columna intactos.
Las limitaciones y salidas completas constan en el expediente de [[Cierres en cooperativas Qorilazo y Prodelco - plan]].

GitHub rechazó el push directo por historial lineal, PR obligatoria y checks.
Se linealizaron cuatro commits sin cambiar el árbol probado
`51119623f2bf4872d7fcf131020d7c297b6c0904`.
PR: https://github.com/avanza-digital/avancecorp-crm/pull/315
Feature: `crm/cooperativas-plazo-360-20261016`, HEAD
`5872a53287c192eae7a9bd0078637df1c5ef57ec`.
No se publica desde esa rama: construir solo tras fusionar y verificar Main
idéntico a avancecorp/main. GitHub exige una revisión aprobada; a las
04:11 UTC seguía REVIEW_REQUIRED. Miguel dijo que podía conseguirla.
La PR pertenece a miguejbs98 y no puede autoaprobarse; el otro administrador
listado es jhosepv96. No hay CODEOWNERS en el árbol. No se usó bypass.
La fusión automática está deshabilitada en el repositorio; no se cambió esa opción.

Hostinger ya responde mediante la sesión OAuth MCP existente. El 401 inicial
lo causaba un helper que forzaba un token antiguo del llavero; no hizo falta
reconfigurar el MCP ni compartir credenciales por chat.

Banco temporal activo: coopac360-retoma-20261017,
ref qlsukwhdouhgzkjgsebe, ID 94cba615-4071-46ea-b69a-85c2092041ad,
creado 02:24:08 UTC, US$0,01344/h ya autorizados. Tiene historial base exacto
487 y solo las tres candidatas aprobadas, aplicadas por CLI con sus versiones
originales. Fuente sigue intacta: 84 cierres, 59 con condiciones, cero
incompatibles y base_plazo ausente. No se ha hecho merge SQL ni deploy.
Eliminar el banco y sus credenciales al cerrar el release.

Continuación privada saneada y herramientas en
`/private/tmp/avancecorp-coop360-publicacion/ESTADO-RETOMA-4-20261017.json`.
Clon aislado: `/private/tmp/avancecorp-coop360-release-20261016`.
Expediente compartido actualizado en
`CRM-Avance-Corp/docs/plans/cooperativas-plazo-360-20261016/`.

## Publicación completada — 17/10/2026 UTC

PR #315 fusionada a las 04:18:24 UTC. Fuente publicada:
`f1e6f60269b300f300291b64ad0a007788d9a94b`, árbol idéntico al candidato probado.
Main local y avancecorp/main sincronizados; checkout compartido y cambios ajenos preservados.

Publicado por MCP Hostinger en https://crm.miavance.com desde el ZIP limpio
`crm-20261017T042148Z-f1e6f60269b3.zip`, SHA-256
`ec0cd6f70893b19ec11f85bfe92a6cabac25c1bc8893725a977b16fb6ac0ea1c`.
Build vivo `build-20261017T042147508Z`. El release anterior 92ae6f94 de #314
ya estaba publicado; se recuperó su manifiesto y se verificó su ascendencia.
Preflight PASS; una única publicación, sin rollback ni reconfiguración MCP.

Merge nativo Supabase completado: solo las tres migraciones aprobadas,
historial 487→490 y digest base intacto. Los 84 contratos originales conservan
exactamente sus datos y vencimientos; base calendario. Nuevos: meses × 30 días,
12 meses = 360 días, sin cambiar tasa anual. Correcciones preservan la base.
Tres validadores PASS; 62 ACL por columna intactos; 23 Edge Functions sin cambios.
Advisors productivos: seguridad 381→381 y rendimiento 190→190, sin nuevos avisos.

Smoke: portada/versión y 115 JS + 7 CSS con HTTP 200 y SHA exactos; acceso de
Gerencia comprobado en Chrome y consola sin errores. La comparación ampliada
conserva FAIL literal en 12 de 13 PNG; todos responden 200 y los originales del
ZIP son idénticos a los anteriores. Dimensiones/cabeceras son compatibles con
optimización CDN ya observada en otros releases. Se purgó caché, sin cambiar
configuración. No confundir esa salvedad con un fallo del JS o de la regla 360.

Banco qlsukwhdouhgzkjgsebe eliminado a las 04:27 UTC aproximadamente;
ausencia verificada, otras ramas conservadas. Tercer banco: unas 2h03m,
US$0,0276 orientativos por tarifa autorizada, no factura. Los dos anteriores
ya estaban eliminados. Se retiraron credenciales, mapa privado de históricos,
exportaciones de esquema/historial y carpeta CLI temporal; OAuth global intacto.

Acta vigente: `CRM-Avance-Corp/docs/plans/cooperativas-plazo-360-20261016/PUBLICACION-20261017.md`.
Evidencia de SQL, HTTP y limpieza junto a ella. Los límites de E2E, RLS opcional,
review de auditoría NOT RUN y divergencias de realidad permanecen en las actas.
Actualizar sesiones/PWA abiertas; no se reescriben borradores antiguos.

Relacionado: [[Cierres en cooperativas Qorilazo y Prodelco - plan]].
