---
fecha: 2026-09-06
estado: propuesto-pendiente-de-decision-de-miguel
tags: [crm, ux, gerencia, plan]
---
# Plan UX del usuario Gerencia — número → lista → ficha → acción (2026-09-06)

Miguel descartó el plan UX anterior y su Figma: copiaban mockups y desmejoraban el CRM. Pidió analizar **solo Gerencia**, sobre **producción**, con el playbook `UI-UX.pdf`, y trabajar en **archivos de Figma nuevos**.

**Diagnóstico (commit publicado `96f2038`):** el tablero de Gerencia enseña bien pero no conduce. De 14 pantallas, solo Leads y Pipeline llegan a un lead; ninguna cifra de dirección abre la lista que la compone. La conversión del mes aparece en cinco pantallas. Línea base: «quiénes son las citas vencidas» ≥ 6 clics; «qué cerró Ana Torres» ≈ 7 clics con respuesta aproximada; «de qué origen vienen los cierres» sin respuesta.

**Modelo propuesto:** toda cifra y todo nombre es una puerta → Leads recibe filtros por enlace y los muestra como miga de pan (viven en la URL) → ficha del lead (existe) → acción. Ficha de analista alcanzable desde cualquier nombre. Período común a la Dirección. Cuatro pantallas de dirección con una pregunta cada una (Resumen, Equipo = Ranking + Rendimiento, Conversiones sin hero, Citas). Metas se integra. Tokens de la Fase 1 (una fuente, cinco colores con significado, escala 4–48, estados).

**Fases:** 0 medir · 1 tokens · 2 número→lista→ficha · 3 período común · 4 pantallas de dirección · 5 estados honestos y Cartera · 6 validar. Métricas: clics por tarea, pantallas con salida a leads (2 → 14), repeticiones de la conversión (5 → 1).

**Riesgo de datos:** «cierres del mes» debe salir de la fecha de conversión, no de la etapa Convertido (inventario de 45 días); puede necesitar una lectura de servidor en solo lectura.

Documentos: `UX-UI-GERENCIA/PLAN-GERENCIA-2026-09-06.md` · evidencias `UX-UI-GERENCIA/08-produccion-2026-09-06/` · Figma flujos https://www.figma.com/board/TAdFQI94B2DABzSLU8I9kI · Figma mockups https://www.figma.com/design/1OD5qEmCz7CI1IuNBm642E

Relacionadas: [[Fundamentos UX del CRM]] · [[Plan de mejoras UX-UI del CRM]] · [[Plan de mejora UX de Gerencia - revision 2026-09-05]] (antecedente, descartado).
