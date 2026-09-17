---
tags: [crm, analistas, tasas, notificaciones, jornada]
actualizado: 2026-09-16
---

# Solicitudes de tasa: rechazos solo en notificaciones

## Decisión de Miguel

Miguel mostró dos rechazos del 11/09 que seguían ocupando «Mi jornada» el 16/09.
El panel incluía deliberadamente rechazos de los últimos siete días, incluso
después de leer la respuesta. Aprobó retirarlos del recuadro y conservarlos como
notificaciones en la campana.

«Tus solicitudes de tasa» queda reservado para solicitudes propias y vigentes:
pendientes de Gerencia, topes por aceptar y autorizaciones pendientes de utilizar.
Si no hay solicitudes en curso, el recuadro desaparece. Al responder la última,
se conserva un anuncio accesible y el foco de teclado, sin una tarjeta vacía.

## Implementación local

- `CRM-Avance-Corp/app/src/screens/hoy/tasas-autorizadas-analista.tsx` consulta
  `ESTADOS_SOLICITUD_TASA_VIVOS` y filtra también por estado efectivo, vigencia
  y pertenencia antes de presentar las tarjetas.
- La campana mantiene su consulta independiente, avisos, sonido y lectura.
  Las respuestas terminales siguen consultables durante los últimos siete días;
  la lectura se conserva por cuenta y navegador, como antes.
- Los formularios conservan el contexto del rechazo para volver a solicitar una
  tasa. No se modificaron reglas de rentabilidad, contratos, SQL ni permisos.
- Se actualizaron las pruebas existentes del panel para rechazos, solicitudes
  activas, ausencia de tarjeta y conservación del foco al resolver la última.

## Verificación del 16/09

- **PASS:** 19 pruebas específicas del panel, registro de respuestas y proveedor.
- **PASS:** `npm run check`, 248 archivos / 3.659 pruebas con cobertura; lint,
  TypeScript, configuración de release, service worker, build, bundle y duplicación.
- **PASS:** `npm run test:e2e -- e2e/respuestas-tasa.spec.ts`, cuatro recorridos
  Chromium: aprobación, rechazo/tope, lectura, sonido, dos pestañas, permiso
  denegado, caída de red y salida de sesión. Backend y notificación del sistema
  simulados; no acredita recepción física en la PC del analista.
- **NOT RUN:** `npm run gate:realidad` no inició sus lecturas: falta
  `SUPABASE_URL` en la sesión (salida 2). No se acredita ese gate integral;
  el prerrequisito SQL se comprobó por separado mediante lectura productiva.
- Cambio local de presentación, LEVEL 1; sin revisión secundaria.

## Estado de entrega

Miguel autorizó la publicación mediante `$release-crm` y confirmó la aprobación
en GitHub. **PUBLICADO en https://crm.miavance.com/** y verificado el 16/09/2026
a las 17:47 Lima (22:47 UTC).

| Dato | Versión efectivamente publicada |
| --- | --- |
| Commit de fuente | `4c2fe9e4418186504968d6f32fce925a3b773834` |
| Artefacto | `crm-20260916T223631Z-4c2fe9e44181.zip` |
| SHA-256 del ZIP | `1e01e493b32d9d058bf8038875a0cc2cb1a69be55f46e8f2b088d4ec1c019d19` |
| Build servido | `build-20260916T223630431Z` |
| Fuente | Main limpio, idéntico a `avancecorp/main` antes de construir y subir |

El [PR #7](https://github.com/avanza-digital/avancecorp-crm/pull/7) quedó
`APPROVED` y `MERGED` a las 22:31 UTC. Se respetaron las protecciones de GitHub.
El candidato `e01b4718a77a26579470b8ea1918c0808d862892` permanece en la rama
de corrección `fix/rechazos-tasa-jornada`; la implementación inicial se conserva
en `9e994a4f`. El commit integrado y el candidato probado tienen exactamente el
mismo árbol Git: `8b364bccc50789635646bc2782a01fe1ef3af0a4`.
Se reutilizó esa evidencia de pruebas y se construyó el paquete definitivo
desde el commit integrado. Se usó el Main existente en
`/private/tmp/avancecorp-gestion-worktree`; no se creó rama de release ni worktree.

- **PASS:** gate completo repetido en el candidato de Main; frontend idéntico
  al de los cuatro E2E focalizados. GitHub `verify` y `e2e` PASS en el
  [run 35156052244](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35156052244).
- **PASS:** `npm run release:crm` y `npm run release:crm:verify`, incluidos
  configuración productiva, bundle, ZIP y manifiesto de fuente limpia.
- **PASS:** requisito de Facturación para supervisores, ya incluido en Main:
  migración `20260916205617` registrada y `crm.facturacion_diaria_fn(date)` con
  md5 `79d75db2f7457035a804b32464f4caca`, dueño `postgres`, search path vacío y
  sin ejecución para `anon`, en `dctqcbznekcyxhjujuci`. Consulta de solo lectura;
  no se aplicó SQL durante esta publicación.
- **PASS:** publicación con el servidor oficial Hostinger,
  `hosting_deployStaticWebsite`, dominio `crm.miavance.com`, ZIP local verificado
  y `removeArchive: false`. Subida correcta y despliegue `Request accepted`.
- **PASS:** verificación HTTP posterior, 93/93 comprobaciones. Portada, HTML,
  versión, JS, CSS y demás archivos no transformados: 81 con bytes idénticos
  al manifiesto. Once imágenes respondieron HTTP 200 como imagen, con bytes
  transformados por el hosting; no se declaran idénticas. `.htaccess` protegido.
- **NOT RUN:** revisión visual productiva; Browser no tiene navegadores conectados.

ZIP, manifiesto, recibo saneado de Hostinger y resultados HTTP se conservan en
`CRM-Avance-Corp/releases/`, con el prefijo
`crm-20260916T223631Z-4c2fe9e44181` y extensiones `.zip`, `.manifest.json`,
`.hostinger.json` y `.http.json`. También se conserva el registro operativo en
`_dev_artifacts/rechazos-tasa-jornada/avancecorp-tasas-release-state.json`.

Recuperación preservada: `crm-20260916T182804Z-14be1e0581d8.zip`, SHA-256
`4178865fd0ecc1247019005d7897ca4df3b3eb0fd076e2737c9f3f29a836981d`, junto
con su manifiesto. Esa versión coincidía con la web antes de publicar (93
comprobaciones HTTP PASS). Esta acta posterior no cambia el commit de fuente
del paquete publicado ni requiere otra publicación.

## Cierre de sesión

Miguel pidió guardar todo y cerrar el 16/09/2026, a las 18:01 Lima. El cambio
está publicado; se conservan el acta, las pruebas, el paquete y la recuperación.
La revisión visual y el gate integral de realidad conservan los límites
declarados arriba. Este cierre documental no vuelve a desplegar el CRM.

Relacionadas: [[Alertas de respuestas de tasa para analistas - 2026-09-11]],
[[Notificaciones de tasa - publicadas 2026-09-11]], [[Inicio]].
