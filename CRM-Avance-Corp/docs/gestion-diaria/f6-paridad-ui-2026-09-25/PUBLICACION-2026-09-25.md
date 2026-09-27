# F6 — Corrección horizontal publicada y verificada

**PASS — 25/09/2026, 10:13 Lima.** La corrección del PR #103 está servida en
[crm.miavance.com](https://crm.miavance.com). Gerencia comparte la cabecera,
resumen y filtros de supervisión, mantiene ocho indicadores en una franja
compacta y conserva tabla y detalle lado a lado con el menú abierto en un
portátil. Pulso y Hábitos mantienen sus datos y acciones propios del rol.

Miguel autorizó expresamente publicar mediante `release-crm` tomando la
integración manual del PR #103 como aprobación, una vez terminado en verde
el control de Main. Se cumplió esa condición. GitHub no registra un review
APPROVED y esta excepción no se extiende a otros PR.
[Autorización](autorizacion-paridad-ui-pr103.json) y
[preflight de Main/CI/fuente](preflight-paridad-ui-autorizada.json).

## Artefacto y recuperación

| Dato | Evidencia |
| --- | --- |
| Commit publicado | `65e96df95511e683dfd39dc852ecd5e5312abc57` |
| Build | `build-20260925T150218036Z` |
| ZIP | `crm-20260925T150218Z-65e96df95511.zip` |
| Contenido | 2320890 bytes; 117 archivos |
| SHA-256 ZIP | `bf7351942b63599ee92531175ee45b696d5657035c843bd4f4839a437447e4ee` |
| SHA-256 manifiesto | `ca33d61d1937abf836e2173e1950b70baf117dbf1c0a76aea3c784919ccbffab` |
| Recuperación | `crm-20260925T054322Z-f9196dba908f.zip` |
| SHA-256 recuperación | `e6c17b3b8084c154137160aef01c0f0ed49c93d1984261f3e2986e90f3f4ffeb` |

El paquete se construyó desde Main limpio, idéntico a `avancecorp/main`.
`release:crm` y `release:crm:verify` pasaron; se reconfirmó fuente, huella y
versión servida inmediatamente antes de subir. Los ZIP y manifiestos se
conservan fuera del web root, en `release-main103/` y `release-main101/` del
checkpoint local de F6. [Resumen del artefacto](artefacto-pr103.json).

El respaldo anterior pasó su verificación de ZIP y el cotejo HTTPS de
81 archivos; portada y versión se cotejaron otra vez justo antes de publicar.
[Respaldo cotejado](rollback-previo-paridad-ui.json). No se ejecutó reversa.
La credencial existente del Llavero funcionó; no se pidió ni cambió un token.
[Acceso Hostinger](hostinger-listo-pr103.json). El mismo MCP de Hostinger realizó
la subida y extracción del paquete ya construido.
[Recibo](hostinger-deploy-pr103.json).

## Comprobaciones

| Control | Resultado real |
| --- | --- |
| Equivalencia de fuente | Árbol completo de Main idéntico al commit probado `e0a93306` |
| Gate local | PASS 4423 pruebas / 298 archivos, lint, tipos, cobertura, build y controles de release |
| E2E completos tras review | Chromium Docker 271 PASS / 0 FAIL / 26 omitidas, commit `14ed7336` |
| Ajuste móvil final | Gate repetido y E2E Docker Chromium 11/0 + WebKit 11/0, sin reintentos |
| Revisión independiente | CHANGES_REQUESTED; observaciones resueltas y comprobadas por PRIMARY; no se atribuye otro dictamen |
| GitHub | PR #103 y Main: tres controles PASS en cada uno |
| Archivos publicados | **81/81 PASS** por HTTPS, byte a byte: HTML/JS/CSS y `version.json` |
| Recorrido real | **9/9 PASS** en la sesión productiva de gerencia |
| CLI `gate:realidad` | **NOT RUN**, faltan variables privilegiadas; no se confunde con el recorrido de lectura |

Las pruebas locales se reutilizan por equivalencia del código; no se presentan
como nuevas ejecuciones. La suite completa precede a cuatro líneas de CSS
móvil, verificadas después con ambos motores y el gate integral.
[Resolución del review](RESOLUCION-REVISION.md), [evidencia técnica](ACTA.md),
[archivos servidos](frontend-pr103-publicado-verificado.json) y
[recorrido productivo](smoke-pr103-produccion.json).

El recorrido comprobó composición horizontal a 1366×768 y Hábitos a 1280×800,
ambos con el menú abierto; fecha 24/09, comparación completa y cierre con Escape,
filtro de atención, equipo con diez analistas, analista → registro de 25 a
40 gestiones → ficha y regreso conservando la fecha y las 40 gestiones.
En móvil a 390 y 320 px, los ocho valores permanecieron dentro de sus casillas
sin desbordamiento de página. Se restauraron Hoy, el menú y el tamaño de ventana.
Sólo se realizaron lecturas: no se crearon gestiones ni se reconocieron o
aplazaron avisos reales para probar. La evidencia versionada no contiene nombres o identificadores de clientes
o analistas, notas comerciales ni capturas productivas.

## Plan y alcance pendiente

El [mismo Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=2-122)
marca esta corrección publicada y conserva los cinco pendientes de observación
y retirada. [Cambio registrado](figma-pr103-publicada.json) y
[captura final inspeccionada](figma-pr103-publicada.png), sin texto recortado.

Esta entrega no cambia SQL, Edge Functions ni permisos. No modifica T0
**24/09/2026, 21:57:11 Lima**, no acredita otro día estable ni cierra F6 completo.
El corte único del sábado 26/09 a las 11:30 sigue pendiente. La retirada de
Seguimiento requiere siete días reales estables, sin incidencias relevantes
abiertas, y pruebas finales; nunca antes del **01/10, 21:57:11 Lima**.
[Observación](../OBSERVACION-F3-F5.md). F4.1 y la alerta de tasa muy baja siguen
apagadas. La conformidad humana anterior permanece cerrada.

Esta acta documenta la publicación de `65e96df9`; no exige publicar otra vez
por los cambios documentales posteriores.
