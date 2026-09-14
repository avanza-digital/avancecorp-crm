-- SOLO LECTURA. Ejecutar de nuevo justo antes del despliegue autorizado.
select p.oid::regprocedure::text as funcion, md5(p.prosrc) as md5_instalado,
       e.huella as md5_requerido, md5(p.prosrc)=e.huella as coincide,
       pg_get_userbyid(p.proowner) as propietario, p.prosecdef, p.proconfig, p.proacl
from (values
 ('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)','9822f3d4d45d0fc5767c599ea871da94'),
 ('private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)','6a9509dd1a4131042d578d3d7d673cbc'),
 ('private.trg_contratos_observar_rentabilidad()','3e0390e96137c503e5f28a55fe6c04c0'),
 ('public.crear_contrato(jsonb,jsonb)','2f619ddf650bd0db2ffa64790f894312')
) e(firma,huella)
left join pg_proc p on p.oid=to_regprocedure(e.firma);

select to_regprocedure('private.rentabilidad_minimo_alta(text,numeric)') is null as helper_aun_no_instalado;

select version,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo
from crm.politica_rentabilidad where vigente_desde<=now()
order by vigente_desde desc,version desc limit 1;
