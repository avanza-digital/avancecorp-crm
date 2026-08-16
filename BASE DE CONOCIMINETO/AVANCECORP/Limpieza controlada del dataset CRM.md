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

## 2026-08-16 — Limpieza REAL en producción, a mano, antes de encender el puente

Miguel: «toda esa data es demo, límpiala». Los 5 leads que quedaban (4 convertidos)
salieron con todo su rastro, en **una sola sentencia**, antes del arranque del puente.

**Lo que se llevó:** 5 leads · 44 actividades · 14 tareas · 6 asignaciones del ledger ·
3 reservas de conversión · 1 cierre externo · 3 anulaciones de cierre Avance ·
1 depósito reclamado · 5 ciclos + 20 etapas + 6 hitos de SLA. `crm.leads` = **0**.

**Lo que NO se tocó** (verificado por conteo después): `public.contratos` = 385 ·
`public.perfiles` = 350 · `crm.equipo` = 24 · `crm.metas_vendedor` = 112. Ninguno de los
5 leads tenía `contrato_id`, así que el portal quedó fuera por construcción, no por suerte.

### La técnica (reutilizable)

Los guards **no tienen puerta de servicio para DELETE**: se leyó el cuerpo de los cinco
y en todos la rama `tg_op = 'DELETE'` lanza **incondicionalmente**, antes de mirar
`crm.op_privilegiada` / `crm.ledger_writer` / `crm.sla_writer` — esas válvulas solo abren
UPDATE/INSERT. La única vía es `ALTER TABLE ... DISABLE TRIGGER <nombre>`.

Un solo bloque `DO` que: comprueba que hay exactamente 5 leads (si no, se niega) →
**baja 7 candados nombrados uno a uno** → borra en orden de dependencias → **los vuelve a
subir** → y verifica lo hecho (0 leads, 0 filas colgando, los 7 candados en `tgenabled='O'`),
lanzando si algo no cuadra. Como es **una sola sentencia, es atómica**: cualquier fallo
deshace hasta el `DISABLE`, así que no existe el estado «candado caído y nadie mirando».
Y mientras dura, el `ALTER TABLE` mantiene un lock exclusivo: ninguna otra sesión puede
colar una escritura por el hueco. Misma familia que [[Probar en producción sin escribir nada]].

**Nombrar los triggers, no `DISABLE TRIGGER USER`:** así los `trg_audit_*` **siguen vivos** y
cada fila borrada queda copiada entera en `public.audit_log.data_antes`. Verificado: 5 leads,
14 tareas, 3 anulaciones, 1 cierre externo, 3 reservas y 1 depósito con copia completa.
⚠️ **Las 44 actividades y las 31 filas de SLA NO tienen copia**: su auditoría solo cubre
`INSERT`. Si algún día importa poder deshacer eso, ahí está el hueco.

### Las siete llaves (por si se repite)

| Tabla | Candado |
|---|---|
| `crm.lead_asignacion_sla_hitos` | `trg_lead_asignacion_sla_hitos_guard` |
| `crm.lead_sla_etapas` | `trg_lead_sla_etapas_guard` |
| `crm.lead_sla_ciclos` | `trg_lead_sla_ciclos_guard` |
| `crm.lead_asignaciones` | `trg_lead_asignaciones_00_inmutables` |
| `crm.cierres_externos` | `trg_cierres_externos_00_inmutables` |
| `crm.cierres_avance_anulados` | `trg_cierres_avance_anulados_00_append_only` |
| `crm.depositos_reclamados` | `trg_depositos_reclamados_00_append_only` |

Orden de borrado: depósitos → hitos → etapas → ciclos → anulaciones → cierres externos →
reservas → asignaciones → tareas → actividades → leads.

⚠️ **`crm.depositos_reclamados` no aparece mirando solo qué referencia a `crm.leads`**: cuelga
del *cierre externo*, un salto más allá. Salió de preguntar por las llaves que apuntan a **cada
tabla del conjunto a vaciar**, no solo a `leads`. Sin esa consulta, la operación habría muerto
a mitad contra un RESTRICT (sin daño, pero sin enterarse de por qué).

**Efecto de negocio:** la conversión de agosto queda en **0 convertidos** — era 4, toda demo.
No había ningún mes sellado (`periodos_cerrados` = 0), así que no se rompió ninguna foto histórica.
