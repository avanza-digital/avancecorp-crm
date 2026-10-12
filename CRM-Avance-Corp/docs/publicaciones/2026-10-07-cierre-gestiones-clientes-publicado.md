# Cierre de tareas de clientes: publicación verificada

## Estado final

**PUBLICADO en [crm.miavance.com](https://crm.miavance.com)**. Hostinger confirmó la
entrega el **07/10/2026 04:55:39 UTC** (06/10, 23:55:39 en Lima). Verificación HTTP
completada el 07/10 a las 05:10 UTC. La comprobación visual la realiza Miguel.

En **Cartera → ficha de cliente → Seguimiento → Cerrar tarea**, el analista registra
el resultado de la gestión. Agenda conserva el cierre. Registro, resumen de
gestiones y control de citas permiten supervisar los resultados según permisos.
Una cita agendada o confirmada no se cuenta como entrevista realizada: requiere
registrar asistencia. Se conserva la distinción entre autor y responsable.

| Identificación | Valor |
| --- | --- |
| Commit publicado | `3bdfded2c8130a3e8843d5320516f4691de933f3` |
| Build servido | `build-20261007T045430720Z` |
| Fuente | Main limpio de la copia aislada, igual a `avancecorp/main` antes de enviar |
| Artefacto | [crm-20261007T045431Z-3bdfded2c813.zip](../../releases/crm-20261007T045431Z-3bdfded2c813.zip) |
| Manifiesto | [Archivo verificado](../../releases/crm-20261007T045431Z-3bdfded2c813.manifest.json) |
| SHA-256 ZIP | `053780737f010276acda83b6d6cf8c035ac4e3f947e179ff820eaf9f593afafd` |

## Conservación de lo que estaba en producción

El commit anteriormente publicado, `dfb8874d534bc6462432dee00298f022e4437a0b`,
es **ancestro del Main final**. Se conservaron su corrección del capital renovado
y los cambios de Main, incluidas #207, #208, #209 y #210. El árbol de aplicación
publicado es idéntico al probado en `e255e96d`:
`3ea20c6848873b977d95146fccdddd72a52162dc`.

La PR #212 había quedado integrada mediante squash y no conservaba esa ascendencia.
Se detectó antes de publicar. La [PR #213](https://github.com/avanza-digital/avancecorp-crm/pull/213)
resolvió la reconciliación con un merge real, aprobado mediante la confirmación
explícita de la acción administrativa puntual. Padres: `89138f73` y `3fa430cb`.
No se cambiaron reglas globales de GitHub, ni el preflight, ni se forzó el historial.
Después se reconstruyó el ZIP desde el Main final, sin reutilizar la identidad de
un candidato anterior. El taller compartido y sus cambios ajenos se conservaron.

El wrapper volvió a verificar Main remoto y ejecutó el preflight oficial
**inmediatamente antes del envío**, a las `2026-10-07T04:55:26.519Z`. PASS.
Hubo una sola publicación del paquete final; no se purgó caché ni se cambió DNS/CDN.

## Verificación

| Control | Resultado |
| --- | --- |
| `npm run check`, código de producto `e255e96d` | **PASS**: 392 archivos / 6.286 pruebas; lint, tipos, build, configuración, bundle y duplicación |
| Equivalencia de app entre `e255e96d` y Main final | **PASS**, árbol idéntico; cambios adicionales de reconciliación son actas |
| Docker local: cierre, Agenda y supervisión, ocho specs en `ad111817` | **PASS**: 43 aprobadas, 13 omitidas, cero fallos/retries |
| Docker local: delta posterior #210, F5 completo en `e255e96d` | **PASS**: 13/13, cero fallos/retries; no sumar como casos distintos a la fila anterior |
| SQL #207 productivo, postflight de solo lectura | **PASS**: `2026-10-07T04:45:14.151431Z` |
| `release:crm` y `release:crm:verify`, Main final | **PASS**, fuente limpia y SHA verificada |
| Reconciliación, ancestro vivo y preflight inmediato | **PASS** |
| Hostinger: upload y deploy | **PASS**, respuesta `success` en ambas operaciones |
| Smoke HTTP del frontend | **PASS**: portada, versión, 110 JS y 6 CSS, HTTP 200 y bytes/SHA exactos |
| Accesibilidad HTTP de los archivos públicos | **PASS**: 154/154 respuestas HTTP 200 |
| Comparación literal ampliada de los 154 archivos | **FAIL literal**, limitado a diez PNG transformados por CDN; detalle abajo |
| Revisión visual productiva por Codex | **NOT RUN**: Miguel indicó que la realiza él |

Las migraciones de #207 ya estaban instaladas y verificadas, con sus gates SQL,
SLA activo, matriz HTTP de 3.075 aserciones, permisos y conservación del historial.
Esta publicación de frontend no reaplicó SQL, no modificó Edge Functions y no creó
gestiones reales para probar. Claude revisó la reconciliación con **PASS**;
sus observaciones de reconstruir desde Main y repetir preflight fueron atendidas.

### Observación de imágenes de Hostinger

La comparación HTTP estricta encontró 144 archivos idénticos y diez PNG distintos.
Los diez originales dentro del ZIP final son idénticos a los del ZIP anterior.
Se obtuvieron nueve originales por HTTP con `x-hcdn-cache-status: BYPASS` y su
SHA coincidió. `aliados/ntc-agency.png` siguió llegando desde CDN redimensionado
de 3508×3253 a 1600×1484; su igualdad binaria con el original **no quedó acreditada
por HTTP**. La imagen responde 200. Se conserva el FAIL literal del ensayo inicial.

El comportamiento observado es compatible con la optimización de ancho y calidad
que documenta [Hostinger](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/)
y con sus [estados de caché](https://www.hostinger.com/support/how-hostinger-cdn-caching-works/).
La atribución a esa transformación es un diagnóstico basado en las cabeceras,
dimensiones y nueve originales recuperados. No se alteró la configuración del
hosting para conseguir una coincidencia. El gate requerido de HTML/JS/CSS y versión
está aprobado; esta limitación se conserva en el informe ampliado.

## Llamadas desde el celular

`LLAMADAS_CELULAR_APROBADAS = false` permanece. El registro manual de llamadas y
Deshacer siguen disponibles. La integración automática del celular se activará
cuando su responsable complete y verifique el backend de #190; esta entrega ya
permite cerrar y supervisar las tareas de clientes sin esperar ese trabajo.

## Recuperación y evidencia

Se conserva el paquete anteriormente publicado:
[crm-20261007T034649Z-dfb8874d534b.zip](../../releases/crm-20261007T034649Z-dfb8874d534b.zip),
con su manifiesto. SHA-256:
`47070ef4c08e5f1e3c1d5cc371abfcbc208d07fcbce9f5ba5ec6571b73565ca2`.
Un rollback requiere decisión de Miguel y conserva resultados, recibos e historial;
no se elude automáticamente el preflight para publicar un commit anterior.

- [Estado final y smoke](../../app/artifacts/gestiones-clientes-publicacion-final.json).
- [Procedencia, padres y equivalencia](../../app/artifacts/gestiones-clientes-main-final-procedencia.json).
- [Confirmación de Hostinger](../../app/artifacts/gestiones-clientes-hostinger-publicacion.json).
- [Preflight inmediato](../../app/artifacts/gestiones-clientes-final-preflight-inmediato.json).
- [HTTP literal de 154 archivos](../../app/artifacts/gestiones-clientes-smoke-publicado.json).
- [Comprobación adicional de imágenes](../../app/artifacts/gestiones-clientes-imagenes-origen.json).
- [Build del Main final](../../app/artifacts/gestiones-clientes-main-reconciliado-release.log).
- [Estado completo del encargo](../../app/artifacts/gestiones-clientes-independiente-estado.json).

Esta acta documenta la entrega realizada. No cambia el commit del manifiesto ni
requiere otra publicación.

## Cierre de recursos locales, 07/10/2026

Miguel pidió cerrar lo que ya no se necesita. Se cerraron mediante SIGTERM la vista
local del puerto 5197 y su backend de ejemplo del 59999, verificando previamente
PID, comando, fecha de inicio y puerto. Ambos puertos quedaron libres y el proceso
NPM padre terminó. No había pestañas locales de esta entrega abiertas. Se conservan
los paquetes, respaldos y evidencias, además de las pruebas y bancos de otros trabajos.
Esta limpieza no ejecutó ninguna operación en producción.

[Evidencia de cierre](../../app/artifacts/gestiones-clientes-cierre-local-20261007.json).
