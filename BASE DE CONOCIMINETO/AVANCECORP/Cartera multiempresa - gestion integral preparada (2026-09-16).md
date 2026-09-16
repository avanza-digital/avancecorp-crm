---
tags: [crm, cartera, multiempresa, gestion, preparado, retoma]
fecha: 2026-09-16
estado: implementado-local-pendiente-sql-y-publicacion
---

# Cartera multiempresa — gestión integral preparada

Miguel autorizó ejecutar [[Cartera multiempresa - plan de gestion integral (2026-09-16)]]
y conservar cambios ajenos. Autorizó expresamente separar el trabajo en un
worktree. Ruta: `/private/tmp/avancecorp-gestion-worktree`; rama
`codex/gestion-multiempresa`. Funcional `25a0b9da`, integración de los cambios
remotos de eliminación y leads propios hasta `1f9e5f83` en `a2243c4e`.
Main y los cuatro archivos ajenos no versionados de la carpeta original se
conservaron. Esta tarea no publicó ni instaló SQL productivo.

## Implementación

- La ficha reúne correcciones de cliente/banca Avance, contacto/documento neutral,
  contrato Avance y COOPAC con sus autoridades, precarga, bloqueos y errores.
- Detalle puntual con cuotas, pagos, saldo, producto/versiones, notas, PDF,
  tasas/autorizaciones, capital anterior/renovado/adicional y atribución de venta.
- Alta directa de Supervisión/Gerencia según capacidad vigente; analista desde Leads.
  Se retira la entrada Gestión Avance con F5 habilitada; fallback previo conservado.
- Cinco horas desde el registro original, sin reiniciar por fusión/vinculación;
  rol, autoría, responsable, revocación y fuente se verifican en servidor.
  Gerencia, Admin y Directorio mantienen sus diferencias. No hay comisiones.
- Contacto neutral no crea cuentas Auth/perfiles ni reescribe cierres anteriores;
  versiones y recibos protegen contra doble envío, conflictos y pérdidas de respuesta.

## Evidencia

`CRM-Avance-Corp/supabase/scripts/gestion-multiempresa/` contiene matriz, README,
reversa, evaluaciones Claude, `HTTP-LOCAL.json`, `SQL-LOCAL.json`,
`VERIFICACION.md` y `CIERRE-LOCAL.json`.

- Gate integrado: **3.654 pruebas**, **199 E2E** (26 skips existentes), lint,
  typecheck, build, release-config, bundle y duplicación PASS.
- 24 grupos Auth/HTTP/SQL reales locales PASS, incluidos fusión, antes/límite/después
  de cinco horas, revocación, concurrencia, Directorio y pagos/cotitulares/cuentas.
- Instalación/reversa con huellas, propietarios/ACL y funciones public intactas PASS.
  600 contactos en 29,08 ms y los mismos IDs visibles; medida local sintética.
- Dos revisiones Claude, ambas CHANGES_REQUESTED. Codex resolvió los hallazgos
  acreditados y contrastó las hipótesis con núcleo y pruebas; no hay dictamen
  Claude PASS inventado ni tercera consulta.
- Consulta productiva de solo lectura: 496 identidades activas, 24 sin perfil Avance,
  24 COOPAC vigentes sin condiciones; huellas previas compatibles y tabla nueva
  aún ausente. Gate general de realidad y ensayo/advisors remotos NOT RUN aquí.
- Banco local propio cerrado (servicios y ambas bases); snapshot/contenedor
  compartidos conservados. Sin recurso cloud de pago.

## Próximo paso concreto

Revisar y autorizar `20260916152851_crm_gestion_integral_multiempresa.sql` y su
banco remoto con presupuesto, completar ensayo/advisors y merge autorizado.
La reversa conserva datos y auditoría: primero restaurar la web anterior, después
revocar RPC nuevas y restaurar funciones. Reactivación mediante migración nueva.

Después integrar la rama en Main, comprobar igualdad con `avancecorp/main`,
reconstruir el artefacto y publicar solo con invocación humana `$release-crm`.
El ZIP local de la rama es para revisión y no autoriza esa publicación.

Las conformidades G7/G8 y apertura [[F9 - apertura general autorizada (2026-09-15)]]
conservan su estado. Relacionadas: [[Cartera inversionistas - implementacion de filtros comerciales (2026-09-15)]],
[[Eliminar contrato vinculado sin historial - preparado 2026-09-16]],
[[Lead propio del supervisor - 2026-09-16]].
