---
tags: [crm, cartera, inversiones, continuidad]
fecha: 2026-10-06
estado: publicado-y-verificado
---

# Nueva inversión — bloqueo global y continuidad del cliente

## Decisión del usuario

El 06/10/2026 pidió deshabilitar «Registrar nueva inversión» cuando el cliente ya
cuenta con una inversión y dejar las operaciones de continuidad. Se preguntó
expresamente por empresa frente a todo el grupo. Respuesta:
«En todo el grupo; si ya invirtió, usar solo continuidad».

Esta decisión sustituye la propuesta de permitir la primera inversión en otra
empresa de [[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].

## Implementado en local

- En la ficha multiempresa, «Registrar nueva inversión» queda visible y deshabilitado
  cuando `inversiones_total > 0`, con una explicación accesible. El contador abarca
  toda la persona, todas las empresas y páginas; no depende del capital activo.
- Sin inversiones, «Registrar primera inversión» conserva permisos y comprobaciones
  de frescura existentes.
- Upgrade, renovación y reinversión conservan sus condiciones actuales: no se permite
  upgrade sin contrato Avance activo ni se inventan nuevas condiciones financieras.
- La ficha Avance y sus vistas de tabla y móvil también deshabilitan el alta cuando
  existen contratos. Se conservan los cambios previos de otras tareas.
- Archivos de producto: `app/src/components/app/inversionista-ficha.tsx`,
  `app/src/components/app/cliente-ficha.tsx`, `app/src/screens/mi-cartera.tsx` y
  `app/src/lib/contratos-catalogo.ts` (dentro de `CRM-Avance-Corp`).

## Alcance y límites

Es un cambio de botones de la interfaz, no una nueva validación del servidor.
Conversión de leads, venta cruzada, RPC y portal no se modificaron. Tampoco se
reescribieron inversiones, tasas, categorías ni métricas.

El cómputo de todo el grupo está en la ficha multiempresa. La vista antigua de
Avance (demo o contingencia con la bandera multiempresa apagada) solo dispone de
contratos Avance; no certifica ausencia de historial exclusivo en cooperativas.
La restricción integral en todas las entradas requeriría su propio cambio de servidor.

Un cliente con historial retirado conserva el bloqueo pedido. La disponibilidad
concreta de continuidad sigue dependiendo de los flujos existentes. Este cambio no
crea la ruta pendiente de «volver a invertir» tras retiro total.

Publicación autorizada con «ok vmaos deploy» y retomada con «ya esta» tras integrar el PR #206. Publicado y verificado el 06/10/2026 a las 16:35 Lima.

## Verificación

- PASS: lint (10 advertencias previas fuera de los archivos de producto modificados).
- PASS: TypeScript, build de producción y verificación del bundle.
- PASS: suite completa con cobertura, 387 archivos / 6.205 tests; pruebas de
  configuración de release 4/4 y service worker 8/8.
- PASS: tras ajustes finales de accesibilidad, 218 tests de cartera y fichas.
- PASS: E2E locales en Docker, 25/25, repetidos tras los ajustes finales:
  `f5-cartera`, `mi-cartera-detalle`, `contrato-crear`.
- PASS: `git diff --check` de los ocho archivos tocados y captura visual de la ficha.
- FAIL previo: duplicación 1,06 % supera el límite de 0,8 %; comparación en una copia
  del código anterior a esta tarea confirma 56 clones y 1,06 % antes y después.
  Por ello `npm run check` global no se reporta como PASS.
- NOT RUN: gate de realidad; el comando salió por ausencia de `SUPABASE_URL`.
  No se acreditó comportamiento sobre datos productivos.

## Revisión independiente

Una consulta a Claude con el wrapper del repositorio: CHANGES_REQUESTED.
Se aplicaron explicación accesible en tabla/móvil, combinación de motivos de bloqueo,
texto condicional sobre continuidad y reutilización de la condición para el rótulo.
Se documentaron los límites de la vista antigua y de no modificar el servidor.
No se solicitó otro dictamen para obtener PASS.

Los supuestos de total nulo/indefinido ya se rechazan en `FichaInversionistaSchema`
y `obtenerFichaInversionista`; no se añadió una tolerancia que convierta datos
inválidos en cero. La recuperación de conexión se prueba con un cliente sin inversiones.

Evidencia local de esta sesión: `/private/tmp/crm-continuidad-inversion-20261006/`
(copias iniciales, parche propio, logs de checks/E2E y revisión).

Relacionadas: [[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]],
[[Gestión comercial de clientes - renovaciones y upgrades]].

## Preparación de publicación (06/10/2026)

Parche aislado en una copia limpia de `avancecorp/main`, commit candidato `18e1e6c2c97caa4aa73c59acbdf3585cef0b5c5f`. [PR #206](https://github.com/avanza-digital/avancecorp-crm/pull/206). Conserva B11 ya publicado y excluye el trabajo pendiente de gestiones/postventa.

- PASS: `npm run check`, 385 archivos / 6.206 pruebas, duplicación 0,43 %. El fallo de duplicación de la carpeta compartida no se reproduce en la fuente limpia.
- PASS: 25 E2E en Docker sobre esta fuente limpia.
- PASS: artefacto candidato, verificación SHA-256 y preflight contra el vivo `afae7b59412a`.
- Paquete candidato (no publicado): `crm-20261006T212454Z-18e1e6c2c97c.zip`; SHA-256 `fa2c2496ce835232c663c66bcd4183858dc18281180d21ba135a657895e23f05`.
- Esta preparación quedó completada: PR integrado y paquete definitivo publicado, según el cierre siguiente.

Evidencia persistente: `CRM-Avance-Corp/output/continuidad-inversion-20261006/deploy/estado.json`. La copia limpia está en `/private/tmp/crm-continuidad-release-20261006`.

## Publicación efectiva y cierre

- PR #206 integrado; Main del workspace, la copia limpia y `avancecorp/main` coincidentes.
- Commit publicado: `4e6ee7ee296be83cd96366e3e79685343b3b706b`. Build: `build-20261006T213354829Z`.
- ZIP definitivo: `releases/crm-20261006T213355Z-4e6ee7ee296b.zip`. SHA-256: `9b5be00b190443726f5520fc37a54ba27ff3785ace447200b7ce2d807430e33d`.
- Fuente limpia; árbol idéntico al candidato que pasó 6.206 pruebas y 25 E2E.
- PASS: release, verificación del artefacto, preflight, Hostinger y HTTPS (154 archivos).
- PASS: ficha real, «Nueva inversión» deshabilitado y «Registrar upgrade» habilitado, con explicación visible. Sin escrituras de negocio.
- Main actualizado conservando el WIP ajeno. Ninguna migración aplicada por esta tarea.
- Acta: `CRM-Avance-Corp/docs/publicaciones/continuidad-inversiones-2026-10-06.md`.

No quedan pasos de publicación pendientes. Los límites de interfaz descritos arriba permanecen.
