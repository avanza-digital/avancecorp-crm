---
tags: [crm, conversion, interfaz, publicacion]
actualizado: 2026-10-19
---

# Conversión — ficha compacta preparada

**Estado superado: PUBLICADA y verificada el 19/10 a las 11:56 Lima.** #335 y #336 fusionados; versión `ficha-compacta-6479402d-20261019`, Main `6479402d`. Acta vigente: [[Conversion - ficha compacta publicada (2026-10-19)]]. Esta nota conserva la preparación y los bloqueos históricos.

Miguel pidió retirar de «Antes de convertir a cliente» los textos «Deben corresponder a la misma cita de este ciclo. Cambiar de etapa no registra estos hechos», «Completa los dos requisitos para convertir a este lead» y el siguiente paso visible «Agendar una cita». También pidió una ficha menor y publicar exclusivamente este ajuste.

El [PR #335](https://github.com/avanza-digital/avancecorp-crm/pull/335) quedó fusionado el 19/10 a las 11:23 Lima, en Main `a1c103f8b680f1b6efd3ed3ce437982eec190241`. Retira dos párrafos, reduce relleno/separación y compacta el refresco. Conserva requisitos, estados, acciones y reglas de conversión. Solo cambia un componente de producto y adapta dos archivos de pruebas.

**Estado actual, 11:27 Lima:** el [PR #336](https://github.com/avanza-digital/avancecorp-crm/pull/336), commit `17130503e42c6806ed2ba9bcec368bc790648ba4`, corrige las dos observaciones de CodeRabbit que quedaron fuera de la fusión de #335 mientras se verificaban localmente. Solo oculta «Agendar una cita» cuando existe su botón; conserva visible «Asignar un analista» y las demás indicaciones. El refresco usa `any-pointer-coarse:size-11` para mantener 44 px también con ratón principal y pantalla táctil. Son dos líneas del mismo componente. PR abierto, comprobaciones remotas y revisión en curso; GitHub marca `REVIEW_REQUIRED`. **Todavía no publicado.**

## Verificación

- `npm run check`: PASS, 456 archivos y 7.316 pruebas, además de lint, tipos, cobertura, build, configuración, bundle y duplicación.
- E2E: 7/7 PASS en Docker local, repetido para las dos correcciones finales (17,8 segundos); incluye errores/refresco, oficina/reintentos, foco, cierre habitual, cita futura y permisos. Ninguna prueba escribe en producción.
- Las 7.316 pruebas y el gate integral también se repitieron con las correcciones finales: PASS. CSS construido: regla de 44 px bajo `any-pointer: coarse` confirmada. Evidencia: `check-correcciones.log`, `e2e-correcciones.log` y `verificacion-correcciones.json`.
- `gate:realidad`: NOT RUN completo por falta de credenciales de lectura en el entorno CLI. Consulta productiva de solo lectura mediante conector: `exigir`, revisión 2, inicio `2026-10-19T14:44:22.886326Z`.
- Revisión manual del navegador/VoiceOver: NOT RUN. Cambio LEVEL 1: no requiere nueva revisión de Claude.
- Base `avancecorp/main` y versión web viva `3797e6affbed` tienen el mismo árbol de `app` antes del parche. Diff del candidato contra esa versión: únicamente los tres archivos indicados.
- ZIP, SHA, fuente limpia y preflight de compatibilidad con lo publicado: PASS para la candidata inicial. Esa candidata no incluye las dos correcciones posteriores y no debe publicarse; hace falta reconstruir desde Main después de #336.

## Publicación pendiente

Pendiente vigente: cerrar la revisión y comprobaciones de #336, integrar sus dos correcciones, sincronizar Main local/remoto y generar/verificar/publicar el ZIP final. #335 ya está fusionado; las comprobaciones de su versión terminaron SUCCESS. Los párrafos siguientes conservan el diagnóstico histórico de los bloqueos previos.

**19/10 11:08 Lima: resuelto el bloqueo de checks ajenos.** Por orden de Miguel, «Documentación», «ERP» y «Base de datos» ya no se exigen al CRM. Se preservaron sus otras protecciones y se comprobó equivalencia en los otros cinco repositorios. [[GitHub - checks ajenos retirados del CRM (2026-10-19)]]. CodeRabbit terminó SUCCESS; Actions y la aprobación requerida siguen pendientes. El diagnóstico que sigue conserva el estado anterior a la corrección.

Actualización del diagnóstico, 19/10 ~11:00 Lima: Miguel actualizó la rama con Main a las 10:46 (`efafbfc0`, incorpora el acta documental #334 de Main `e3559f76`). El árbol `CRM-Avance-Corp/app` es idéntico al commit probado `71330d70`; la copia aislada quedó sincronizada por fast-forward. Las pruebas locales conservan su equivalencia. GitHub reporta incidencia activa en Actions/Pages/Webhooks desde las 10:49: https://www.githubstatus.com/api/v2/summary.json (incidente `8tzbpcnl75jp`). En el head nuevo, los jobs aparecen `queued`, sin runner ni pasos, y CodeRabbit sigue procesando la nueva revisión. No atribuirlo a fallo del ajuste visual ni reiniciar continuamente los jobs. CodeRabbit tuvo una incidencia de acceso/revisiones ese día, pero su componente Reviews figura operativo desde las 14:13 UTC; no afirmar que sigue caído.

Hay además una discrepancia de configuración que debe evaluarse por separado: la regla activa de organización `proteccion-main` (id `20216285`, fuente `avanza-digital`) exige `Documentación`, `ERP` y `Base de datos`, nombres no definidos en los workflows actuales del CRM. Exige también una aprobación. La regla específica `crm-backend-preflight-obligatorio` (id `24459428`) exige `preflight`. La demora de ejecución y el bloqueo de fusión son distintos; que termine la incidencia no garantiza que esas condiciones queden satisfechas. No se cambió ninguna protección global ni se añadió este ajuste de configuración al PR visual.

GitHub marca `REVIEW_REQUIRED`: exige una aprobación de otro revisor. Los controles remotos están pendientes. El intento de habilitar fusión automática fue rechazado porque no está permitida en este repositorio; no se cambió ninguna regla ni se usó fusión administrativa. Se solicitó gestionar la revisión; la autorización de Miguel para publicar ya existe y no se vuelve a solicitar.

La candidata de revisión **NO está publicada**. Copia: `/Users/usuario/Downloads/CRM-ficha-compacta-20261019/`, archivo `crm-20261019T154309Z-71330d70df84.zip`; SHA-256 `9c24f587c2423d5995abd065a8b5e9a4dfe7290a9e740f1cfc52ed53ce24e4af`.

Al fusionarse: sincronizar Main local/remoto, verificar que el código de pantalla solo contiene este ajuste, reconstruir desde ese commit, verificar manifiesto/preflight, publicar mediante Hostinger y comparar portada/versión/JS/CSS servidos. El publicador preparado exige Main limpio, sincronizado y un diff limitado a la ficha y sus pruebas.

Trabajo aislado: `/private/tmp/hoy-supervisor-goal-20261018/candidato-main`, rama vigente `fix/ficha-conversion-revision` (#336), basada en Main posterior a #335. Evidencia y herramientas preparadas: `/private/tmp/ficha-conversion-compacta-20261019/`; `hostinger-publicar.mjs` y `verificar-http.py` todavía no ejecutados. Antes de publicar, crear `candidato.json` con el manifiesto del nuevo artefacto de Main; `candidato-revision.json` identifica solo la candidata inicial de rama.

Relacionadas: [[Conversion - exigencia activa en produccion (2026-10-19)]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].
