---
tags: [crm, gestion-diaria, f6, ux, gerencia]
actualizado: 2026-09-25
---

# UX horizontal de gerencia preparada y validada

**Candidato validado; revisión normal de GitHub y publicación pendientes.**
Miguel añadió esta entrega al goal F4.1–F6: trasladar la experiencia horizontal
aprobada para supervisores a gerencia, conservando sus matices y permisos.
Continúa [[Gestion Diaria - cola completa F6 preparada (2026-09-24)]] y
[[Gestion Diaria - F5 publicada y F6 en observacion (2026-09-24)]].

La cabecera reúne fecha, registro general y seguimiento; conserva los ocho
indicadores de F5 y sus comparaciones. Una tabla compara equipos y después
analistas, con detalle lateral o diálogo en móvil. Hábitos incorpora tabla,
búsqueda y filtro por equipo, manteniendo las ventanas 7/14/30 y todos sus datos.
La navegación conserva operación → equipo → analista → registro → ficha.
Los filtros no cambian los totales globales ni los pendientes actuales.

Se conservan búsqueda, filtros y páginas al abrir fichas, ampliar y cambiar el
ancho. Otra fecha/ventana inicia otro contexto. El registro general se monta
al visitarlo y se mantiene oculto después para conservar su consulta; no hay
un lector por cada fila. Una denegación retira toda la vista hasta verificar
la sesión; el servidor sigue decidiendo el acceso. SQL, RPC, RLS y roles no
cambian.

Fuente `4a4cb1ec`, con Main `3027028d` / PR #100 integrado sin conflictos.
Gate PASS: 4.421 tests / 298 archivos; Chromium Docker completo 270/0/26,
WebKit dirigido 10/0, sin reintentos. Cinco advertencias previas de lint y 26
omisiones conocidas se conservan. Dos reviews: CHANGES_REQUESTED corregido,
seguido de PASS; mejoras opcionales verificadas en las corridas finales.
Capturas sintéticas de escritorio, detalle ampliado y móvil inspeccionadas.

Acta, decisiones y hashes en
`CRM-Avance-Corp/docs/gestion-diaria/f6-ux-gerencia-2026-09-24/ACTA.md`
y `VALIDACION.json`. Mismo Figma actualizado; la casilla de integración sigue
pendiente hasta incorporar/publicar. Rama
`codex/gestion-diaria-f6-ux-gerencia-20260924`, en la copia separada autorizada.

La publicación F5 vigente sigue siendo `b402a7f1`. Esta preparación no retira
Seguimiento ni acredita siete días reales: no puede retirarse antes del
01/10/2026 a las 21:57:11 Lima, y requiere estabilidad documentada. El corte
único del sábado 26/09 permanece pendiente. No pedir otra conformidad manual.
Véase [[Inicio]].
