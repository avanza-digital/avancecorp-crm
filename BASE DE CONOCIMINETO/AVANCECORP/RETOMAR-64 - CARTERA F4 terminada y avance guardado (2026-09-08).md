---
tags: [retomar, cartera, multiempresa, F4, F5]
fecha: 2026-09-08
estado: guardado-F4-tecnica-terminada-F5-pendiente
codigo: RETOMAR-64
---

# CARTERA — avance guardado, F4 técnica terminada

Miguel pidió guardar todo el avance. **F4 terminada técnicamente / G4 cerrado**;
no hay publicación, aplicación SQL ni activación productivas. No reabrir el
pendiente de comisiones: Miguel confirmó que se calculan fuera del sistema y
no quiere un módulo para indicar cuánto pagar ni conciliar pagos externos.

## Dónde está el trabajo

- Rama: **`codex/f4-cierre`**.
- Worktree de desarrollo: `/private/tmp/avancecorp-f4-desarrollo`.
- El historial Git está fuera del temporal, en
  `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/.git`.
- Respaldo privado permanente de esta sesión: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/RESPALDOS-CARTERA/2026-09-08_140127`.
  Incluye `cartera.bundle` (rama e historial Git), dumps actuales de los dos
  bancos sintéticos, sus directorios completos, Storage y contexto local de
  colaboración. El manifiesto de respaldo registra hashes; conservar permisos
  privados porque contiene credenciales ficticias de Auth/API.

## Commits de referencia

| Commit | Avance |
|---|---|
| `e28d97d` | Cierre técnico de G4 y decisión explícita de comisiones externas |
| `bcdfa0d` | Candidata completa, revisión integral evaluada, fixes finales y evidencia |
| `36725bd` | Reconstrucción, corpus F2, finanzas y permisos de lectura vigentes |
| `698e0d6` | Cotitulares con procedencia y corrección versionada de solicitudes |

Este punto de retoma se guarda en el siguiente commit de la misma rama.
El bundle se crea después de ese commit para incluir también estas instrucciones.

## Estado técnico para continuar

- 48 funciones (18 adaptadas, 30 nuevas), 11 módulos, siete tablas nuevas.
- Candidata SQL versionada: `20260907191832_crm_f4_inversiones_base_y_escritores.sql`.
  SHA-256: `84f8b3b407812363ebe9705aaaab46b8620d48a79dc7d6d38cc285a18a293afe`.
- 3050 tests frontend, 43 PDF Deno y matrices SQL/HTTP comprobadas; reconstrucción
  y restauración pareada verificadas. Los fallos previos y su recuperación están
  documentados sin transformarlos retrospectivamente en PASS.
- Claude fue reviewer sin escritura; Codex evaluó su CHANGES_REQUESTED y verificó
  las correcciones. No se afirma un PASS posterior de Claude.
- Bancos `avancecorp-f4-bank` (API 56321, PG 56322) y
  `avancecorp-f4-reconstruccion` (API 57321, PG 57322). F3 ON, F4/F5 OFF en ambos.
  Runtime temporal de funciones detenido. Las bases/Storage se conservan.
- El PDF mantiene contenido, firma, fuentes y plantilla. Agregar cotitulares
  impresos requiere aprobación previa de Miguel sobre texto/ubicación.

## Próximo paso

**F5: cartera y Ficha 360 multiempresa**, inversiones agrupadas por empresa/moneda,
responsable vigente, permisos y botón «Nueva inversión», con datos sintéticos.
Leer el plan y la matriz; no repetir como pendientes las pruebas ya cerradas de F4.
No desplegar ni activar automáticamente: se conservan las fases/gates posteriores.

Si el worktree temporal desaparece, abrir el repositorio principal, comprobar
`git worktree list` y recuperar la rama `codex/f4-cierre` en un worktree nuevo.
El historial está en el repositorio principal y también en `cartera.bundle`;
no copiar encima del checkout principal ni descartar cambios de otras tareas.
Los bancos tienen rutas cerradas `/private/tmp/avancecorp-f4-*`: restaurar allí
sus archivos si faltan, siguiendo el runbook y usando destinos nuevos para DB/
Storage. No repetir la migración sobre una base que ya contiene F4.

## Documentos vigentes

- [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]];
- [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]];
- [[F4 multiempresa - reconstruccion, finanzas y lectura vigente (2026-09-08)]];
- [Matriz F4](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md);
- [Reconstrucción y restauración](../../CRM-Avance-Corp/supabase/scripts/f4/RECONSTRUCCION-Y-RESTAURACION.md);
- [Acta de cierre G4](../../CRM-Avance-Corp/supabase/scripts/evidencia-f4/cierre-g4-comisiones-externas-2026-09-08.json).

`RETOMAR-63` es una pausa anterior; queda superado por esta nota. Los documentos,
SQL y manifiestos históricos conservan su estado de aquella captura.
