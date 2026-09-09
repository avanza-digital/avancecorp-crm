---
fecha: 2026-09-09
estado: publicado-con-deuda-documentada-del-banco-general
tags: [crm, citas, gerencia, publicacion, verificacion]
---

# Citas de Gerencia publicadas

Miguel autorizó finalizar la implementación y publicación («ok hazlo») y crear/eliminar un banco Supabase temporal con coste («sii hazlo»).

Publicado en **crm.miavance.com → Gerencia → Citas** desde Main limpio `887bef6e1bda65f2eb65b8cb9ae00d093f2bf883`, coincidente con `avancecorp/main` al publicar. Release `crm-20260909T045534Z-887bef6e1bda`; versión web `build-20260909T045533356Z`.

Aplica [[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]] y [[Citas Gerencia - tablero horizontal y flujo por persona 2026-09-08]]: mes/cuatro semanas comerciales, filtros, meta de tres citas por lead y 125% = 3,75, recorrido de inasistencia hasta conversión posterior a asistencia.

Dos lectores aplicados por banco → merge. Versiones Supabase `20260909031832` y `20260909031848` corresponden a archivos locales `20260909003243` y `20260909015744`; no renombrar los archivos versionados. Las 557 funciones previas y sus permisos, tablas, triggers, políticas, índices y vistas productivas quedaron iguales. Los avisos de seguridad anteriores no aumentaron.

PASS: frontend completo (3.127 tests; 147 E2E; 26 omitidas), matrices SQL específicas, REST autenticado por roles, firma generada y lectura V2 con datos de producción. NOT RUN: navegación del módulo con una sesión productiva de Gerencia, que no estaba disponible.

**La matriz RLS general sigue FAIL: 65 de 1.655 aserciones.** Se identificaron configuraciones ausentes en el banco y expectativas anteriores a cambios de permisos ya publicados; no todos los casos se investigaron individualmente. No tratar este cierre como aprobación global del CRM. La publicación del lector se sustentó en invariancia del código previo y pruebas específicas; el banco general necesita mantenimiento separado.

Banco creado `plaeuugsybujzymrcvgj`, eliminado tras la integración. `banco-f7` no se tocó. ZIP de reversión conservado fuera del web root. Caché purgada, versión estable y ZIP público 404. Hostinger transforma doce PNG; no cambiaron respecto al paquete de reversión.

Evidencia y alcance: [publicación de Citas](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/integracion/publicacion-2026-09-09/README.md).
