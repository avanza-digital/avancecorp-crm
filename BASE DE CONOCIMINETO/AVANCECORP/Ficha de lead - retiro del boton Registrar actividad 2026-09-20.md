---
tags: [crm, leads, ux, actividad, historial]
fecha: 2026-09-20
estado: publicado-verificado
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
- **PASS:** después de integrar los cambios simultáneos de `main`, el pre-push
  volvió a ejecutar 265 archivos / 3.929 pruebas.
- **PASS:** PR [#52](https://github.com/avanza-digital/avancecorp-crm/pull/52),
  CI del PR `35534976884` y CI de `main` `35535637932`; en ambas ejecuciones
  terminaron en verde `verify` y la suite E2E completa.

## Publicación

- Publicado el 20/09/2026 a las 15:44 (Lima) en `crm.miavance.com` mediante el
  conector oficial de Hostinger.
- Commit fuente y de merge: `438b94cee90237f68975c03d619837b8cd549468`.
- Release: `crm-20260920T202856Z-438b94cee902`.
- Build: `build-20260920T202855561Z`.
- ZIP privado: 2.257.612 bytes; SHA-256
  `3eda2734a8af1d0554854361b0fe1af02d92a34bfce42e210137072cb9589ae6`.
- **PASS:** `index.html`, `version.json`, los 11 bundles JavaScript iniciales y
  la hoja CSS respondieron HTTP 200 y coincidieron byte por byte con los hashes
  del manifiesto.
- **PASS:** el ZIP respondió HTTP 404 tanto desde `crm.miavance.com` como desde
  `miavance.com`.
- **PASS:** el artefacto anterior
  `crm-20260920T193711Z-6fd1252e5689` permanece validado y conservado fuera del
  web root para reversión.
- **NOT RUN:** inspección visual manual en navegador integrado; no había ningún
  navegador conectado a la sesión. La navegación quedó cubierta por el E2E
  completo remoto aprobado.

No se modificó backend, base de datos, permisos ni datos. El commit posterior
de esta acta es solo documental y no requiere volver a desplegar el frontend.
