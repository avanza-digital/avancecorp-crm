---
tags: [crm, datos, seguridad, scripts, wip]
actualizado: 2026-08-07
estado: bloqueado
---

# Limpieza controlada del dataset CRM

Relacionado con [[Inicio]], [[Offboarding seguro del CRM (P04)]],
[[Cuentas bancarias por contrato]] y
[[Disponibilidad y enfriamiento de leads (P-047 y P-048)]].

## Decisión vigente

`CRM-Avance-Corp/supabase/scripts/clean-crm-data.mjs` sigue siendo una
herramienta WIP para branch/staging. Solo están habilitados `--help` y
`--preflight`. `--dry-run` y la limpieza efectiva abortan antes de crear el
cliente Supabase, incluso si se entrega la frase destructiva correcta.

No ejecutar este script contra una base hasta cerrar el bloqueo estructural y
probar la operación completa en una base desechable.

## Auditoría local 2026-08-07

- Las opciones desconocidas se rechazan también cuando empiezan por `--`.
- `--preflight` y `--dry-run` son mutuamente excluyentes.
- `--preserve-reference` conserva como conjunto
  `crm.enfriamiento_politica`, `crm.cuentas_bancarias` y
  `crm.contrato_cuentas_pago`; así no rompe el enlace histórico contrato →
  cuenta.
- El plan incluye `crm.objetivos_vendedores`, que referencia
  `crm.equipo` y había quedado omitida.
- El ejemplo de preflight declara las dos variables que valida el CLI, usando
  una clave ficticia porque ese modo no crea cliente ni abre red.
- Hay 13 pruebas CLI sin red para flags, variables, producción, confirmación,
  URLs inseguras, targets, preservación y el bloqueo WIP.

## Bloqueo estructural

`crm.lead_asignaciones` es un ledger append-only. Su trigger
`trg_lead_asignaciones_00_inmutables` rechaza todo `DELETE` de forma
incondicional, incluido `service_role`. La implementación por PostgREST no
puede vaciar esa tabla; además, como borra secuencialmente, podría eliminar
tablas anteriores y fallar después, dejando una limpieza parcial.

El guard del CLI evita ese escenario. Para habilitarlo hace falta diseñar una
operación transaccional exclusiva para una base desechable, presentar primero
el SQL y probar rollback, orden de FKs, triggers y modos de preservación. No se
ha autorizado crear una RPC destructiva persistente ni relajar la
inmutabilidad del ledger.

Punto de continuidad original: `CRM-20260806-PENDIENTES-EA53F10`.
