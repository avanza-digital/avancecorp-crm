# Paso 3a en producción, 17/10/2026 (Miguel con «!», desde la copia aislada; `npx supabase db query --linked --file`)

Decisión de Miguel (17/10, 4:45 p. m.): acepta la excepción de latencia de `estado` (NO PASA del arnés con la misma CPU) y aplicar hoy.

## 1. verificar.sql — ANTES (≈16:46)
- SERIE=ANTES · familia SLA=62 · 1adaf6c5708637fd916705cc090a4218 (la esperada) · GATE SERIE COMPLETA: NO · exigidas IGUALES
- ámbito y `_filas` AUSENTES; autorizada, resumen, cola y guardianes = ANTES
- Historial de la serie en el índice: ANTES · coincide: SÍ · eventos: ninguno
- Versiones del índice posteriores a 20261017054425 que no son de la serie: **0**
- ACL piezas privadas: ninguna (efectiva y guardada) · puertas: authenticated, crm_gestion_diaria_lector
- **Censo analítico: 46 · 197ca5defd92b36247b1ae899301be13** (referencia para los pasos siguientes: tiene que quedar IGUAL)
- assert_sla_nucleo, assert_cola_v3, assert_sla_avisos: **OK**
- Ajenos en rojo (preexistentes, no del SLA): assert_gestion_diaria (trg_sla_recibo_guard), assert_analitica_leads_citas
  (cartera_filtrada_fn), assert_analista_vigencia (proteger_campos_inmutables), assert_f7_piezas_cerradas (crear_contrato_con_cuenta, #317)

## 2. M1 `20261017054425_crm_sla_ventana_por_filas` (≈16:50)
- Sin error (`rows: []`): COMMIT.

## 3. verificar.sql tras M1 (≈16:51)
- SERIE=M1 · 64 · 1a632cfd48a2cc1602646a8fb0fb5285 (la esperada) · exigidas IGUALES · ámbito, `_filas`, autorizada, nucleo y avisos(guardián) = M1
- Historial: ANTES · coincide NO (esperado: el registro va al final con registrar-indice) · posteriores ajenas 0 · ACL ninguna
- Censo 46 · 197ca5de… IGUAL · 3 guardianes del SLA OK · ajenos igual que antes

## 4. M2 `20261017054426_crm_sla_avisos_por_filas` (≈16:52)
- Sin error (`rows: []`): COMMIT.

## 5. verificar.sql tras M2 (≈16:53)
- SERIE=M2 · 64 · 5e4e27c4548576663fa65b801a839f0e (la esperada) · exigidas IGUALES · resumen y guardián de avisos = M2
- Historial ANTES · coincide NO (registro al final) · posteriores ajenas 0 · ACL ninguna · censo 46 · 197ca5de… IGUAL · 3 guardianes del SLA OK

## 6. M3 `20261017054427_crm_sla_cola_por_filas` (≈16:54)
- Sin error (`rows: []`): COMMIT.

## 7. verificar.sql tras M3 (≈16:57)
- SERIE=M3 · 64 · f9ea903841b9186ac985e103e050e6d5 (la esperada) · **GATE SERIE COMPLETA: OK** · exigidas IGUALES · cola y guardián de cola = M3
- Historial ANTES · coincide NO (falta registrar) · posteriores ajenas 0 · ACL ninguna · censo 46 · 197ca5de… IGUAL · 3 guardianes del SLA OK

## 8. registrar-indice.sql (≈16:58)
- «REGISTRO: serie M3 · 3 versión(es) nueva(s) y 0 ya vigente(s) del mismo evento · versiones del índice posteriores a 20261017054425 que no son de la serie: 0»

## 9. Después de aplicar (16:59–17:00)
- **Advisors de seguridad y rendimiento:** sin alertas nuevas.
  - `sla_operacion_ambito`, `sla_operacion_autorizada_filas` y `sla_operacion_autorizada` no aparecen.
  - `crm.avisos_sla_resumen_v2_fn` y `crm.cola_accion_v3_fn` siguen en la lista de siempre de DEFINER ejecutables por
    `authenticated`, con la ACL sin cambios: `verificar.sql` lo comprobó en cada paso.
- **Logs desde las 16:45:**
  - 0 errores de Postgres (ERROR/FATAL/PANIC), sin contar los P0001 de `verificar.sql`;
  - las RPC responden 200: `avisos_sla_resumen_v2_fn` 27, `estado_sla_leads_v2_fn` 19, `gestion_diaria_avisos_fn` 10,
    `gestion_diaria_cola_trabajo_fn` 1 y `gestion_diaria_analista_fn` 1.
