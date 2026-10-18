# Analista - PWA con navegacion inferior (2026-10-15)

## Decisión de Miguel

Llevar al Analista las mejoras PWA existentes de Gerencia, respetando su vista y ámbito personal. Accesos elegidos: **Mi día · Gestión Diaria · Agenda · Más**.

La confirmación «Funciona en ambos» dada en Android e iPhone al comienzo de esta sesión se refería a **Gerencia**. No acredita todavía la nueva vista de Analista.

## Implementación

- `NavegacionMovil` comparte el comportamiento existente por rol y consume los destinos autorizados de `Sidebar`.
- Analista mantiene su pantalla personal y recibe pendientes prioritarios, filtros móviles, aviso de desconexión, ajuste al teclado, márgenes seguros y actualización aplazable.
- Agenda móvil separa las acciones de los datos de cada tarea para que el título y el importe sean legibles.
- Los filtros de Pendientes se conservan por sesión también al cambiar a escritorio; allí se muestran completos y se pueden limpiar. Es una decisión para mantener la consulta al rotar o ampliar la ventana.
- Los nuevos ajustes de controles y estilos de pendientes se limitan a Analista para preservar la presentación de Gerencia.
- Sin cambios de permisos, datos, migraciones ni suscripciones push. Configuración sigue habilitada para el calendario propio del Analista.

Se aplicó **ECC `frontend-patterns`**. La revisión independiente se resolvió con evidencia y pruebas del PRIMARY.

## Publicación y comprobación

**Publicado en https://crm.miavance.com/ el 15/10/2026 (Lima)**, después del merge de Miguel en [PR #305](https://github.com/avanza-digital/avancecorp-crm/pull/305) y sus controles aprobados.

- Commit publicado: `94ef6886b50d0734a29fff57c10d268680aaed9d`.
- Build: `build-20261016T023049819Z`.
- Artefacto: `crm-20261016T023050Z-94ef6886b50d.zip`.
- SHA-256: `ee4c53b5783645ea764a710eefab563770a5c94a0729e75c1eabff7520b557f9`.
- Main local y `avancecorp/main` coincidían; construcción desde fuente limpia, preflight PASS y publicación por Hostinger MCP.
- `npm run check` PASS y repetición con dependencias del lockfile: 6976 pruebas en 434 archivos.
- E2E completo Docker: **436 PASS / 0 FAIL / 26 SKIP**, dos workers, cero reintentos, 18,8 min.
- Postflight: **126 archivos HTTP 200 con SHA-256 exacto**; versión viva coincide. Acceso al login móvil y escritorio PASS en navegador limpio, sin errores JavaScript ni desbordamiento.

Acta detallada: `CRM-Avance-Corp/docs/encargos/2026-10-15-publicacion-pwa-analista.md`. Implementación: `CRM-Avance-Corp/docs/encargos/2026-10-15-pwa-analista.md`. Evidencia local en `CRM-Avance-Corp/output/pwa-analista-20261015/`.

La comprobación de Analista instalado en teléfonos físicos queda pendiente. No confundir las pruebas Docker ni la simulación de teclado con una validación física.

Se conserva el ZIP anterior `crm-20261016T002735Z-d1796dd4cf8c.zip` y su manifiesto, con SHA-256 `956e504ee7790ab912cf789a27a7e1ae36697dd2507e1c3c043d549a2d2d3cc6`. No se efectuó rollback.

## Cierre de sesión

Miguel pidió guardar la entrega y limpiar los temporales. El código está en Main por el PR #305; acta y evidencia señalan el commit realmente publicado aunque Main avance después solo con notas. La memoria está enlazada desde Inicio.

Respaldo local: `CRM-Avance-Corp/output/pwa-analista-20261015-respaldo-cierre.tar.gz`, con manifiesto SHA-256 contiguo. Informe de limpieza: `CRM-Avance-Corp/output/pwa-analista-20261015/cierre-limpieza.json`. Se conservan las pruebas, capturas y los paquetes publicado/anterior. Los trabajos de otras tareas se mantienen en el árbol original; no usar una limpieza global del repositorio para cerrar esta PWA.

Siguiente comprobación: Analista instalado en Android e iPhone físicos.

## Relacionadas

- [[Gerencia - Plan de cierre PWA y acceso a Gestion Diaria (2026-10-05)]]
- [[Gerencia - Cuatro mejoras PWA implementadas en local (2026-10-06)]]
- [[Gerencia - Navegacion inferior movil en vista previa (2026-10-05)]]
- [[Hoy del analista - leads recibidos hoy (2026-10-05)]]
