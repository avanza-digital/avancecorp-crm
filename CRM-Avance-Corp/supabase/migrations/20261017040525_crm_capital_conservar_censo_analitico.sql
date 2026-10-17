-- Mantiene el censo analítico vigente al extraer el núcleo y añadir su lector
-- de Citas por corte. No levanta el tope ni recertifica deuda ajena.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table private.analitica_leads_citas_exenciones,private.analitica_lc_sello,
  private.analitica_leads_citas_tope in share row exclusive mode;

do $censo$
declare f record; v_huella text; v_n integer;
  v_cierre text:='crm.cerrar_periodo(date)';
begin
  -- Banco de solo esquema: todavía no existe una certificación que conservar.
  if not exists(select 1 from private.analitica_leads_citas_exenciones) then return; end if;
  if md5(pg_catalog.pg_get_functiondef('private.contadores_crudos_leads_citas()'::regprocedure))<>'6a5d2a2ed9e6442aff17d598af6d59da'
    or md5(pg_catalog.pg_get_functiondef('private.huella_exenciones_analitica_lc()'::regprocedure))<>'ad7d8cfd4e4f4ae6f1c2c3fecf51bb99'
    or (select sello from private.analitica_lc_sello where id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'Censo analítico no compatible o sello desactualizado: revisar antes de publicar capital por venta';
  end if;
  -- Solo esta declaración cambió de cuerpo; conservar su razón y clase.
  if (select huella from private.analitica_leads_citas_exenciones where objeto=v_cierre)
    is distinct from '4b89856af0ebc6c4e46f6ffef8be61af' then
    raise exception 'Cambió la declaración del cierre: no recertificar otra versión';
  end if;
  select md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^
]*',' ','g'),'/\*.*?\*/',' ','g'))
    into v_huella from pg_proc p where p.oid=v_cierre::regprocedure;
  if v_huella is distinct from '516d20ef47df1332de58a4dd6384bf5b' then
    raise exception 'El cuerpo del cierre no es el revisado para capital por venta';
  end if;
  update private.analitica_leads_citas_exenciones set huella=v_huella where objeto=v_cierre;
  -- Misma pregunta analítica de las piezas nativas; nuevos nombres por la
  -- proyección por operación y el lector de la publicación aceptada.
  for f in select * from (values
    ('private.produccion_operaciones(timestamp with time zone,timestamp with time zone,uuid)',
      '6d455505b11520edd3752e84e0bbe672',
      'Producción canónica por operación extraída del agregado nativo: conserva sus counts de enlaces/atribución y no calcula otra conversión.'),
    ('private.citas_gerencia_consulta_corte(date,date,uuid)',
      '5ac87f541dd94f0a8f5e55ad2042e830',
      'Lector analítico nativo de Citas con las mismas puertas, cohortes y PII; sustituye solo capital/población monetaria por el corte completo aceptado. No redefine conversión.')
  ) p(objeto,huella,razon) loop
    select md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^
]*',' ','g'),'/\*.*?\*/',' ','g'))
      into v_huella from pg_proc p where p.oid=f.objeto::regprocedure;
    if v_huella is distinct from f.huella
      or exists(select 1 from private.analitica_leads_citas_exenciones e where e.objeto=f.objeto) then
      raise exception 'Pieza analítica nueva no coincide con la revisada: %',f.objeto;
    end if;
    insert into private.analitica_leads_citas_exenciones(tipo,objeto,clase,razon,huella)
      values('funcion',f.objeto,'analitica',f.razon,f.huella);
  end loop;
  update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
  get diagnostics v_n=row_count;
  if v_n<>1 or exists(select 1 from private.contadores_crudos_leads_citas() c
    where c.objeto in(v_cierre,'private.produccion_operaciones(timestamp with time zone,timestamp with time zone,uuid)',
      'private.citas_gerencia_consulta_corte(date,date,uuid)') and (not c.declarada or not c.huella_ok)) then
    raise exception 'La certificación analítica de capital no quedó vigente';
  end if;
end $censo$;
commit;
