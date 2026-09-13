-- Sólo preparación del banco desechable después de la comparación RLS.
-- Configuración pública de negocio del padre; actor sustituido por usuario ficticio.
-- El singleton nace antes del trigger en la migración original. Reproducimos
-- esa inicialización en una transacción y reactivamos la guarda antes de probar.
begin;
do $$ begin assert not exists(select 1 from crm.sla_operacion_control); end $$;
alter table crm.sla_operacion_control disable trigger trg_sla_nucleo_guard;
insert into crm.sla_operacion_control(id,modo,revision,cambiado_en,cambiado_por,politica_adopcion_id,primera_activacion_en)
select true,'activo',1,'2026-09-07 04:03:49.941009+00',id,
 'ee276f9b-07ef-4f1e-9689-6e16b16d7eb6','2026-09-07 04:03:49.941009+00'
from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe';
alter table crm.sla_operacion_control enable trigger trg_sla_nucleo_guard;
commit;
select 'CONTROL_SLA_SINTETICO_LISTO';
