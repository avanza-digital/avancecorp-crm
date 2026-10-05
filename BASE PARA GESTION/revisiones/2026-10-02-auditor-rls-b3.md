# auditor-rls · B3 (20261002231436_crm_base_gestion_puertas.sql) — 02/10/2026 (noche)

**VERDICT: CHANGES_REQUESTED → APLICADO el 02/10 (noche), reensayado 43/43 en banco.**

## Hallazgos y qué se hizo
- **[P1] KPI y sello falsificables:** `reactivacion_base`, la clave `respuesta` y `via = base_gestion` no estaban reservados en
  `crm.actividades` (el trigger «solo núcleo» sellado solo reserva las claves del resultado de llamada): un analista podía
  forjar por la API una «reactivación» (infla `reactivaciones_mes` del resumen) o un replay falso de «agendó cita».
  → Nuevo sello `trg_00_actividades_base_gestion_solo_nucleo` (BEFORE INSERT OR UPDATE OF metadata; GUC
  `crm.op_base_gestion`; exento sin usuario). El insert de la reactivación y los `update … respuesta` van bajo el GUC.
  Negativos en banco (3) y en `test-rls.mjs` (2); postflight con forja.
- **[P2] Orden de candados invertido** (lead → persona) al componer `reabrir_lead_fn` → persona ANTES que lead (READ COMMITTED,
  candado compartido de la bandera, `private.bloquear_personas_de_leads`) en `reactivar_core` y en `intento_core` cuando el
  resultado es `agendo_reunion`, como `llamada_registrar`.
- **[P2] Idempotencia leída antes del candado** (dos clics concurrentes → 23505 crudo) → el replay se lee DESPUÉS del
  `for update` del lead y solo entre operaciones del mismo actor (`creado_por = p_actor`, también P3 del oráculo).
- **[P3] Atribución del resumen** → por DUEÑO del lead (lo que Supervisión registra sobre un lead del analista cuenta para
  el analista); `p.activo` añadido; documentado en `comment on`.
- **[P3] Ayudantes DEFINER sin necesidad** → `base_gestion_rol` y `base_gestion_lead_visible` pasan a INVOKER.
- **[P3] UPDATE incondicional de `proxima_llamada_en`** → `is distinct from`.
- 23505 «otro contenido» comparte SQLSTATE con el índice de contacto vivo al reabrir: documentado en la cabecera (el front
  distingue por texto).

## Verificado sin hallazgo
Sin fuga de ámbito ni PII: la CTE `base` filtra todo por `base_gestion_lead_visible`; `p_vendedor_id` se valida por rol;
`vendedor_ids_visibles` siempre recibe `auth.uid()`; ACL exacta; nada sellado se reemplaza; GUCs de transacción se revierten
al abortar; triggers del UPDATE a `contactado` inofensivos; `md5(op||':reactivar')::uuid` válido y determinista; postflight sin
escrituras; reversa coherente.

## Riesgos de regresión señalados
«Agendó cita» es todo-o-nada (si la reactivación falla, el intento no se registra: correcto; el front traduce 23505/P0409/
P0429/P0001). `base_gestion_lead_visible` evalúa `vendedor_ids_visibles` por fila para Supervisión: medir con EXPLAIN en la
rama con datos.
