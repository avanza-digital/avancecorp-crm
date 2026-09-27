# F6 — UX gerencial publicada y verificada

**PASS — 25/09/2026, 05:14 Lima.** La UX/UI horizontal de gerencia está
servida en [crm.miavance.com](https://crm.miavance.com). Conserva las cifras y
permisos de F5, el selector de fecha y el recorrido operación → equipo →
analista → registro → ficha. La cola completa de F6 también permanece publicada.
La retirada de Seguimiento sigue pendiente de observación real estable.

## Autorización y fuente

Miguel autorizó expresamente publicar F6 mediante `release-crm` desde
`f9196dba908fab4a28048e43ceab2c1284156cee`, aceptando la integración manual del
[PR #101](https://github.com/avanza-digital/avancecorp-crm/pull/101) para esta
publicación. No se atribuye una revisión APPROVED en GitHub ni una excepción
general para otros PR. [Autorización registrada](autorizacion-f6.json).

El acceso Hostinger se recuperó con la credencial nueva proporcionada por el
usuario y guardada en el Llavero; su valor no forma parte de esta evidencia.
Antes del despliegue se comprobó árbol limpio, Main local igual a
`avancecorp/main` y el artefacto construido desde ese commit.
[Preflight](preflight-f6-autorizada.json).

## Artefacto y recuperación

| Dato | Valor |
| --- | --- |
| Fuente publicada | `f9196dba908fab4a28048e43ceab2c1284156cee` |
| Build | `build-20260925T054322011Z` |
| ZIP | `crm-20260925T054322Z-f9196dba908f.zip` |
| Tamaño y contenido | 2.320.539 bytes; 117 archivos |
| SHA-256 ZIP | `e6c17b3b8084c154137160aef01c0f0ed49c93d1984261f3e2986e90f3f4ffeb` |
| SHA-256 manifiesto | `353460dac8a118557cc31224eadd8e48c7bfeed776c9c9cfbf477eeb10400af6` |
| Recuperación anterior | `crm-20260925T041520Z-3027028d7c97.zip` |
| SHA-256 recuperación | `b07b1379ea590face22d905517c4493c3a949d107722a0744c332b0f804a0421` |

ZIP y manifiestos se conservan en el checkpoint local de F6, carpetas
`release-main101/` y `rollback-main100/`. El respaldo anterior se cotejó antes
del despliegue: **80/80 PASS** (79 HTML/JS/CSS y `version.json`).
[Comprobación previa](rollback-previo-f6-autorizada.json). No se ejecutó reversa.
Esta publicación no promueve SQL, Edge Functions ni cambios de RLS.

## Verificación

| Control | Resultado y alcance |
| --- | --- |
| Código de la app | Idéntico al probado en `4a4cb1ec`; Main y head del PR con el mismo árbol |
| Gate integral y revisión | PASS: 4.421 pruebas / 298 archivos; revisión independiente final PASS, dos consultas usadas |
| E2E locales en Docker | Chromium 270 PASS / 0 FAIL / 26 omisiones previstas; WebKit 10 PASS / 0 FAIL; sin reintentos |
| GitHub | PR #101 y Main `f9196dba`: tres controles PASS en cada uno |
| Artefacto | `release:crm:verify` PASS de nuevo antes de publicar; SHA-256 exacto |
| Hostinger | Subida correcta y despliegue aceptado a las 05:13:56 Lima |
| Archivos servidos | **81/81 PASS** por HTTPS, byte a byte: 80 HTML/JS/CSS y `version.json`, 05:14:43 Lima |
| Recorrido real posterior | **8/8 PASS** en la sesión de gerencia, hasta las 05:18:38 Lima |

Los gates locales se reutilizan porque el código publicado es idéntico al
probado; no se presentan como ejecuciones nuevas. [Validación técnica](VALIDACION.json),
[CI y fuente](pr101-integracion-y-ci-main.json),
[recibo Hostinger](hostinger-deploy-f6.json),
[hashes servidos](frontend-f6-publicado-verificado.json) y
[recorrido productivo](smoke-f6-produccion.json).

El recorrido comprobó fecha 24/09, comparación de cuatro equipos, detalle
lateral, equipo → analista → registro, carga de 25 a 40 gestiones, apertura de
ficha y regreso conservando las 40 filas y la fecha. También se verificaron
hábitos de 14 días, vista estrecha, escritorio de 1440 × 900 y regreso a Hoy.
Se usaron acciones de lectura: no se crearon registros ni se reconocieron o
aplazaron avisos reales para probar. La evidencia guardada contiene agregados,
sin nombres, identificadores de personas ni capturas de registros productivos.

## Plan y pendientes reales

El [mismo Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=2-122)
marca terminada la integración UX/UI de gerencia y conserva abiertos los cinco
puntos de observación y retirada. [Lectura del cambio](figma-publicada.json) y
[captura inspeccionada](figma-publicada.png), sin recortes de texto.

T0 permanece en **24/09/2026, 21:57:11 Lima**. Esta publicación y su smoke son
controles puntuales; no acreditan otro día ni reinician el período.
La retirada requiere siete días reales estables, **no antes del 01/10/2026 a
las 21:57:11 Lima**, y las pruebas del alcance final. El corte único del sábado
26/09 a las 11:30 sigue NOT RUN. [Observación](../OBSERVACION-F3-F5.md) y
[preparación de la retirada](../PREPARACION-F6-2026-09-24.md).

El CLI productivo `gate:realidad` sigue NOT RUN por ausencia de variables
privilegiadas; no se confunde con las consultas SQL de lectura ya ejecutadas.
Sus límites y la corrección del esquema del control constan en
[VALIDACION-CONTROL-REALIDAD.json](VALIDACION-CONTROL-REALIDAD.json).
Esta acta no cierra F6 completo ni exige volver a publicar por documentación.
