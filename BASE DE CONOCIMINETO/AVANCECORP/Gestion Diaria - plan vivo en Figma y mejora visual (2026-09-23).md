# Gestión Diaria — plan vivo en Figma y mejora visual

Miguel pidió trasladar el mismo plan por fases y casillas presentado en el chat
a Figma y mantenerlo actualizado conforme avance el trabajo.

Tablero editable: https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L

Se crearon y comprobaron visualmente 76 puntos distribuidos en F0–F6,
incluyendo las seis etapas de F4 y F4.1. F0–F3 están publicados; F4 sigue en
etapa 6, con primera jornada del 24/09 y seguimiento del sábado pendientes.
No confundir pruebas técnicas con validación humana ni activar tasa baja antes de F5.

## Continuidad del tablero

- Actualizar **este mismo archivo de Figma** al registrar cada avance verificado.
- Actualizar también `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
- Los IDs y el texto de cada punto están en `docs/gestion-diaria/FIGMA-PLAN.json`.
- Cambiar las casillas solo con evidencia; conservar PASS/FAIL/NOT RUN.
- Es una actualización durante el trabajo, no una automatización en segundo plano.

## Mejora visual solicitada

Miguel considera insuficiente la calidad visual de `Mi día` y `Mi equipo hoy`.
Prioriza **analista y supervisor**, y pide seguir el documento de fundamentos
UX/UI. **Implementada y verificada en local el 23/09**, en la rama
`codex/gestion-diaria-ui` de la copia aislada existente, preservando la tarea
de la otra sesión.

- Analista: contacto activo y llamada con prioridad, dos paneles proporcionados,
  cola con selección clara y detalle progresivo.
- Supervisor: resumen comparable, búsqueda y filtros integrados en la tabla,
  acciones junto a cada analista, motivos de atención y vencidas legibles.
- Gate integral **PASS: 4.175 pruebas**; Docker **13 passed / 0 failed**.
- Claude devolvió **CHANGES_REQUESTED**. Codex corrigió foco de alto contraste,
  contexto accesible, separación de textos y énfasis de vencidas; también evitó
  el recorte potencial del menú. Se repitieron los gates después. No afirmar PASS
  del reviewer ni usar una consulta sin dictamen como aprobación.
- Gate de realidad **NOT RUN**, sin credenciales en esta copia. Las demos y
  pruebas usan datos sintéticos; no prueban la primera jornada real.
- **Pendientes: publicación, aceptación y smoke productivo** de esta mejora.
  Las 76 casillas del plan por fases conservan su estado.

Evidencia y resolución de la revisión en
`CRM-Avance-Corp/docs/gestion-diaria/UI-ANALISTA-SUPERVISOR-2026-09-23.md`
y `UI-REVISION-CLAUDE-2026-09-23.md`. El bloque adicional del tablero de Figma
ya distingue implementación local y publicación pendiente.

Reglas: Plus Jakarta Sans, navy/azul, sin verde, una acción principal,
jerarquía clara, color por decisión, legibilidad y estados completos. Las
reglas de cortes, permisos, cálculos y registro conservan su alcance aprobado.

[[Fundamentos UX del CRM]] · [[Gestion Diaria F4 - publicado y cortes programados para el 24-09 (2026-09-23)]] · [[Inicio]]
