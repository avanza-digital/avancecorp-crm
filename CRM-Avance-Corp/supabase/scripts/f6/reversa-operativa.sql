-- Reversa F6: detener nuevas gestiones y ocultar la agenda neutral.
-- No borra tareas, recibos, solicitudes, historia ni inversiones.
-- El mantenimiento de identidad sigue sincronizando dueño/canónica/veto.
-- La consulta del recibo propio permanece disponible para resolver un corte.
begin;
set local lock_timeout='5s';
select nombre from crm.multiempresa_flags where nombre='postventa_neutral' for update;
update crm.multiempresa_flags set activo=false where nombre='postventa_neutral';
commit;
