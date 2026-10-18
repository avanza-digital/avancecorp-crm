-- Reversa de 20261018032400_crm_recuperar_ventas_recargadas.sql. Devuelve a su huella anterior las CUATRO funciones que
-- la migración parchó (private.cierre_anulado, crm.cierres_estado_fn, crm.altas_nuevas_por_analista_fn y
-- crm.anular_cierre_avance): las dos ventas rehabilitadas (anuladas al borrar) vuelven a contar como ANULADAS, a salir como
-- «CIERRE ANULADO» y fuera de «Altas nuevas».
-- NO deshace lo que no tiene vuelta: las acreditaciones no regresan a los contratos borrados (ya no existen: el escritor lo
-- rechaza), así que 1, 2 y 5 SIGUEN contando; las fechas comerciales corregidas de 2 y 5 no vuelven solas (están en el
-- respaldo de cada fila: se devuelven, si hace falta, con «Corregir fecha comercial» de Gerencia), y la tabla
-- crm.conversion_ventas_recuperadas y sus filas se conservan como historia (solo inserción), igual que las notas.
-- Se niega si el mes de alguna venta recuperada ya está sellado o su venta ya entró en un sello.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), como la migración.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level read committed;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table crm.periodos_cerrados in share mode;

create temporary table reversa_funciones on commit drop as
select p.oid as oid, p.oid::regprocedure::text as firma, p.proowner, p.prosecdef, p.provolatile, p.proconfig, p.proacl
from pg_catalog.pg_proc p
where p.oid in ('private.cierre_anulado(uuid)'::regprocedure, 'crm.cierres_estado_fn(uuid[])'::regprocedure,
                'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, 'crm.anular_cierre_avance(uuid,text)'::regprocedure);

do $preflight$
begin
  if (select pg_catalog.string_agg(f.firma || '=' || md5(pg_catalog.pg_get_functiondef(f.oid)), ',' order by f.firma) from pg_temp.reversa_funciones f)
     is distinct from 'crm.altas_nuevas_por_analista_fn(integer)=7136e6ea0786ae7ec166a7957f6e77d2,'
                      'crm.anular_cierre_avance(uuid,text)=9625124158f7d2d04a2a59c4be405942,'
                      'crm.cierres_estado_fn(uuid[])=965b778f15e64d3b5f41b257d6469ec8,'
                      'private.cierre_anulado(uuid)=878d19fffc19bc39649a5105bd51b082' then
    raise exception 'REVERSA recuperar_ventas: las funciones no tienen la huella que dejó la migración';
  end if;
  if exists (select 1 from crm.conversion_ventas_recuperadas r
             join crm.conversion_acreditaciones ca on ca.id = r.acreditacion_id
             where ca.incluida_en_sello is true or ca.sellado_en is not null
                or exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= ca.periodo_comercial)) then
    raise exception 'REVERSA recuperar_ventas: el mes de una venta recuperada ya está sellado; un mes sellado no se reescribe';
  end if;
  -- Cardinalidad (Codex 18/10): toda fila tiene su acreditación (no hay FK a propósito); si falta una, revisar antes.
  if (select count(*) from crm.conversion_ventas_recuperadas r
      join crm.conversion_acreditaciones ca on ca.id = r.acreditacion_id and ca.lead_id = r.lead_id)
     <> (select count(*) from crm.conversion_ventas_recuperadas) then
    raise exception 'REVERSA recuperar_ventas: una venta recuperada ya no tiene su acreditación; requiere revisión';
  end if;
end
$preflight$;

create function pg_temp.desparchar(p_funcion regprocedure, p_quitar text[]) returns void language plpgsql as $$
declare
  v_def text := pg_catalog.pg_get_functiondef(p_funcion);
  i integer;
begin
  for i in 1 .. array_length(p_quitar, 1) loop
    if (length(v_def) - length(replace(v_def, p_quitar[i], ''))) / length(p_quitar[i]) <> 1 then
      raise exception 'REVERSA %: el texto % no aparece exactamente una vez', p_funcion, i;
    end if;
    v_def := replace(v_def, p_quitar[i], '');
  end loop;
  execute v_def;
end $$;

select pg_temp.desparchar('private.cierre_anulado(uuid)'::regprocedure, array[
'      -- 18/10/2026: salvo que esa anulación exacta se haya rehabilitado (crm.conversion_ventas_recuperadas).
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
',
'      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.inversion_eliminada_id = ie.id)
']);
select pg_temp.desparchar('crm.cierres_estado_fn(uuid[])'::regprocedure, array[
'      -- 18/10/2026: una anulación rehabilitada (crm.conversion_ventas_recuperadas) ya no se muestra como vigente.
      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
']);
select pg_temp.desparchar('crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, array[
'    -- 18/10/2026: salvo una anulación rehabilitada (crm.conversion_ventas_recuperadas).
    where not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)
']);
select pg_temp.desparchar('crm.anular_cierre_avance(uuid,text)'::regprocedure, array[
'  -- 18/10/2026: una venta anulada y después recuperada (crm.conversion_ventas_recuperadas) no se vuelve a anular.
  if exists (select 1 from crm.conversion_ventas_recuperadas r
             where r.lead_id = p_lead_id and r.cierre_avance_anulado_id is not null) then
    raise exception using
      errcode = ''P0409'',
      message = ''Esta venta se anuló y después se recuperó: no se vuelve a anular. Para corregir su inversión usa «Reemplazar inversión»'';
  end if;
']);

comment on function private.cierre_anulado(uuid) is
  'El cierre (conversión) del lead está anulado: cierre externo inicial anulado, anulación de Avance, o conversión anulada y eliminada (crm.inversiones_eliminadas).';
comment on table crm.conversion_ventas_recuperadas is
  'Ventas de leads recuperadas tras borrar y recargar su contrato (migración 20261018032400). REVERTIDA: las funciones ya no '
  'consultan esta tabla; las filas quedan como historia (solo inserción, sin API).';

do $postflight$
begin
  if (select pg_catalog.string_agg(f.firma || '=' || md5(pg_catalog.pg_get_functiondef(f.oid)), ',' order by f.firma) from pg_temp.reversa_funciones f)
     is distinct from 'crm.altas_nuevas_por_analista_fn(integer)=b421dfb1f3a317776d9e4e1b9e69dd76,'
                      'crm.anular_cierre_avance(uuid,text)=03b673084dbbbbff7aef21c12e7f30b5,'
                      'crm.cierres_estado_fn(uuid[])=f543c8090d2266f26cfbcd6649b783f4,'
                      'private.cierre_anulado(uuid)=df71c2b1e3cd44b97c3ad84e00637266' then
    raise exception 'REVERSA recuperar_ventas: las funciones no volvieron a su huella anterior';
  end if;
  if exists (select 1 from pg_temp.reversa_funciones f join pg_catalog.pg_proc p on p.oid = f.oid
             where p.proowner is distinct from f.proowner or p.prosecdef is distinct from f.prosecdef
                or p.provolatile is distinct from f.provolatile or p.proconfig is distinct from f.proconfig
                or p.proacl is distinct from f.proacl) then
    raise exception 'REVERSA recuperar_ventas: cambiaron dueño, seguridad, volatilidad, configuración o permisos de una función';
  end if;
end
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
