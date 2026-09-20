---
tags: [crm, leads, ux, actividad, historial]
fecha: 2026-09-20
estado: validado-local-pendiente-publicacion
---

# Ficha de lead — retiro del botón Registrar actividad

Relacionado con [[Ficha de lead compacta - tasa plegable e historial con scroll 2026-09-20]],
[[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]] y
[[Fundamentos UX del CRM]].

## Decisión

La sección Actividad de la ficha del lead deja de mostrar el acceso rápido
«Registrar actividad…» y elimina todo el espacio visual que ocupaba. El
historial aparece inmediatamente debajo del título y conserva su región con
scroll interno de altura acotada.

El cambio no elimina el compositor ni la operación de registro. El compositor
sigue abriéndose cuando una acción operativa de SLA de primera atención o
seguimiento lo solicita. También permanecen intactos los registros desde
llamadas, WhatsApp, Gestión Diaria y cierre de tareas.

Es un cambio exclusivamente de frontend: no modifica RPC, tablas, permisos,
tipos de actividad ni datos.

## Alcance técnico

- `app/src/components/app/lead-drawer.tsx`: elimina el botón, su referencia de
  foco y su huella de espaciado; el cierre del resultado de llamada devuelve el
  foco a la sección Actividad.
- El riel `Historial de actividades` conserva `max-h-80`, `overflow-y-auto` y
  `overscroll-contain`.
- Las pruebas del compositor se ejecutan en el estado en que una acción SLA ya
  lo abrió; la prueba de interfaz comprueba que el botón y su texto no existen.

## Verificación

- **PASS:** 52 pruebas focalizadas de la ficha, el historial y el compositor
  invocado por SLA.
- **PASS:** recorrido E2E focalizado en Chromium; el botón y su texto no están
  presentes y el historial conserva `max-h-80` y `overflow-y-auto`.
- **PASS:** gate integral `npm run check`: lint (solo cuatro avisos
  preexistentes en `coverflow-carousel.tsx`), typecheck, 265 archivos / 3.921
  pruebas con cobertura, configuración de release, 8 pruebas del worker de
  tasas, build, verificación del bundle y control de duplicación.
- **NOT RUN:** suite E2E completa; para este cambio LEVEL 1 se ejecutó el flujo
  directamente afectado.

No se publicó ni se modificó backend, base de datos o producción.
