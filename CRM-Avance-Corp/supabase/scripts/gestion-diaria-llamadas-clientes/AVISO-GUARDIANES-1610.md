# AVISO para el re-sellado de guardianes en pausa (`GUARDIANES-1610-CORREGIR-KITS`, migración `20261016211001`)

**19/10/2026.** La migración `20261019170422_crm_gestion_diaria_llamadas_clientes.sql` (rama
`crm/llamadas-clientes-gestion-diaria-20261019`) **re-emite tres gates de Gestión Diaria** a partir de su cuerpo vivo,
con reemplazos anclados:

| Gate | Qué cambia | Huella viva antes (19/10) |
| --- | --- | --- |
| `private.assert_gestion_diaria_analista()` | huellas del agregador y del lector + sección 2b nueva (ayudante de llamadas a clientes) | `eb2c03fd99f13cda077f8c02e4533ec4` |
| `private.assert_gestion_diaria_citas()` | huella del agregador | `12012959d2e751c43df86b847dcce037` |
| `private.assert_gestion_diaria_pulso()` | huellas del agregador y del lector | `bdccbb6e3fee574416a0987941ae344b` |

**NO toca** la huella de `crm.equipo_visible_fn()` (`200162f4…` → sigue en rojo hasta la 211001) ni la de
`private.trg_sla_recibo_guard()` en el gate del resultado. Tampoco sella `es_coordinacion_consulta` ni
`borrado_lead_error_autoriza`.

## Qué significa para la 211001

- Si la 211001 se aplica **DESPUÉS** de esta: su preflight que pinna `assert_gestion_diaria_analista` en `eb2c03fd…`
  (línea ~111 de la 211001) se negará. Hay que **regenerar las precondiciones midiendo producción** (como ya dice
  `PENDIENTE.md`, punto 1) y hacer el reemplazo `200162f4…` → `58bd0554…` sobre el cuerpo vivo (el ancla sigue existiendo,
  una sola vez). Las huellas nuevas selladas por esta migración están en
  `supabase/scripts/gestion-diaria-llamadas-clientes/verificacion.json`.
- Si la 211001 se aplica **ANTES**: esta migración compone sin cambios (su preflight solo exige que las anclas
  `'7c5d14e6…'`, `'27d25609…'` y `-- 3. La cola de la que bebe la pantalla` sigan exactamente una vez en el gate del
  analista, y las dos primeras en citas/pulso).
- El ensayo de esta migración SIMULÓ la 211001 en su banco (roster `200162f4…` → `58bd0554…` y censo analítico
  neutralizado en el pulso) solo para que los 24 mutantes viejos fueran concluyentes; se deshizo antes de comparar con
  producción.

## Dónde está todo

`supabase/scripts/gestion-diaria-llamadas-clientes/{LEEME.md, ensayar.mjs, reversa.sql, verificacion.json}` y la fila
de `MIGRACIONES.md` de `20261019170422`.
