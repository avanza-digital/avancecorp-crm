-- Banco autorizado y desechable. Todo cambio deliberado termina en rollback.
-- Ejecutar con el runner de rama que verifica el destino antes de conectar.
begin;
create or replace function pg_temp.rechaza_alteracion(p_nombre text,p_cambio text,p_error text)
returns void language plpgsql as $$
declare mensaje text;
begin
  perform private.assert_analitica_leads_citas();
  begin
    execute p_cambio;
    begin
      perform private.assert_analitica_leads_citas();
    exception when others then mensaje:=sqlerrm; end;
    if mensaje is null or mensaje not like p_error then
      raise exception 'MUTANTE SOBREVIVIÓ o falló por otra causa [%]: %',p_nombre,coalesce(mensaje,'gate verde');
    end if;
    raise exception using errcode='ZX001',message='Revertir exclusivamente este mutante';
  exception when sqlstate 'ZX001' then null; end;
  perform private.assert_analitica_leads_citas();
  raise notice 'PASS %',p_nombre;
end $$;

create or replace function pg_temp.rechaza_escritura(p_nombre text,p_cambio text,p_error text)
returns void language plpgsql as $$
declare mensaje text;
begin
  perform private.assert_analitica_leads_citas();
  begin
    execute p_cambio;
  exception when insufficient_privilege then mensaje:=sqlerrm; end;
  if mensaje is null or mensaje not like p_error then
    raise exception 'ESCRITURA NO RECHAZADA por la protección esperada [%]: %',p_nombre,coalesce(mensaje,'aceptada');
  end if;
  perform private.assert_analitica_leads_citas();
  raise notice 'PASS %',p_nombre;
end $$;

do $$
declare a record; rol text; definicion text; nombre text; n integer; falsa text;
begin
  assert (select count(*) from private.contadores_crudos_leads_citas())=34,'Inventario completo visible';
  assert (select tope from private.analitica_leads_citas_tope where id)=30,'Techo conservado';
  assert (select count(*) from private.auxiliares_analitica_lc_auditados() where vigente)=4,'Cuatro auxiliares verificados';
  for a in select * from private.auxiliares_analitica_lc_auditados() loop
    select pg_get_functiondef(to_regprocedure(a.objeto)) into definicion;
    perform pg_temp.rechaza_alteracion(a.objeto||' cuerpo',replace(definicion,E'begin\n',E'begin\n perform 1;\n'),'%auxiliar auditado cambió%');
    perform pg_temp.rechaza_alteracion(a.objeto||' configuración','alter function '||a.objeto||' set search_path=public','%auxiliar auditado cambió%');
    perform pg_temp.rechaza_alteracion(a.objeto||' propietario','grant create on schema crm,private to crm_metricas_bridge; alter function '||a.objeto||' owner to crm_metricas_bridge','%auxiliar auditado cambió%');
    foreach rol in array array['public','anon','authenticated','service_role'] loop
      if not has_function_privilege(rol,to_regprocedure(a.objeto),'EXECUTE') then
        perform pg_temp.rechaza_alteracion(a.objeto||' grant '||rol,'grant execute on function '||a.objeto||' to '||rol,'%auxiliar auditado cambió%');
      end if;
    end loop;
    perform pg_temp.rechaza_alteracion(a.objeto||' grant option','grant execute on function '||a.objeto||' to authenticated with grant option','%auxiliar auditado cambió%');
    perform pg_temp.rechaza_alteracion(a.objeto||' renombrada','alter function '||a.objeto||' rename to auxiliar_renombrado_prueba','%auxiliar auditado cambió%');
    perform pg_temp.rechaza_escritura(a.objeto||' declaración protegida',format('delete from private.analitica_leads_citas_exenciones where objeto=%L',a.objeto),'Una exencion no se borra por fuera:%');
    -- Si se desplaza la identidad sin borrar, el gate sigue exigiendo su declaración.
    perform pg_temp.rechaza_alteracion(a.objeto||' declaración desplazada',format('update private.analitica_leads_citas_exenciones set objeto=%L where objeto=%L',a.objeto||'.desplazada',a.objeto),'%auxiliar auditado cambió%');
    perform pg_temp.rechaza_alteracion(a.objeto||' motivo sin sello',format('update private.analitica_leads_citas_exenciones set razon=razon||%L where objeto=%L',' alterada',a.objeto),'%sin re-sellarse%');
  end loop;
  foreach rol in array array['public','anon','authenticated','service_role'] loop
    perform pg_temp.rechaza_alteracion('helper grant '||rol,'grant execute on function private.auxiliares_analitica_lc_auditados() to '||rol,'%clasificación fija%');
  end loop;
  perform pg_temp.rechaza_alteracion('helper propietario','grant create on schema private to crm_metricas_bridge; alter function private.auxiliares_analitica_lc_auditados() owner to crm_metricas_bridge','%clasificación fija%');
  -- Cero, tres, cinco y cuatro duplicados nunca son un conjunto aceptable.
  foreach n in array array[0,3,5,4] loop
    falsa:=format('create or replace function private.auxiliares_analitica_lc_auditados() returns table(objeto text,razon text,vigente boolean) language sql stable security definer set search_path='''' as $mut$ select ''auxiliar repetido''::text,''falso''::text,true from generate_series(1,%s) $mut$',n);
    perform pg_temp.rechaza_alteracion('helper conjunto '||n,falsa,'%clasificación fija%');
  end loop;
  perform pg_temp.rechaza_alteracion('sobrecarga no autorizada',$mut$
    create function crm.metricas_multiempresa_fn(date,text) returns integer language sql as $q$ select count(*)::integer from crm.leads $q$
  $mut$,'%SIN declarar%');
  perform pg_temp.rechaza_alteracion('copia en otro esquema',$mut$
    create function private.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamptz,uuid)
    returns integer language sql as $q$ select count(*)::integer from crm.leads $q$
  $mut$,'%SIN declarar%');
  perform pg_temp.rechaza_alteracion('contador nuevo declarado supera techo',$mut$
    create function crm.contador_nuevo_prueba() returns integer language sql as $q$ select count(*)::integer from crm.leads $q$;
    insert into private.analitica_leads_citas_exenciones(objeto,tipo,huella,razon)
    select 'crm.contador_nuevo_prueba()','funcion',md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),'Declaración sintética para probar el techo'
    from pg_proc p where oid='crm.contador_nuevo_prueba()'::regprocedure;
    update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc() where id;
  $mut$,'%subieron de 30 a 31%');
end $$;
select private.assert_analitica_leads_citas() as resultado;
rollback;
