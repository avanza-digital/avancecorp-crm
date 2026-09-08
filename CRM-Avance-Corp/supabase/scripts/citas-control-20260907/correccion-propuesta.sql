-- PROPUESTA REVISADA: reparar solo el registro de control de Citas.
-- No aplicada en producción. La publicación 20260907194622 conservó la regla
-- de consumir citas_episodios, conversion_episodios y capital_episodios.
-- Actualiza la huella de un objeto y el sello de la lista en una transacción.
begin;
set local search_path='';
set local lock_timeout='5s';
set local statement_timeout='30s';
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('private.analitica_leads_citas_exenciones'),
  pg_catalog.hashtext('migracion'));
lock table private.analitica_leads_citas_exenciones in share row exclusive mode;
lock table private.analitica_lc_sello in share row exclusive mode;
lock table private.analitica_leads_citas_tope in share row exclusive mode;

do $control_citas$
declare
  v record; v_n integer; v_huella text;
  v_objeto constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_fila jsonb; v_otras jsonb; v_tope jsonb;
begin
  for v in select * from (values
      ('private.assert_analitica_leads_citas()','0b474e7f58e1f668b62a02730b716457'),
      ('private.capital_episodios(timestamp with time zone,timestamp with time zone,boolean,uuid[])','b8f375fbb377582835f4cfe222240c5b'),
      ('private.citas_episodios(timestamp with time zone,timestamp with time zone,timestamp with time zone)','ea636888a266941e959f26c6a5727216'),
      ('private.contadores_crudos_leads_citas()','34e0ae16a95912e5a5eedd4da845e288'),
      ('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)','8a2549dbfa59c732da04900ed90b6361'),
      ('private.huella_exenciones_analitica_lc()','817926e696fa554d8485e8e1aa6e9b73'),
      ('private.metricas_reuniones_implementacion(date,date)','cec7ee9ec1c31ddd8fa17f1d42e88fc1'),
      ('private.peso_referido_conversion(date)','3a80775b21767839e524880d419689f3')
    ) fuentes(firma,huella)
  loop
    if md5(pg_get_functiondef(v.firma::regprocedure)) is distinct from v.huella then
      raise exception 'Control Citas: cambio de fuente %, revisar antes de actualizar',v.firma;
    end if;
  end loop;

  if (select sello from private.analitica_lc_sello where id)
      is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'Control Citas: el sello previo no coincide; revisar la lista';
  end if;
  if (select count(*) from private.contadores_crudos_leads_citas()
      where not declarada or not huella_ok) <> 1
    or not exists(select 1 from private.contadores_crudos_leads_citas()
      where objeto=v_objeto and declarada and not huella_ok) then
    raise exception 'Control Citas: el fallo ya cambio o existen otras inconsistencias';
  end if;

  select to_jsonb(e) into strict v_fila
    from private.analitica_leads_citas_exenciones e where objeto=v_objeto;
  if v_fila->>'tipo' is distinct from 'funcion'
    or v_fila->>'huella' is distinct from '48702e1a8028340b3a26137027182c98'
    or v_fila->>'razon' is distinct from 'CONSUME LOS DOS NUCLEOS (citas_episodios para banderas, conversion_episodios para cierres): agrega filas ya servidas por los núcleos y expone el divisor y sus exclusiones por modalidad; no reconstruye esas reglas.' then
    raise exception 'Control Citas: cambio la declaracion que se reviso';
  end if;
  -- Expresión idéntica a contadores_crudos_leads_citas, fijado arriba por MD5.
  -- El control final usa el censo real y rechaza cualquier divergencia.
  select md5(regexp_replace(regexp_replace(
             lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
             '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) into v_huella
    from pg_proc p where p.oid=v_objeto::regprocedure;
  if v_huella is distinct from '4b28cc419c1b0d84fdbe43afdd5a0909' then
    raise exception 'Control Citas: huella normalizada diferente de la revisada';
  end if;

  select jsonb_agg(to_jsonb(e) order by objeto) into v_otras
    from private.analitica_leads_citas_exenciones e where objeto<>v_objeto;
  select to_jsonb(t) into strict v_tope from private.analitica_leads_citas_tope t where id;

  update private.analitica_leads_citas_exenciones
    set huella=v_huella
    where objeto=v_objeto and huella=v_fila->>'huella';
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'Control Citas: se esperaba actualizar una referencia'; end if;

  update private.analitica_lc_sello
    set sello=private.huella_exenciones_analitica_lc(),sellado_en=now()
    where id;
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'Control Citas: se esperaba actualizar un sello'; end if;

  if (select to_jsonb(e)-'huella' from private.analitica_leads_citas_exenciones e where objeto=v_objeto)
      is distinct from v_fila-'huella'
    or (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e where objeto<>v_objeto)
      is distinct from v_otras
    or (select to_jsonb(t) from private.analitica_leads_citas_tope t where id)
      is distinct from v_tope then
    raise exception 'Control Citas: se altero otra parte del registro';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
  perform private.assert_auditoria();
  perform private.assert_f7_piezas_cerradas();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
end;
$control_citas$;
select private.assert_analitica_leads_citas() as control_citas;
commit;
