-- Solo dentro de BEGIN/ROLLBACK, sobre F4 completo ya instalado.
create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'F4 revisión: %',mensaje; end if; end $$;
create function pg_temp.error_esperado(p_sql text,p_estado text) returns void language plpgsql as $$
declare recibido text; begin
  begin execute p_sql; exception when others then recibido:=sqlstate; end;
  perform pg_temp.afirmar(recibido is not distinct from p_estado,'Estado esperado '||p_estado||', recibido '||coalesce(recibido,'ninguno'));
end $$;

-- Hosted hereda USAGE auth de authenticated: no requiere un grant directo.
revoke usage on schema auth from crm_gestion_diaria_lector;
select pg_temp.afirmar(has_schema_privilege('crm_gestion_diaria_lector','auth','USAGE'),'Uso auth heredado');
select private.assert_gestion_diaria();

select set_config('request.jwt.claim.sub',(select perfil_id::text from crm.equipo
  where activo and rol_crm='gerencia' limit 1),true);
set local role authenticated;
do $$ declare c jsonb; config jsonb; fecha timestamptz; variante jsonb; begin
  c:=crm.configuracion_gestion_diaria_fn();
  config:=c#>'{vigente,configuracion}';
  fecha:=(((c->>'dia')::date+30)::timestamp at time zone 'America/Lima');
  for variante in select * from (values
    (config||'{"corte_1_hora":"09:00"}'),(config||'{"corte_1_hora":"13:00"}'),
    (config||'{"corte_2_hora":"18:00"}'),(config||'{"corte_2_hora":"10:00"}'),
    (config||'{"bien_min_pct":25,"atencion_min_pct":25}')
  ) t(config) loop
    perform pg_temp.error_esperado(format('select crm.publicar_politica_gestion_diaria(%s,%L,%L,%L)',
      c->>'expected_version',fecha,variante,'Rechazo directo de reglas'), '23514');
  end loop;
  perform pg_temp.error_esperado(format('select crm.publicar_politica_gestion_diaria(%s,%L,%L,%L)',
    c->>'expected_version',fecha+interval '1 minute',config,'Fuera de medianoche Lima'),'23514');
  perform pg_temp.afirmar(crm.configuracion_gestion_diaria_fn()->>'expected_version'=c->>'expected_version','No escribió reglas inválidas');
end $$;
reset role;

create temporary table revision_actor as select e.perfil_id vendedor,e.supervisor_id supervisor,
  gen_random_uuid() lead,clock_timestamp() desde from crm.equipo e
  where e.activo and e.rol_crm='vendedor' and private.rol_crm(e.supervisor_id)='supervisor' limit 1;
grant select on revision_actor to authenticated;
select crm.crear_lead_si_disponible(p_nombre_completo=>'LLAMADAS NO UTILES REVISION F4',p_telefono=>'999577991',
  p_origen=>'oficina',p_monto_estimado=>25000,p_moneda=>'PEN',p_id=>lead,p_vendedor_id=>vendedor,
  p_nota=>'Fixture reversible de llamadas no útiles') from revision_actor;
select set_config('request.jwt.claim.sub',vendedor::text,true) from revision_actor;
set local role authenticated;
select crm.registrar_llamada_v3(gen_random_uuid(),lead,'numero_errado',p_detalle=>'Número incorrecto en fixture reversible') from revision_actor;
select crm.registrar_llamada_v3(gen_random_uuid(),lead,'no_es_la_persona',p_detalle=>'Otra persona en fixture reversible') from revision_actor;
select pg_temp.afirmar(ll.llamadas=2 and ll.utiles=0 and ll.contestadas=0
  and ll.primera_llamada_en is not null and ll.ultima_llamada_en is not null,
  'Dos llamadas no útiles sí cuentan en llamadas y primera/última')
  from revision_actor a cross join lateral private.gestion_diaria_llamadas(a.desde,clock_timestamp(),array[a.vendedor]) ll;
reset role;
select set_config('request.jwt.claim.sub',supervisor::text,true) from revision_actor;
set local role authenticated;
select pg_temp.afirmar((crm.gestion_diaria_avisos_fn()#>>'{contexto,con_llamadas}')::integer>0,'Contexto reconoce llamadas no útiles');
reset role;

-- Demuestra que las escrituras no llaman al SLA, incluso cuando este falla.
do $independencia$ declare copia text; anterior text; r jsonb; aviso text; begin
  copia:=pg_get_functiondef('crm.gestion_diaria_reconocer_corte(text,text,uuid)'::regprocedure);
  perform pg_temp.afirmar(strpos(copia,'private.gestion_diaria_avisos(clock_timestamp())')>0,'POST usa núcleo de cortes');
  perform pg_temp.afirmar((select md5(prosrc)='7009218260658cfbf6ed096715d2a8d5'
    from pg_proc where oid='private.gestion_diaria_avisos(timestamptz)'::regprocedure),'Núcleo sin composición SLA');
  anterior:=pg_get_functiondef('private.gestion_diaria_alertas_sla()'::regprocedure);
  execute $fallo$create or replace function private.gestion_diaria_alertas_sla() returns jsonb
    language plpgsql stable security definer set search_path='' as $c$begin raise exception 'SLA caído de prueba'; end$c$$fallo$;
  r:=private.gestion_diaria_avisos(clock_timestamp());
  perform pg_temp.afirmar(r->>'version'='1' and not r?'diarias','Lectura de cortes independiente de SLA caído');
  aviso:=r#>>'{alertas,0,id}';
  perform pg_temp.afirmar(aviso is not null,'Caso no vacío para probar escritura');
  r:=crm.gestion_diaria_presentar_corte(aviso,gen_random_uuid());
  perform pg_temp.afirmar(r->>'version'='1','Presentación funciona con SLA caído');
  r:=crm.gestion_diaria_reconocer_corte(aviso,'reconocer',gen_random_uuid());
  perform pg_temp.afirmar(r#>>'{alertas,0,estado}'='reconocido' and not r?'diarias','Reconoce sin llamar al SLA');
  perform pg_temp.error_esperado('select crm.gestion_diaria_avisos_fn()','P0001');
  execute anterior;
end $independencia$;
select 'PASS: auth heredada, horarios/medianoche por RPC, llamadas no útiles y escrituras sin SLA';
