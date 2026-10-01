-- APAGAR la marca de potencial del lead (bandera 'potencial_lead'): el interruptor de emergencia.
-- Lo lanza Miguel con `!`. Con la bandera apagada la puerta de marcar se niega (55000) y la de lectura
-- devuelve habilitada=false: la pantalla deja de pintar el potencial en su siguiente lectura. Las
-- marcas y su historial SE QUEDAN (nada se borra) y la tarea diaria sigue bajando las que existan; al
-- volver a encender, reaparecen como estén. UN solo UPDATE en su propia transacción corta.
-- Bitácora: public.audit_log (sin actor desde `db query`: anotar en MIGRACIONES.md quién y cuándo).
begin;
set local lock_timeout = '30s';
do $chk$
begin
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead') then
    raise exception 'APAGAR potencial_lead: no existe la bandera (la fase 1 no está aplicada)';
  end if;
end;
$chk$;
update crm.multiempresa_flags set activo = false, actualizado_en = pg_catalog.now() where nombre = 'potencial_lead';
do $post$
begin
  if (select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead') is distinct from false then
    raise exception 'APAGAR potencial_lead: la bandera no quedó apagada';
  end if;
  raise notice 'APAGAR potencial_lead OK: bandera apagada; marcas conservadas %.', (select pg_catalog.count(*) from crm.lead_potencial);
end;
$post$;
commit;
