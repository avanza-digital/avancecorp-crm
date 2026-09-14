-- Reversa operativa F8: corta el piloto sin borrar miembros, inversiones,
-- postventa, auditoría ni ninguna otra historia.
begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
update crm.piloto_f8_control
set activo=false,
  motivo='Reversa operativa controlada F8'
where singleton;
update crm.piloto_f8_miembros
set activo=false,
  motivo='Reversa operativa controlada F8'
where activo;
commit;
