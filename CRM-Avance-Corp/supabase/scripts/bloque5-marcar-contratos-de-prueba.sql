-- ============================================================================
-- F2.b · BLOQUE 5 de activación — el cliente de PRUEBA deja de contar como capital real
-- ============================================================================
-- QUÉ: «PRUEBA CLEINTE» (clienteprueba2@gmail.com, documento «2026», inválido) tiene DOS contratos
-- activos que hoy NO están marcados como prueba y, por tanto, suman en el capital y en las métricas:
--   · 2026-01-645645  PEN 100 000  (16/06/2026, nuevo)
--   · 2026-01-000009  USD  10 000  (31/07/2026, renovación)
-- Decisión de Miguel (06/09/2026): marcarlos como PRUEBA y dejar la cuenta del cliente activa.
-- El otro caso del censo, «SANCHEZ KIRK» (sin documento), se deja como está: su único contrato ya
-- estaba marcado como prueba.
--
-- CÓMO: por la ÚNICA puerta prevista, `public.marcar_contrato_demo(contrato, es_demo, motivo)`:
-- solo Gerencia, motivo obligatorio, rechaza contratos con operaciones de cartera y rechaza meses
-- ya sellados (ninguno de los dos lo está: junio y julio de 2026 siguen abiertos; 0 operaciones).
-- Deja rastro doble en `public.audit_log`: el UPDATE y una fila hermana con el motivo.
--
-- IDENTIDAD: la puerta exige una sesión de Gerencia, así que se fija la del ADMINISTRADOR AVANCE
-- CORP (superadmin del portal, gerencia del CRM). Si prefieres que quede a nombre de CARLOS VALLES,
-- cambia el uuid por 'ebb19751-5976-4446-91ec-03382247d8b8' antes de ejecutar.
--
-- EFECTO: el capital vivo de la empresa baja en PEN 100 000 y USD 10 000 (los que nunca debieron
-- contar). Reversible por la misma puerta con `false` y su motivo, mientras el mes siga abierto.
-- ============================================================================
begin;
set local lock_timeout = '10s';
select set_config('request.jwt.claims',
       json_build_object('sub', 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127', 'role', 'authenticated')::text, true);
set local role authenticated;

select public.marcar_contrato_demo(
  'f6ec5c4a-b156-406b-944d-dc90d4766ef3'::uuid, true,
  'Cliente de prueba (PRUEBA CLEINTE, documento invalido): el contrato era un ensayo y estaba contando como capital real. Bloque 5 de activacion F2.b, 06/09/2026.'
) as contrato_2026_01_000009;

select public.marcar_contrato_demo(
  '5a373238-fe14-4dce-8b0c-c7eb27b2dcc3'::uuid, true,
  'Cliente de prueba (PRUEBA CLEINTE, documento invalido): el contrato era un ensayo y estaba contando como capital real. Bloque 5 de activacion F2.b, 06/09/2026.'
) as contrato_2026_01_645645;

reset role;
select numero_contrato, es_demo, estado from public.contratos
where cliente_id = '69e91647-7b6d-4824-bff3-d8fe54766d69' order by numero_contrato;
commit;
