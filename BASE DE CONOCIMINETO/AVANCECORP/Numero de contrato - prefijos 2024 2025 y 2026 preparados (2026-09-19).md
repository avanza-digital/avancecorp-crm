---
tags: [crm, portal, contratos, numeracion, auditado, publicado]
actualizado: 2026-09-19
---

# Número de contrato: prefijos 2024, 2025 y 2026

**PUBLICADO Y VERIFICADO el 19/09/2026 en CRM y portal.**

Miguel confirmó que los analistas pueden elegir `2024-01-`, `2025-01-` y
`2026-01-`. El último sigue como selección inicial del alta. El segmento `01`
no es el mes. Se transcriben seis dígitos del contrato físico, incluidos ceros
iniciales. La serie no determina las fechas ni el período comercial.

Alta, corrección y borradores del CRM conservan el número completo. La auditoría
ampliada pedida por Miguel y revisada con Claude detectó que los dos editores
antiguos del portal solo reconocían 2026: al corregir 2024/2025 perdían el prefijo.
También se corrigieron esos formularios, su búsqueda de duplicados y las
respuestas tardías de otra serie/contrato. Una nueva alta restaura 2026 y vacía
los dígitos. Los números legados AC mantienen el tratamiento anterior.

La base usa UNIQUE sobre el número completo; se admite repetir los seis dígitos
en series diferentes. Las relaciones con cuentas, cuotas, inversión, renovación
y PDF usan UUID. No se cambian permisos ni lógica financiera y no hace falta
una migración productiva para este selector.

## Evidencia

- PASS: gate CRM `npm run check`, 3.773 tests en 254 archivos, lint, tipos, cobertura y build; mismo código app publicado.
- PASS: 55 tests de componentes y 10 recorridos Playwright de alta CRM.
- PASS: 104 tests del portal; el defecto se reprodujo antes de corregirlo.
- PASS: DOM real del portal en Chromium, 390/1280 px, ambas pantallas.
- PASS: 48 tests del handler/renderer PDF, incluidos PDFs de las tres series.
- PASS: 14 comprobaciones SQL reales en copia sintética aislada con ROLLBACK,
  incluidos alta/corrección, snapshot, cuenta/cuotas, autorización, cinco horas,
  idempotencia y preparar/corregir/confirmar inversión.
- PASS: dos altas simultáneas del mismo número persisten una sola.
- PASS: 32 definiciones del recorrido reproducidas con huella idéntica a la
  lectura de producción. El resto del banco sigue siendo sintético local.
- Claude devolvió CHANGES_REQUESTED en la auditoría ampliada. El PRIMARY resolvió
  el fallo del portal y contrastó el resto con pruebas; no se pidió otro dictamen
  para conseguir aprobación.
- Se reparó una prueba anterior del portal que buscaba los roles en index.ts,
  aunque ahora están en autorizacion.mjs. Comprueba el resolver y la revocación;
  no se modificaron los permisos de producto.
- NOT RUN: `gate:realidad` no llegó a medir por faltar SUPABASE_URL en su entorno.
  El catálogo productivo se leyó mediante el conector. Sin escrituras productivas.

## Publicación coordinada completada

Miguel autorizó el release con `$release-crm` y aprobó el PR #31, integrado
el 19/09/2026 a las 22:08:23 UTC. La publicación se completó.

Primero se publicaron los seis archivos del portal, a las 22:32:13 UTC
(17:32 Lima): núcleo y módulos, luego HTML y service worker al final.
Pines vigentes: analista v29, contratos v44, numero-contrato-core v1 y SW v119.
Se usó TUS para actualizar solo esos archivos y se purgó la caché/CDN.
Después se publicó el CRM a las 22:33:24 UTC (17:33 Lima) mediante
`hosting_deployStaticWebsite`; también se purgó su caché.

**Guardar lo pendiente y actualizar las pestañas antiguas antes de operar con
2024/2025.** El código cargado en una pestaña antigua puede conservar el editor
previo hasta recargarla.

## Versión efectivamente publicada

- Main fuente: `4bd3dc1b5d1a71f60ec1abd6192f2dc92a4a1d3e`, alineado con
  `avancecorp/main` en una copia limpia antes de subir.
- Árbol app: `f0cec7e5e10a7a4c5ee1f609af22f1a5f2e734fa`, idéntico al PR
  aprobado y al check local de 3.773 pruebas. Main 4bd3dc1b solo agrega actas
  respecto del merge 0d1c1ae3; se reutilizaron esos gates.
- Portal: `35198b14a8b70790faf55443ca6b1df95c70882e`, publicado y verificado.
- ZIP CRM: `crm-20260919T222832Z-4bd3dc1b5d1a.zip`, 2.199.941 bytes.
- SHA-256: `d22bbf92654be4a003491cb161160d9549a7d2b164cea76771a0ad74423f1c53`.
- PASS: `release:crm`, `release:crm:verify`, configuración productiva y
  102/102 archivos locales del ZIP con tamaño y huella correctos.
- PASS GitHub del PR aprobado: `verify`, `e2e` y `preflight`; E2E remoto con
  206 aprobados y 26 omitidos. PASS local: 12 recorridos de contratos/historial
  y 104 pruebas del portal.
- PASS HTTP posterior: 65 archivos del CRM (portada, versión y todos los JS/CSS)
  y seis del portal con HTTP 200 y SHA-256 idéntico a sus manifiestos.
  JS principal vigente: `assets/index-DEdo03gm.js`.
- PASS Chromium: acceso CRM y entrada a los dos módulos del portal sin sesión;
  redirección al acceso público y apertura del formulario de correo, sin errores
  de página ni recursos fallidos. No hubo escrituras productivas de prueba.
- No se aplicaron migraciones ni Edge Functions en este release. Historial
  (#28) y permisos (#30) ya estaban integrados y sus actas registran el backend.

La conexión se recuperó sin cambiar configuración. Aunque la sesión solo
anunciaba facturación, el MCP `hostinger-hosting` ya estaba configurado.
Se utilizó el servidor oficial local instalado `hostinger-api-mcp` 1.59.0
por stdio, sus esquemas reales y el OAuth existente. No se instalaron paquetes
ni se cambiaron proveedor, DNS o configuración MCP. Sin credenciales en actas.

## Recuperación conservada

Se confirmó por HTTP el último release realmente publicado antes de este:
`crm-20260919T213432Z-4094df3c9224`, conservado con ZIP y manifiesto.
SHA-256: `66ae91eba9a5905e9671e2a2dd3f891ea62938d4b4aeedfe9f650e68f6fc5bb4`.
También se reconfirmaron y conservaron los cinco archivos anteriores del portal.
El editor antiguo no preserva 2024/2025: evaluar compatibilidad antes de
recuperarlo si ya existen contratos con esas series.

El paquete 0d1c1ae3 y las candidatas a030fb7b/766353c2 nunca se publicaron.
Una acta posterior no cambia el commit fuente del despliegue. Se preservaron
los trabajos ajenos del taller.

[Acta, ZIP, manifiestos y comprobaciones de publicación](../../CRM-Avance-Corp/docs/publicaciones/prefijos-contrato-2026-09-19/README.md)
y `estado-release.json` registran **PUBLICADO_Y_VERIFICADO**, sin bloqueos.

[Informe de auditoría con alcance y límites](../../CRM-Avance-Corp/docs/auditorias/prefijos-contrato-2026-09-19.md).

Relacionado: [[Número de contrato]] · [[Ciclo de vida de contratos]] ·
[[Periodo comercial de contratos]] · [[Inicio]].
