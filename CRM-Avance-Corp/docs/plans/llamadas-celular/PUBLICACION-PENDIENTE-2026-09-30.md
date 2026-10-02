# F1 pendiente durante la publicación de documentos

Miguel autorizó publicar únicamente la corrección DNI/CE/pasaporte y respondió
«Solo documentos; mantener F1 pendiente» al consultar el alcance del PR #148.

Se integró Main completo y se retiró temporalmente la activación de F1 en
`App.tsx`, `contacto.tsx`, `auth.tsx` y `gestion-diaria/analista.tsx`.
Esos cuatro archivos recuperan exactamente el comportamiento anterior al PR;
sus pruebas de contacto y Gestión Diaria corresponden a ese comportamiento.
Los componentes, coordinador, búsqueda, rutas y pruebas unitarias de F1
permanecen versionados. El receptor no se monta, el contacto no arma la cola
compartida y App no conserva el número recibido en el enlace del celular.

La reactivación requiere autorización específica de Miguel, restaurar la
integración de esos archivos (el commit de aplazamiento está separado de la
corrección de documentos), ajustar sus pruebas y superar los gates vigentes.
No revertir todo el release de documentos para reactivar F1.

## Reactivación preparada (01/10/2026)

Jhosep comunicó la autorización de Miguel el 01/10/2026 (hacia las 17:30 UTC).
La rama `feat/llamadas-f1-reactivar` deshace SOLO el commit de aplazamiento
`9815ad02` («mantener F1 Llamadas pendiente por indicación de Miguel») sobre el
`main` de ese día: vuelven la integración de F1 en `App.tsx`, `contacto.tsx`,
`auth.tsx` y `gestion-diaria/analista.tsx` y sus pruebas. No toca el release de
documentos ni ninguna otra pieza. El merge y el release los hace Miguel.

## Publicada (01/10/2026, ~19:55 Lima)

La reactivación (PR #160) salió a producción dentro del release
`crm-20261002T005155Z-4498582850b1` (commit `44985828`, build
`build-20261002T005154879Z`, rama `release/potencial-filtro-llamadas-20261001`),
junto con el filtro por potencial de Leads. Miguel lo confirmó en esa sesión
(«sí, esos dos también», por Gestionado y Llamadas), invocó `/release-crm` y
lanzó la subida. F1 no pidió nada nuevo del servidor: su búsqueda usa
`crm.cartera_pagina_fn`, que ya estaba en producción. Gates de ese release:
`npm run check` PASS (346 archivos, 5 592 pruebas), e2e Docker completo con 321
en verde y los dos fallos ajenos conocidos (`gerencia-operativa.spec.ts:108`,
`gestion-diaria-vuelta.spec.ts:11`), preflight y smoke correctos. Falta la
prueba real desde un celular: no se hizo en esa sesión.
