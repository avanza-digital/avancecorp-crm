---
tags: [crm, github, publicacion, protecciones]
actualizado: 2026-10-19
---

# GitHub — checks ajenos retirados del CRM

**APLICADO y verificado el 19/10/2026 a las 11:08 de Lima.** Miguel ordenó retirar «Documentación», «ERP» y «Base de datos» al diagnosticar el bloqueo del PR #335. El alcance es el CRM, conservando el resto de protecciones y los demás repositorios.

## De dónde venían

La regla de organización `proteccion-main`, id `20216285`, fuente `avanza-digital`, se aplicaba a `~ALL` los repositorios y sus ramas predeterminadas. Creada el 01/08/2026 a las 22:08 de Lima, última actualización anterior al ajuste el 17/10 a las 20:35. Incluía esos tres checks, que no están definidos en los workflows del CRM. No se añadieron con el cambio de ficha.

## Cambio aplicado

1. Se creó y releyó la regla activa `comprobaciones-proyectos-excepto-crm`, id `25416858`, con los mismos tres checks y los mismos parámetros/actores de la original. Conserva `~ALL` y excluye exactamente `avancecorp-crm`.
2. Después de verificarla, se retiró solamente `required_status_checks` de la regla general `20216285`. Permanecen sin cambio borrado protegido, bloqueo de push forzado, historial lineal y PR con una aprobación, code owner y descarte de aprobaciones obsoletas.
3. `crm-backend-preflight-obligatorio`, id `24459428`, conserva `preflight` de GitHub Actions (app 15368), rama Main actualizada y ningún bypass.

El orden mantuvo protección continua: primero duplicó los checks de los demás proyectos y luego retiró la copia de la regla común. No se desactivaron reglas, se autoaprobó el PR ni se fusionó como administrador.

## Verificación real

- Claude SECONDARY_REVIEWER: PASS; dos notas P3 sobre renombrado y default `protected`, atendidas mediante documentación y comparación de respuesta real. Codex verificó el resultado.
- CRM: los tres contextos retirados no aparecen en las reglas efectivas de Main; la regla nueva tampoco se aplica al CRM. `preflight` y una aprobación siguen requeridos. Resto de parámetros idénticos.
- Otros cinco repositorios: comparación de todas las reglas efectivas antes/después PASS, incluidos parámetros y atribución de la nueva regla. `cliente-clinica-alvarez`, `avanza-platform`, `avancecorp-portal`, `Academia-Phoenix`, `belysh-sistema-gestion`.
- Protección clásica de branch: 404, no existe una segunda exigencia clásica oculta. La protección está en los rulesets activos.
- Hubo un timeout TLS durante una lectura posterior a la escritura; no se repitió la mutación. Se ejecutó un verificador exclusivamente GET y completó todos los contrastes PASS.
- PR #335: CodeRabbit SUCCESS; Actions todavía `queued` y `REVIEW_REQUIRED` al cierre de la comprobación. Retirar estos checks no equivale a aprobar ni publicar la ficha.

## Continuidad y reversa

Si se renombra `avancecorp-crm`, actualizar su exclusión en `25416858`. La condición y los actores permitidos de la regla de checks deben conservar equivalencia con la regla general para los demás proyectos.

Para deshacer: **primero** restaurar las `rules` originales en `20216285` y verificar; **después** retirar la regla nueva `25416858`. Así no hay intervalo sin protección para otros proyectos. No ejecutar una reversa sin una necesidad autorizada.

Auditoría, originales, payloads, recibos, review y comparación final: `/private/tmp/crm-reglas-github-20261019/`. Copia conservada: `/Users/usuario/Downloads/CRM-reglas-GitHub-20261019/`.

Relacionadas: [[Conversion - ficha compacta preparada PR 335 (2026-10-19)]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].
