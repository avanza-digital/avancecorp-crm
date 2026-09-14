-- SOLO LECTURA. Ejecutar inmediatamente antes de una futura instalación autorizada.
begin read only;
set local statement_timeout='30s';
do $guard$ begin
 if md5(pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure))
   is distinct from '8b2eeffc547a1c095926ddb76876d262' then
   raise exception 'Deriva del lector de Citas: volver a comparar y ensayar';
 end if;
 if md5(pg_get_functiondef('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure))
   is distinct from 'c9e58c1da9dd7a5d52991c9e47dc19d5' then
   raise exception 'Deriva del núcleo de capital: revisar contrato del ticket';
 end if;
 if to_regclass('crm.control_citas_aplicaciones') is not null or to_regclass('crm.control_citas_versiones') is not null then
   raise exception 'Hay configuración instalada: conciliar el historial antes de continuar';
 end if;
end $guard$;
select private.assert_analitica_leads_citas();
select p.oid::regprocedure::text as firma,md5(pg_get_functiondef(p.oid)) as huella,
 pg_get_userbyid(p.proowner) as propietario,p.prosecdef as security_definer,p.proconfig,p.proacl::text as permisos
from pg_proc p where p.oid in (
 'private.citas_gerencia_consulta(date,date)'::regprocedure,
 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure,
 'public.es_superadmin()'::regprocedure,
 'private.rol_crm(uuid)'::regprocedure);
rollback;
