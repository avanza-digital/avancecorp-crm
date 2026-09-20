---
tags: [crm, leads, ux, actividad, historial]
fecha: 2026-09-20
estado: correccion-supervision-validada-local-pendiente-publicacion
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

El cambio no elimina el compositor ni la operación de registro para el
analista. El compositor sigue abriéndose para `vendedor` cuando una acción
operativa de SLA de primera atención o seguimiento lo solicita. También
permanecen intactos los registros desde llamadas, WhatsApp, Gestión Diaria y
cierre de tareas.

La primera publicación reveló una ruta secundaria para Supervisor: el aviso
«Revisa el seguimiento con el analista» todavía ofrecía «Registrar gestión» y
abría el mismo compositor. La corrección conserva el aviso como información de
supervisión, pero elimina esa acción para Supervisor, Gerencia y cualquier rol
distinto de `vendedor`. La regla se aplica tanto en el descriptor visual del
aviso como en la apertura y el render final del compositor.

Es un cambio exclusivamente de frontend: no modifica RPC, tablas, permisos,
tipos de actividad ni datos.

## Alcance técnico

- `app/src/components/app/lead-drawer.tsx`: elimina el botón, su referencia de
  foco y su huella de espaciado; el cierre del resultado de llamada devuelve el
  foco a la sección Actividad.
- El riel `Historial de actividades` conserva `max-h-80`, `overflow-y-auto` y
  `overscroll-contain`.
- `app/src/lib/sla-operacion.ts` centraliza que únicamente `vendedor` puede
  registrar una gestión desde una alerta SLA de la ficha.
- Los avisos de primera atención y seguimiento no presentan botón de acción a
  roles de supervisión; las acciones de tarea vencida y revisión comercial no
  cambian.
- `Timeline` incluye un candado final: aunque reciba por error el estado abierto,
  no renderiza ni procesa el compositor para un rol sin permiso.
- Las pruebas del compositor se ejecutan en el estado en que una acción SLA ya
  lo abrió; la prueba de interfaz comprueba que el botón y su texto no existen.

## Verificación

- **PASS:** 52 pruebas focalizadas de la ficha, el historial y el compositor
  invocado por SLA.
- **PASS:** recorrido E2E focalizado en Chromium; el botón y su texto no están
  presentes y el historial conserva `max-h-80` y `overflow-y-auto`.
- **PASS:** 75 pruebas focalizadas después de la corrección de supervisión; se
  cubren los roles, el texto del aviso, la ausencia de acción y el candado final
  del compositor.
- **PASS:** recorrido E2E focalizado de Supervisor; el aviso permanece visible,
  «Registrar gestión» no existe y el compositor no puede abrirse.
- **PASS:** gate integral: lint (solo cuatro avisos preexistentes en
  `coverflow-carousel.tsx`), typecheck, 265 archivos / 3.933 pruebas con
  cobertura, configuración de release, 8 pruebas del worker de tasas, build,
  verificación del bundle y control de duplicación.
- **PASS:** suite E2E completa: 222 recorridos aprobados y 26 omitidos por las
  condiciones declaradas de esos escenarios.

La primera versión se publicó en el build `build-20260920T202855561Z`. La
corrección de la ruta de Supervisor está validada localmente y pendiente de una
nueva publicación. No modifica backend, base de datos ni datos.
