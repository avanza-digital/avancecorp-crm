# Gestión Diaria — plan vivo en Figma y mejora visual

Miguel pidió trasladar el mismo plan por fases y casillas presentado en el chat
a Figma y mantenerlo actualizado conforme avance el trabajo.

Tablero editable: https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L

Se crearon y comprobaron visualmente 76 puntos distribuidos en F0–F6,
incluyendo las seis etapas de F4 y F4.1. F0–F3 están publicados; F4 sigue en
etapa 6, con primera jornada del 24/09 y seguimiento del sábado pendientes.
No confundir pruebas técnicas con validación humana ni activar tasa baja antes de F5.

## Retoma — supervisor horizontal (23/09/2026)

Miguel aprobó un nuevo prototipo horizontal y pidió planificar su desarrollo.
El mismo tablero incorpora el [prototipo, seis fases y 24 etapas](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-2),
con 24 tareas H1–H2 completas, 48 de H3–H6 pendientes y las 76 casillas anteriores intactas. Cada fase tiene
objetivo, dependencia, entregable y criterio de cierre. Plan detallado,
revisión de Claude y referencia en
[[Gestion Diaria - supervisor horizontal aprobado (2026-09-23)]].
PR #85 ya fusionado en Main `e0bdfe12`; H2 está implementada en la copia aislada, sin publicación.

## Historial — sesión guardada el 23/09/2026

Miguel pidió guardar todo y continuar en otra sesión. Objetivo F4 pausado.
PR #82 publicado y PR #84 integrado. El [PR #85](https://github.com/avanza-digital/avancecorp-crm/pull/85)
guarda el acta y el plan; estaba abierto al pausar, con CI en curso. Comprobar
su estado antes de integrar, sin volver a publicar por cambios documentales.

Punto de trabajo: copia aislada `/private/tmp/avancecorp-release.hvdub4/repo`,
rama `codex/gestion-diaria-ui-acta`. El taller principal sigue reservado al
trabajo de la otra sesión; no mezclar sus cambios.

Los ZIP publicado (`crm-20260923T204458Z-e8e4f35f9ea1`) y de respaldo
(`crm-20260923T173451Z-8e6f4357feb1`), sus manifiestos y recibos saneados están
también en `CRM-Avance-Corp/releases/` del taller principal, fuera de `/tmp`:
diez archivos cotejados por SHA, sin sobrescribir contenido distinto.

Retomar con la validación productiva de analista y supervisor; luego registrar
la evidencia real del 24/09, cortes 11:30 y 16:00 Lima, y del sábado 26/09.
Mantener pendientes los puntos sin evidencia, los dos avisos INFO de índices
y el gate de realidad CLI. Tasa baja OFF hasta F5. No reinstalar SQL ni crear
actividad real ficticia. El mismo tablero de Figma ya muestra la publicación.

## Historial — cierre de H1

H1 se cerró con **4 etapas y 12 tareas** después del PR #85.
Base actual verificada `cf87e808` (#86), copia aislada, mismo tablero.
Al cerrar H1 quedaban H2–H6 y 60 tareas pendientes. Especificación de datos, geometría y
navegación registrada; H3.3 añadirá una RPC de lectura de tareas por analista.
Durante H1 no se implementó el rediseño ni se instaló SQL o publicó producto.
Detalle en [[Gestion Diaria - supervisor horizontal aprobado (2026-09-23)]].

## Continuidad del tablero

- Actualizar **este mismo archivo de Figma** al registrar cada avance verificado.
- Actualizar también `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
- Los IDs y el texto de cada punto están en `docs/gestion-diaria/FIGMA-PLAN.json`.
- Cambiar las casillas solo con evidencia; conservar PASS/FAIL/NOT RUN.
- Es una actualización durante el trabajo, no una automatización en segundo plano.

## Mejora visual solicitada

Miguel considera insuficiente la calidad visual de `Mi día` y `Mi equipo hoy`.
Prioriza **analista y supervisor**, y pide seguir el documento de fundamentos
UX/UI. **Implementada y publicada el 23/09** mediante PR #82. Se trabajó en la rama
`codex/gestion-diaria-ui` de la copia aislada existente, preservando la tarea
de la otra sesión.

- Analista: contacto activo y llamada con prioridad, dos paneles proporcionados,
  cola con selección clara y detalle progresivo.
- Supervisor: resumen comparable, búsqueda y filtros integrados en la tabla,
  acciones junto a cada analista, motivos de atención y vencidas legibles.
- Gate integral **PASS: 4.177 pruebas**; Docker **13 passed / 0 failed** después
  de integrar Main `88564677` (PR #80, tipos de producción). Se adaptó la
  expectativa E2E de filtros vacíos omitidos, sin modificar la API integrada.
- Entrega: [PR #82](https://github.com/avanza-digital/avancecorp-crm/pull/82), fusionado
  en Main `e8e4f35f9ea1bc1b88da469ff45a998d7d40bb91`. Gate final **4.179 pruebas PASS**.
  Build `build-20260923T204457952Z`, ZIP `crm-20260923T204458Z-e8e4f35f9ea1.zip`,
  SHA-256 `ab631a4fac25c53c3d32bd49514c99d92c6420dd2c9b92c1a823a88a46f22de6`.
  Los 114 archivos del origen coinciden; los 75 JS/CSS públicos también. El CDN
  transforma 11 PNG; diagnóstico e integridad registrados, sin cambiar Hostinger.
- El banco completo de release terminó 228 PASS / 6 FAIL / 26 SKIPPED; los seis
  fallos eran mocks de filtros opcionales. El spec corregido pasó 15/0, con el
  mismo producto. Ajuste de fixtures integrado mediante [PR #84](https://github.com/avanza-digital/avancecorp-crm/pull/84).
  No afirmar que la suite completa pasó en una sola ejecución.
- Claude devolvió **CHANGES_REQUESTED**. Codex corrigió foco de alto contraste,
  contexto accesible, separación de textos y énfasis de vencidas; también evitó
  el recorte potencial del menú. Se repitieron los gates después. No afirmar PASS
  del reviewer ni usar una consulta sin dictamen como aprobación.
- Gate de realidad CLI **NOT RUN**, sin credenciales en esta copia. Se hizo una
  lectura SQL parcial, que no lo sustituye. Las demos y pruebas usan datos
  sintéticos; no prueban la primera jornada real.
- **Smoke gerencia PASS**: acceso y registro real tras recarga, sin escrituras.
  **Pendientes: aceptación y smoke productivo de analista y supervisor**.
  La jornada del 24/09 y las 76 casillas del plan conservan su estado.

Evidencia y resolución de la revisión en
`CRM-Avance-Corp/docs/gestion-diaria/UI-ANALISTA-SUPERVISOR-2026-09-23.md`
y `UI-REVISION-CLAUDE-2026-09-23.md`. La publicación, respaldo y límites están en
`UI-PUBLICACION-2026-09-23.md`. El bloque adicional del mismo tablero de Figma
ya distingue publicación cumplida y aceptación humana pendiente.

Reglas: Plus Jakarta Sans, navy/azul, sin verde, una acción principal,
jerarquía clara, color por decisión, legibilidad y estados completos. Las
reglas de cortes, permisos, cálculos y registro conservan su alcance aprobado.

[[Fundamentos UX del CRM]] · [[Gestion Diaria F4 - publicado y cortes programados para el 24-09 (2026-09-23)]] · [[Inicio]]

## H2 cerrada

El mismo tablero incorpora 24/72 tareas H1–H2 completas y 48 pendientes.
Vista horizontal verificada: diez/nueve filas, texto de 16 px y controles de 44 px; móvil y reflow al 200 %.
Gate: 4.192 tests PASS; E2E final 29/29. Acta H2 conserva corrida completa inicial 234/3/26.
Detalles en [[Gestion Diaria - supervisor horizontal aprobado (2026-09-23)]].
