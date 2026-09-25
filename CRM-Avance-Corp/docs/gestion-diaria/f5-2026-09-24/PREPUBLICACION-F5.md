# F5 — Autorización y preparación de publicación

24/09/2026. **Registro histórico de preparación. Publicación completada.**
El estado vigente, la autorización posterior y el respaldo inmediato están en
el [acta productiva](../f5-publicacion-2026-09-24/ACTA.md). Los bloqueos y el
paquete anterior descritos a continuación corresponden a momentos previos.

Miguel respondió: «Autorizar SQL F5 y $release-crm tras aprobación en GitHub».
La pregunta incluía también que los controles debían haber pasado. Se conserva
esa autorización para el SQL exacto y el frontend del [PR #94](https://github.com/avanza-digital/avancecorp-crm/pull/94),
sin volver a solicitarla. La revisión GitHub sigue su vía normal; no se autoriza
una excepción de administrador ni una autoaprobación.

- Producto probado: `e2c73d5b032d30269232443bcd2f8c5ebe69312a`.
- SQL: `20260924201358_crm_gestion_diaria_pulso_habitos.sql`, SHA-256
  `5f904c2b9b492b72fdb1ff1815aac2376d881939d6a8eaed938d1404380bf6b2`.
- Tope de ramas conservado: US$5 total en `fzxtxnkvslpcsscxqfbr`;
  estimación consumida US$0,019374, no factura. Ambas ramas anteriores eliminadas.
- GitHub al preparar esta acta: revisión requerida, sin revisiones aprobadas.
  Preflight PASS; el control integral del frontend estaba en ejecución.
  Consultar el estado del último commit antes de integrar.

## Preparación de recuperación

ZIP anterior conservado fuera de Git:
`CRM-Avance-Corp/releases/crm-20260924T161348Z-929fbbcccb57.zip`, manifiesto
contiguo del mismo nombre con extensión `.manifest.json`.
Fuente `929fbbcccb5710e1031f734a034e8ce90a79b0b2`, 116 archivos,
2.300.734 bytes. SHA-256 del ZIP:
`36892449306963561b85f5ed39ecc4fff6c48335aa72c6f7f140af5b59736991`.

**PASS:** integridad del ZIP y los 116 archivos contra su manifiesto. La
portada, JavaScript y CSS servidos coinciden con ese artefacto. Se consultaron
115 archivos públicos: 103 idénticos byte a byte y doce PNG con huellas
diferentes. `.htaccess` se verificó en el ZIP, no por HTTP.

Siete de esos PNG tienen exactamente los mismos píxeles y dimensiones; cinco
logotipos de 3.508 px se sirven con 1.600 px y proporción conservada. Es un
resultado compatible con la [optimización de imágenes documentada por Hostinger](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/),
que puede cambiar dimensiones/calidad. La configuración efectiva no se leyó,
por lo que no se afirma la causa como demostrada ni la igualdad byte a byte
de los doce PNG. Las respuestas llegaron con `Server: hcdn` y `Content-Type:
image/png`. Los bytes recibidos se conservaron en el checkpoint privado.

[Comparación HTTP](respaldo-frontend-actual.json) y
[comparación de píxeles/dimensiones](imagenes-publicadas-cotejo.json).
El FAIL de la primera comparación significa que no todos los bytes públicos
coinciden; no se convirtió en PASS ni se modificaron imágenes o la configuración
del sitio para ocultarlo. Revalidar versión, manifiesto y respaldo justo antes
de publicar, porque otra tarea puede publicar mientras se espera la revisión.

## Acceso de publicación — registro inicial

La habilidad [release-crm](../../../../.agents/skills/release-crm/SKILL.md) exige
el conector Hostinger y construir desde Main limpio, idéntico al remoto. En esta
sesión no está expuesta la operación `hosting_deployStaticWebsite`; el grupo
Hostinger disponible contiene operaciones de Agency, no el despliegue estático
del hosting normal. La búsqueda de plugins solo devolvió Hostinger Mail,
que no corresponde a esta publicación y no se instaló.

Una consulta de inventario al MCP configurado respondió HTTP 403; se detuvo
sin buscar otro token ni cambiar la conexión. Esto describe una limitación de
las herramientas actuales; no demuestra un fallo del sitio ni invalida la
autorización. Antes de subir, debe estar disponible la operación de despliegue
del conector. No se cambió proveedor, DNS, MCP ni se intentó una publicación.

## Orden restante

1. Obtener aprobación GitHub y PASS de los controles del último commit.
2. Revalidar Main y el SQL del padre. Recrear la rama temporal dentro del tope,
   cotejar el baseline vigente y el único delta F5; repetir controles afectados
   por cambios reales. Promover mediante merge nativo, nunca aplicación directa
   a producción. Verificar ledger, firmas, guardas, permisos y conciliación.
3. Integrar por la vía normal; hacer coincidir Main local y remoto. Construir
   ZIP/manifiesto desde ese commit limpio, cotejarlo y preservar el respaldo.
   Confirmar la disponibilidad del conector antes de la ventana de publicación.
4. Publicar con `$release-crm`, verificar portada y todos los JS/CSS, recorrido
   autorizado y cifras vivas. Registrar el commit y el artefacto reales.
5. Fijar T0 en [OBSERVACION-F3-F5.md](../OBSERVACION-F3-F5.md). Acumular siete
   días reales estables antes de retirar Seguimiento. El corte del sábado 26/09
   sigue siendo una verificación futura; no se marca cumplido por anticipado.

No se reconstruye ni publica otro frontend únicamente por añadir esta acta.

## Actualización: integración externa y acceso recuperado

Todos los controles de `9bde971f` terminaron PASS. GitHub registra que
`miguejbs98` integró el PR #94 el 24/09 a las 20:22:12 Lima en
`8da4bcf31039d0b0953e556c6eab5080ac1346c8`. Su árbol es idéntico al de
`9bde971f`; Main local de la copia autorizada y `avancecorp/main` coinciden.
La API de revisiones devuelve una lista vacía. Codex no ejecutó esa integración
ni una excepción de administrador. La condición explícita de revisión aprobada
sigue pendiente de resolución: el merge no se registra como revisión APPROVED.

Miguel autorizó recuperar Hostinger mediante token. Se guardó en el Llavero de
macOS y se comprobó con el servidor oficial `@hostinger/mcp@1.63.3`, instalado
fuera del repositorio con scripts de instalación deshabilitados. El proceso
recibe la credencial en memoria. No se incluyó su valor en archivos, actas,
configuración o commits; tampoco se modificaron MCP global, DNS ni el sitio.

**PASS:** initialize, inventario de 74 herramientas de hosting y disponibilidad
de `hosting_deployStaticWebsite` con su esquema real: `domain`, `archivePath`
y `removeArchive`. La consulta autenticada encontró exactamente
`crm.miavance.com`, habilitado, y pudo leer su index.html de 2.178 bytes,
que referencia `assets/index-D_95DKmo.js`. El bloqueo de acceso está resuelto;
el despliegue sigue NOT RUN. La consulta manual anterior al MCP remoto que
respondió 403 no utilizó OAuth almacenado: no acreditaba un fallo de la cuenta.

La revisión Endor del paquete quedó UNKNOWN: sin herramienta expuesta ni
`endorctl` instalado; no se atribuye una aprobación de seguridad. Fuente
oficial y versión comprobadas contra GitHub/npm. La evidencia sin secretos y
el cliente de lectura están en el checkpoint privado,
`hostinger-token-validacion.json` y `hostinger-local/`.

La lectura productiva posterior mantiene 355 migraciones y cero entradas
para `20260924201358`. Antes de SQL y frontend debe resolverse la condición
GitHub, preparar el artefacto exacto y ejecutar los controles de promoción
indicados arriba. No se atribuye el inicio de los siete días reales.

## Cierre posterior: autorización explícita y publicación

Miguel respondió «Sí, publicar F5 con esa integración». Autoriza usar la
integración externa del PR #94 para publicar SQL F5 y `$release-crm`; no la
convierte en revisión APPROVED. La publicación quedó verificada desde Main
`b402a7f1` el 24/09 a las 21:57:11 Lima, tras un nuevo ensayo remoto completo
y conciliación productiva. El respaldo inmediato fue actualizado a Main #93
`a1bbe24d`, conservando los cambios de la publicación paralela de venta cruzada.
La rama temporal posterior fue eliminada; coste estimado acumulado US$0,029838.
Los siete días de observación empiezan en ese T0 y siguen pendientes de cumplirse.
Evidencia y límites: [ACTA.md](../f5-publicacion-2026-09-24/ACTA.md).
