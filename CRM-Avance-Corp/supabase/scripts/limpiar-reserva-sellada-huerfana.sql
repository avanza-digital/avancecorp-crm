-- ============================================================================
-- HIGIENE previa al encendido — la ÚNICA reserva sellada que quedó colgada de la vía APAGADA
-- ============================================================================
-- QUÉ ES. `crm.conversion_reservas` marca `efectos_iniciados_en` cuando una conversión empieza a
-- crear la cuenta del Portal. En producción hay 19 filas selladas: 18 son de leads ya convertidos
-- (normal, son el rastro de su conversión) y UNA quedó colgada:
--
--   lead 9d6ee71f-071b-4130-95c6-7ba602e63b4b («Maria Luisa»), sellada el 27/08/2026 15:06 UTC,
--   tope absoluto vencido el 27/08 15:36, lead hoy en etapa `descartado` y ACTIVO,
--   `inversionista_id` NULL, sin claim de idempotencia, y el lead NO TIENE DOCUMENTO.
--
-- CUÁNTO ESTORBA: nada. Se comprobó en producción en solo lectura el 06/09: al no tener documento,
-- con la identidad ENCENDIDA no resuelve a ninguna persona, así que no puede bloquear el alta, la
-- toma ni la conversión de nadie; y el lead está descartado. NO es un prerrequisito del encendido.
-- Se deja preparado porque es suciedad reconocible y Gerencia puede querer la tabla limpia.
--
-- CÓMO CORRERLO (solo si Miguel lo pide): `npx supabase db query --linked --file <este archivo>`.
-- Es idempotente y se niega si la fila ya no cumple EXACTAMENTE el perfil de arriba.
-- ============================================================================
begin;
set local lock_timeout = '5s';
do $limpieza$
declare
  v_lead uuid := '9d6ee71f-071b-4130-95c6-7ba602e63b4b';
  v_n    integer;
begin
  if not exists (
    select 1 from crm.conversion_reservas r join crm.leads l on l.id = r.lead_id
     where r.lead_id = v_lead
       and r.efectos_iniciados_en is not null
       and r.inversionista_id is null
       and r.vence_absoluto_en < now()
       and l.etapa = 'descartado'
       and nullif(pg_catalog.btrim(coalesce(l.dni, '')), '') is null) then
    raise notice 'LIMPIEZA: la fila ya no está o ya no cumple el perfil descrito; no se toca nada.';
    return;
  end if;
  -- El rastro es automático: `trg_audit_conversion_reservas` (AFTER INSERT/UPDATE/DELETE) escribe la
  -- fila entera en `public.audit_log` con su `data_antes`. No hace falta anotarlo a mano, y hacerlo
  -- duplicaría el asiento.
  delete from crm.conversion_reservas where lead_id = v_lead;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'LIMPIEZA: se esperaba borrar exactamente 1 fila y se borraron %', v_n;
  end if;
  raise notice 'LIMPIEZA OK: reserva sellada huérfana del lead % retirada, con rastro en public.audit_log.', v_lead;
end
$limpieza$;
commit;
