-- Bloque documentado en supabase/scripts/LEEME-seed.md, «Baja historica de
-- vendInactive». El guardia se apaga para UNA sentencia y se reenciende en la
-- misma transaccion; el propio gate lo mide justo despues.
begin;
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false
 where perfil_id = (select id from public.perfiles where nombre_completo = 'ANALISTA INACTIVO');
alter table crm.equipo enable trigger user;
update public.perfiles set activo = false where nombre_completo = 'ANALISTA INACTIVO';
commit;
