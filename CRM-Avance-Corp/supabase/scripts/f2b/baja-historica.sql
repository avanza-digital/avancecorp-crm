-- LEEME-seed.md → «Baja historica de vendInactive». Estado HEREDADO: alguien
-- que YA tenia leads abiertos cuando se fue del equipo. El esquema cierra las
-- dos vias normales (y con razon), asi que se construye fuera de banda.
begin;
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false
 where perfil_id = (select id from public.perfiles where nombre_completo = 'ANALISTA INACTIVO');
alter table crm.equipo enable trigger user;
update public.perfiles set activo = false
 where nombre_completo = 'ANALISTA INACTIVO';
commit;
-- Se devuelve el permiso prestado para la siembra: el banco vuelve a la
-- paridad exacta con produccion.
revoke select on crm.periodos_cerrados from service_role;
