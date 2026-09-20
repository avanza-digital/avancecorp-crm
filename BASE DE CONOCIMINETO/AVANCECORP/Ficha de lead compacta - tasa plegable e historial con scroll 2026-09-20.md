---
tags: [crm, leads, ux, tasa, historial]
fecha: 2026-09-20
estado: validado-local-pendiente-publicacion
---

# Ficha de lead compacta — tasa plegable e historial con scroll

Relacionado con [[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Historial por lead sin topes - Fase 1 (2026-09-19)]],
[[Auditoria del historial de leads - analista y supervisor (2026-09-20)]] y
[[Fundamentos UX del CRM]].

## Decisión

La ficha del lead conserva la validación comercial de la solicitud de tasa,
pero deja el panel visualmente plegado al abrir. Un botón compacto
«Solicitud de tasa» permite mostrarlo u ocultarlo y comunica su estado con
`aria-expanded` y `aria-controls`.

El contenido no se desmonta al cerrar: las consultas de política y solicitudes,
el bloqueo de conversión y un borrador que el analista haya empezado siguen
vivos. Es un cambio exclusivamente de frontend; no cambia tasas, permisos,
RPC, tablas ni datos.

El historial de actividades conserva el registro rápido fuera del riel y limita
la lista a 20 rem de alto. Cuando la lista excede esa altura, usa el scroll
discreto del CRM. La paginación «Cargar más gestiones» y el pliegue «Ver
anteriores» siguen funcionando dentro de la región denominada
«Historial de actividades».

## Implementación y verificación local

- `app/src/components/app/condiciones-tasa-lead.tsx`: disclosure compacto que
  mantiene montado `CondicionesTasaLeadPanel`.
- `app/src/components/app/lead-drawer.tsx`: usa el disclosure y agrega el riel
  `ac-scroll` al timeline.
- Pruebas nuevas: el panel inicia oculto sin liberar la conversión y el timeline
  conserva región, altura máxima y overflow vertical.
- **PASS:** lint (solo cuatro avisos preexistentes en `coverflow-carousel.tsx`),
  typecheck, 16 pruebas focales, suite completa de 264 archivos / 3.898 pruebas,
  build y `git diff --check`.
- **PASS:** 8 E2E afectados en escritorio/móvil y recorrido Playwright local con
  tasa cerrada, tasa abierta e historial de 12 actividades desplazado dentro de
  su propio riel. Las capturas locales quedan fuera del release.

Pendiente integrar en `avancecorp/main`, construir desde ese commit limpio y
publicar solamente el frontend del CRM.
