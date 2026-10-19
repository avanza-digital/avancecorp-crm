# Recorrido del lead por hechos · ejecución del goal

Objetivo íntegro: implementar las ocho fases del [plan FigJam](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=17-117), hasta PR integrado en Main y ZIP verificado, sin publicar ni activar producción. Documento adjunto del usuario leído el 18/10/2026.

## Estado

| Fase | Estado | Evidencia / siguiente acción |
|---|---|---|
| 1. Contratos | PASS documental | FASE-1-CONTRATO.md y REVISION-ARQUITECTURA.md; revisión Claude evaluada y corregida por Codex. No implica runtime validado. |
| 2. Evaluación | PASS local | FASE-2-VERIFICACION.md: replay limpio + hardening, SQL/RLS, concurrencia, carga, tipos y typecheck. |
| 3. Cierres/oficina | PASS local | FASE-3-VERIFICACION.md: RPC, formulario compartido, idempotencia, SQL, concurrencia y 67 tests. Entrada desde ficha en fase 4. |
| 4. Guía | PASS local | FASE-4-VERIFICACION.md: 469 tests, a11y corregido, foco Radix, typecheck/lint/build. |
| 5. Conversión | PASS local | FASE-5-VERIFICACION.md: SQL, replay, concurrencia, cartera, 161 UI + 16 Edge, revisiones corregidas. |
| 6. Validación | PASS local | FASE-6-VERIFICACION.md: 79 HTTP, 467 E2E + 26 omitidos, regresión final 41/41 y gate integral 7.314 tests. Hosted/advisors antes de instalación productiva. |
| 7. PR/Main | EN CURSO · 3/5 | [PR #331](https://github.com/avanza-digital/avancecorp-crm/pull/331), tres hallazgos corregidos y revalidados. FASE-7-REVISION-PR.md. Pendientes integración y paridad Main. |
| 8. ZIP | PENDIENTE | Artefacto desde commit verificado, SHA-256 y manifiesto. |

## Entorno

- Base de partida: Main y avancecorp/main `6ace3d441bd874a1e06613ee5718b1023e08c39d`, verificados al iniciar.
- Copia limpia existente: `/private/tmp/hoy-supervisor-goal-20261018/candidato-main`.
- Rama de implementación: `feat/recorrido-lead-hechos-20261018`.
- El taller original contiene cambios ajenos; no se cambiaron de rama ni se incluyeron.
- Banco propio: `/private/tmp/recorrido-lead-hechos-20261018/stack`, puertos 58520–58529.
- Docker disponible. Producción consultada únicamente con transacciones READ ONLY.
- Crear una rama Supabase fue rechazado por falta de confirmación de costo. No se creó recurso remoto ni se confirmó un gasto. Se avanza en el banco local y se resolverá ese requisito antes del gate remoto.

## Límites de autorización

No ejecutar publicación, migraciones de producción ni activación de bloqueos. No instalar n8n. El usuario autorizó implementar el plan completo, incluyendo pruebas aisladas, PR, integración en Main y ZIP. Cada fase registra revisión de Codex, pruebas y resolución de hallazgos antes de avanzar.

## Comprobaciones iniciales

- PASS: objetivo leído y alcance preservado.
- PASS: Main remoto coincide con la copia limpia; rama propia creada desde ese commit.
- PASS: inventario de funciones/ciclos de producción por lectura del catálogo.
- PASS: Docker responde.
- PASS: fase 2 en banco propio; seis grupos de oráculos SQL, cuatro escenarios concurrentes, carga sintética y typecheck.
- PASS: guía, protección de conversión, HTTP real y E2E local del cambio. NOT RUN: advisors hosted, instalación y activación productiva; límites y requisitos en INSTALACION-Y-ACTIVACION.md.

## Seguimiento visual

[Avance con barras, fases y subfases en el mismo FigJam](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=46-190). Los porcentajes representan subfases verificadas; no tiempo estimado. Seis de ocho fases cerradas tras el gate local de fase 6; producción sin modificar.
