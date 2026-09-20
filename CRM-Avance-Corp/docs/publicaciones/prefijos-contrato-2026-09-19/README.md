# Numeración de contratos publicada

**PUBLICADO Y VERIFICADO el 19/09/2026.** Los analistas pueden seleccionar
`2024-01-`, `2025-01-` y `2026-01-`; el alta conserva 2026 como opción inicial
y seis dígitos manuales. El portal conserva estas series al editar.

- [Portal](https://miavance.com): publicado a las 22:32:13 UTC (17:32 Lima).
  Se actualizaron seis archivos: módulos primero, HTML después y service worker
  al final. Se usó TUS para actualizar esos archivos, sin sustituir el sitio entero.
- [CRM](https://crm.miavance.com): publicado a las 22:33:24 UTC (17:33 Lima)
  mediante `hosting_deployStaticWebsite`. Se purgó la caché de ambos sitios.
- **Guardar lo pendiente y actualizar las pestañas antiguas antes de operar
  con 2024/2025.**

## Fuente y artefacto

Main limpio y `avancecorp/main` coincidían antes de subir en
`4bd3dc1b5d1a71f60ec1abd6192f2dc92a4a1d3e`. Ese commit solo agrega actas respecto
del merge del [PR #31](https://github.com/avanza-digital/avancecorp-crm/pull/31).
Se construyó desde la copia limpia `/private/tmp/avancecorp-prefijos-main-218df5e3`.
Se preservó el trabajo ajeno del taller.

- Árbol app: `f0cec7e5e10a7a4c5ee1f609af22f1a5f2e734fa`, idéntico al código
  aprobado y al check local completo de 3.773 pruebas.
- Portal: `35198b14a8b70790faf55443ca6b1df95c70882e`, confirmado en su remoto
  y referenciado por Main.
- [ZIP publicado](../../../releases/prefijos-contrato-20260919/crm-main/crm-20260919T222832Z-4bd3dc1b5d1a.zip) y
  [manifiesto](manifiesto-crm.json).
- Tamaño: 2.199.941 bytes.
- SHA-256: `d22bbf92654be4a003491cb161160d9549a7d2b164cea76771a0ad74423f1c53`.
- [Parche del portal](../../../releases/prefijos-contrato-20260919/portal-parche-prefijos-35198b14a8b7.zip) y
  [orden y huellas](manifiesto-portal.json).

El paquete 0d1c1ae3 y las candidatas a030fb7b/766353c2 nunca se publicaron.
La fuente del despliegue es el commit del manifiesto anterior.

## Verificación

**PASS previo, mismo código:** `npm run check`, 3.773 pruebas en 254 archivos;
12 recorridos Chromium de contratos/historial y 104 pruebas del portal.
GitHub `verify`, `e2e` y `preflight` pasaron sobre el PR aprobado 218df5e3:
206 E2E remotos aprobados y 26 omitidos. La igualdad del código app/portal
permite reutilizar la evidencia tras incorporar las actas de Main.

**PASS desde Main 4bd3dc1b:** `release:crm`, `release:crm:verify`, configuración
productiva y 102/102 archivos del ZIP comprobados por tamaño y SHA-256.
[Evidencia](evidencia/verificacion-main-4bd3dc1b.json).

**PASS posterior:** portada, versión y todos los JS/CSS del CRM: 65 archivos
por HTTP 200 y SHA-256, incluido `assets/index-DEdo03gm.js`. Los seis archivos
del portal, incluidas las URLs v1/v29/v44 y SW v119, coinciden con sus huellas.
Chromium comprobó los tres accesos sin errores de página ni recursos fallidos.
El portal sin sesión redirige al acceso público; «Ingresa con tu correo» abre
el formulario de contraseña.

- [CRM servido](evidencia/crm-produccion-verificada.json).
- [Portal servido](evidencia/portal-produccion-verificada.json).
- [Acceso en navegador](evidencia/smoke-acceso-produccion.json).
- [Recibo del portal](evidencia/hostinger-portal.json) y
  [recibo del CRM](evidencia/hostinger-crm.json).
- [Estado estructurado](estado-release.json).

**Alcance:** el smoke productivo usó sesiones vacías; no creó, editó ni eliminó
contratos reales. La auditoría previa incluye 48 pruebas PDF, 14 comprobaciones
SQL locales y concurrencia. El banco SQL sintético no equivale a una réplica
de producción; `gate:realidad` no llegó a ejecutarse por falta de configuración.
No se aplicaron migraciones ni Edge Functions como parte de este release.

## Conexión y recuperación

Aunque la sesión solo anunciaba facturación, `hostinger-hosting` ya estaba
configurado. Se usó el servidor MCP oficial local instalado (`hostinger-api-mcp`
1.59.0) mediante stdio, con sus esquemas reales y el OAuth existente. No se
instalaron paquetes ni se cambiaron proveedor, DNS o configuración MCP.
Los recibos no contienen credenciales.

El último CRM publicado antes de este fue `crm-20260919T213432Z-4094df3c9224`,
conservado con su manifiesto en `recuperacion-crm/`. SHA-256:
`66ae91eba9a5905e9671e2a2dd3f891ea62938d4b4aeedfe9f650e68f6fc5bb4`.
Portada y JS principal se reconfirmaron por HTTP antes de subir.

`recuperacion-portal/` conserva los cinco archivos anteriores, también
reconfirmados antes de publicar. El portal anterior no conserva 2024/2025:
recuperarlo después de crear contratos con esas series requiere evaluar su
compatibilidad. [Comprobación previa](evidencia/hostinger-preflight.json).

Los manifiestos, esta acta y las verificaciones están versionados. Los ZIP,
respaldos y capturas se conservan en `CRM-Avance-Corp/releases/prefijos-contrato-20260919/`,
excluida de Git por las reglas del repositorio. Los enlaces a ZIP requieren
los archivos locales de esa carpeta.
