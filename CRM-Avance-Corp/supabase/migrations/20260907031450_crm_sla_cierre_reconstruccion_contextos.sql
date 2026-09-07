-- Aplicar solo DESPUES de ejecutar y verificar los lotes de reconstruccion.
-- No altera ni borra contextos. Recuperaciones posteriores requieren reinstalar
-- el helper exacto revisado, reconciliar el hueco y retirar nuevamente la puerta.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
drop function private.sla_reconstruir_contextos_lote(uuid[]);
drop function private.sla_cadena_tarea_reconstruible(uuid,uuid,timestamptz);
select private.assert_sla_operacion();
commit;
