-- SOLO LECTURA. Repetir en la ventana previa a instalar.
-- Las filas previas recibirán base_plazo='calendario'. Se exige TRUE, no UNKNOWN.
select count(*) as total,
  count(*) filter(where plazo_meses is not null) as con_condiciones,
  count(*) filter(where ((plazo_meses is null and tasa_anual is null)
    or (plazo_meses is not null and tasa_anual is not null
      and plazo_meses between 1 and 1200
      and tasa_anual not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
      and tasa_anual>0 and tasa_anual=trunc(tasa_anual,2)
      and vence_en is not null and isfinite(vence_en)
      and vence_en=(coalesce(fecha_comercial,(creado_en at time zone 'America/Lima')::date)
        + make_interval(months=>plazo_meses))::date)) is not true) as incompatibles
from crm.cierres_externos;

select pg_get_constraintdef(oid) as check_anterior,
  md5(pg_get_constraintdef(oid)) as huella
from pg_constraint where conrelid='crm.cierres_externos'::regclass
  and conname='cierres_coopac_condiciones_completas';

select pg_get_functiondef('crm.inversionista_gestion_fn(uuid,uuid)'::regprocedure) as lectura_revision;

select p.oid::regprocedure::text as llamador
from pg_proc p where p.prokind='f'
  and p.pronamespace in ('crm'::regnamespace,'private'::regnamespace,'public'::regnamespace)
  and pg_get_functiondef(p.oid) like '%coopac_validar_condiciones%';

select pg_describe_object(classid,objid,objsubid) as dependiente,deptype
from pg_depend where refclassid='pg_proc'::regclass
  and refobjid='private.coopac_validar_condiciones(date,integer,numeric)'::regprocedure;
