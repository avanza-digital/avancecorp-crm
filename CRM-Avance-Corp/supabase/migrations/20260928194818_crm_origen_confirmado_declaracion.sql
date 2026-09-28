-- Actualiza exclusivamente la huella del lector de origen modificado.
-- Mantiene clase, techo y todas las demas declaraciones del control analitico.
do $huella$
declare v_filas integer;
begin
  update private.analitica_leads_citas_exenciones e
  set huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),
      '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
  from pg_proc p
  where p.oid = 'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure
    and e.objeto = 'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)'
    and e.clase = 'analitica';
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then raise exception 'Se esperaba una declaracion del lector'; end if;
end;
$huella$;
update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;
do $postflight$
begin
  if exists(select 1 from private.contadores_crudos_leads_citas()
      where not declarada or not huella_ok) then
    raise exception 'Contadores o huellas pendientes';
  end if;
  if (select md5(prosrc) from pg_proc where oid =
      'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
      is distinct from '214c6bada3dc63f553d7f9b62fd7963c'
    or (select md5(prosrc) from pg_proc where oid =
      'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
      is distinct from 'ecfdf7e030497af2f299ba327102a5ea' then
    raise exception 'Cambio el nucleo monetario';
  end if;
end;
$postflight$;
