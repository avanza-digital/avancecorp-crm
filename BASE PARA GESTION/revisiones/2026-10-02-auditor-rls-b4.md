# auditor-rls · B4 (20261002233851_crm_base_gestion_enfriamiento.sql) — 02/10/2026 (noche)

**VERDICT: CHANGES_REQUESTED (sin P0/P1) → APLICADO el 02/10 (noche), reensayado 16/16 en banco.**

- **[P2] El trigger podía dispararse fuera del núcleo** (escritores sin usuario: service_role sin JWT, backfills, restauraciones)
  y enfriar con la fecha de hoy ignorando fechas históricas, sin candado. → Gate al inicio: sin `crm.op_base_gestion = on`
  (que el núcleo de B3 siempre enciende) el trigger no hace nada. Cabecera y COMMENT corregidos. Caso de banco «3 intento_base
  sin usuario ni GUC no enfrían» y ensayo equivalente en el postflight.
- **[P3] Justificación del DEFINER** → redactada como B1 (INVOKER también valdría; no amplía ámbito).
- **[P3] Ensayo del postflight sobre una fila real** → elige el descartado MÁS ANTIGUO del analista; documentado el candado
  breve y el abort por `lock_timeout` (fail-safe). Rollback garantizado (`ZZ0B4`); rastro = tuplas muertas/stats/WAL.
- **[P3] La reversa deja descansos fijados** → `raise notice` con cuántos quedan y hasta cuándo (expiran solos ≤ 30 días;
  reactivar los limpia; la puerta de Gerencia no existe aún).
- **[P3] Semántica post-descanso:** tras vencer los 30 días, UN intento sin rellamada ni cita vuelve a enfriar (el cupo del
  ciclo ya está agotado). Documentado y probado; **pendiente de confirmar con Miguel** si prefiere «3 intentos nuevos tras
  cada descanso» (contar desde `greatest(descartado_en, fin del último descanso)`).
- Matriz `test-rls.mjs`: añadidos el D12 negativo por la API (3.º con rellamada no enfría, 4.º sí) y el contrato fuera de
  banda del trigger (DEFINER postgres, search_path vacío, sin EXECUTE, AFTER INSERT con WHEN).

## Verificado sin hallazgo
Concurrencia por el núcleo sólida (`for update` del lead antes del conteo e INSERT; `count` en AFTER ve la fila nueva);
`enfriado_hasta < v_hasta` defensivo; GUC restaurado y revertido ante excepción; orden AFTER
`audit < zy_sla_versionado < zz_avance_etapa < zz_enfriamiento_base < zz_temperatura` y ningún trigger previo cambia la
etapa; sin tablas/columnas nuevas, sin `public`, sin DELETE; `service_role` sin EXECUTE; ledger honesto.
