---
tags: [crm, leads, ux, tasa, historial]
fecha: 2026-09-20
estado: publicado-verificado
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
  typecheck, 16 pruebas focales, suite completa de 264 archivos / 3.895 pruebas,
  build y `git diff --check`.
- **PASS:** 8 E2E afectados en escritorio/móvil y recorrido Playwright local con
  tasa cerrada, tasa abierta e historial de 12 actividades desplazado dentro de
  su propio riel. Las capturas locales quedan fuera del release.

## Publicación verificada

- **PR:** `#48`, integrado por squash en `avancecorp/main` el 2026-09-20.
- **Commit fuente:** `004bd69f330324b28ac71ed7a3874acced7785d8`.
- **CI de `main`: PASS:** `verify` en 11 min 57 s y `e2e` en 13 min 27 s.
- **Release:** `crm-20260920T182520Z-004bd69f3303`.
- **Build ID:** `build-20260920T182519890Z`.
- **ZIP:** 2.255.016 bytes; SHA-256
  `51e1ab8cbda28a5b96fb44383990deeb01c54c6cef862471fa09eacd58074122`.
- **Destino:** `https://crm.miavance.com/`; publicación aceptada por Hostinger
  y verificada el 2026-09-20 a las 13:52 (-05).
- **PASS en vivo:** portada y `version.json` responden 200; el `index.html` y
  los 12 assets JS/CSS de entrada coinciden byte por byte con el release; el
  ZIP responde 404 tanto en `crm.miavance.com` como en `miavance.com`.
- **NOT RUN:** smoke visual directo en producción porque no había navegador
  interactivo conectado a la sesión. Quedan como evidencia equivalente el
  recorrido visual local y los E2E del PR y de `main`, ambos aprobados.

No se publicó backend, migraciones ni cambios de datos. El rollback inmediato
conservado es el release `crm-20260920T074547Z-dbfa9d6bffcf`, commit
`dbfa9d6bffcfdf5e9b1cbc2c5a577a56a6cda737`.
