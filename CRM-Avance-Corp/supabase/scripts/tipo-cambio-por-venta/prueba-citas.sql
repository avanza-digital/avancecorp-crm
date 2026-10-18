savepoint citas_valoradas;
select set_config('request.jwt.claim.sub',pg_temp.persona(1)::text,true);
select pg_temp.comprobar(crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31')=
  crm.citas_gerencia_consulta_fn('2026-10-01','2026-10-31'),
  'Citas conserva el payload exacto cuando la presentación está desactivada');
update crm.capital_valoracion_politica set activa=true;
select pg_temp.comprobar(crm.citas_gerencia_consulta_v2_fn('2026-09-01','2026-09-30')=
  crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30'),
  'septiembre conserva exactamente Citas y su régimen anterior');
create function pg_temp.citas_sin_equivalentes(p jsonb) returns jsonb language sql as $$
  select jsonb_set(p #- '{gestion,valoracion}','{gestion,capital}',(select coalesce(jsonb_agg(
    k - array['equivalente_pen','tasa','fecha_comercial','fecha_tc','politica_tc'] order by n),'[]')
    from jsonb_array_elements(p#>'{gestion,capital}') with ordinality q(k,n)));
$$;
set local role authenticated;
select pg_temp.comprobar(pg_temp.citas_sin_equivalentes(crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31'))=
  crm.citas_gerencia_consulta_fn('2026-10-01','2026-10-31'),
  'supervisión conserva citas, cohortes, PII, identidad y capital elegible del lector original');
reset role;
select jsonb_build_object('tc_fixture','citas-activo','payload',crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31'));
select pg_temp.comprobar((select sum((k->>'equivalente_pen')::numeric) from jsonb_array_elements(
  crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31')#>'{gestion,capital}') k)=
  (select sum((k->>'equivalente_pen')::numeric) from crm.capital_cortes_valorados c,
    jsonb_array_elements(c.base) k where c.id=(select id from cortes_prueba where nombre='original')
    and not(k->>'anulado')::boolean and (k->>'analista_id')::uuid in(select private.vendedor_ids_visibles(pg_temp.persona(1)))),
  'el ticket de Citas suma equivalentes del corte con su ámbito y sin anulados');
select pg_temp.comprobar(not exists(select 1 from jsonb_array_elements(
  crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31')#>'{gestion,capital}') k
  where (k->>'cierre_externo_id')::uuid=pg_temp.persona(32)),
  'Citas conserva la exclusión de cooperativas anuladas aunque el ranking ATR-4 retenga capital');
savepoint identidad_citas;
create temp table identidad_citas_antes as select k->>'contrato_id' contrato,k->>'cierre_externo_id' externo,
  k->>'identidad_persona' identidad from jsonb_array_elements(
    crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31')#>'{gestion,capital}') k;
set local session_replication_role=replica;
insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
values(pg_temp.persona(60),pg_temp.persona(5),pg_temp.persona(2));
update crm.cierres_externos set inversionista_id=pg_temp.persona(60) where id=pg_temp.persona(31);
set local session_replication_role=origin;
select pg_temp.comprobar(not exists(
  (select * from identidad_citas_antes except select k->>'contrato_id',k->>'cierre_externo_id',k->>'identidad_persona'
    from jsonb_array_elements(crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31')#>'{gestion,capital}') k)
  union all
  (select k->>'contrato_id',k->>'cierre_externo_id',k->>'identidad_persona'
    from jsonb_array_elements(crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31')#>'{gestion,capital}') k
    except select * from identidad_citas_antes)),
  'vincular o unificar identidades después del corte no cambia el divisor del ticket aceptado');
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(
  crm.citas_gerencia_consulta_fn('2026-10-01','2026-10-31')#>'{gestion,capital}') k
  where k->>'identidad_persona'='persona:'||pg_temp.persona(60)::text),
  'el ensayo cambia realmente la identidad viva, sin reescribir la almacenada');
rollback to savepoint identidad_citas;
-- Gerencia conserva su testigo; Directorio, Coordinación, vendedor e inactivos
-- no reciben esta puerta con identidades.
set local session_replication_role=replica;
update crm.equipo set rol_crm='gerencia' where perfil_id=pg_temp.persona(4);
set local session_replication_role=origin;
select set_config('request.jwt.claim.sub',pg_temp.persona(4)::text,true);
set local role authenticated;
select pg_temp.comprobar(pg_temp.citas_sin_equivalentes(crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31'))=
  crm.citas_gerencia_consulta_fn('2026-10-01','2026-10-31')
  and crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31') ? 'testigo',
  'Gerencia conserva el testigo independiente y la misma consulta original con sus identidades');
reset role;
-- La reasignación no permite que el antiguo supervisor lea capital aceptado
-- de un vendedor que ya no pertenece a su ámbito actual.
set local session_replication_role=replica;
update crm.equipo set supervisor_id=null where perfil_id=pg_temp.persona(3);
set local session_replication_role=origin;
select set_config('request.jwt.claim.sub',pg_temp.persona(1)::text,true);
set local role authenticated;
select pg_temp.comprobar(not exists(select 1 from jsonb_array_elements(
  crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31')#>'{gestion,capital}') k
  where (k->>'analista_id')::uuid=pg_temp.persona(3)),
  'el ámbito actual de supervisión filtra también el capital del corte');
reset role;
do $$ declare v_rol text; begin
  foreach v_rol in array array['coordinador','directorio','vendedor'] loop
    perform set_config('request.jwt.claim.sub',pg_temp.persona(4)::text,true);
    perform set_config('session_replication_role','replica',true);
    update crm.equipo set rol_crm=v_rol where perfil_id=pg_temp.persona(4);
    update public.perfiles set rol=case when v_rol='directorio' then 'directorio' else 'analista' end where id=pg_temp.persona(4);
    perform set_config('session_replication_role','origin',true);
    begin perform crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31');
      raise exception 'Rol % recibió PII de Citas',v_rol;
    exception when insufficient_privilege then null; end;
  end loop;
  perform set_config('session_replication_role','replica',true);
  update crm.equipo set rol_crm='supervisor',activo=false where perfil_id=pg_temp.persona(4);
  perform set_config('session_replication_role','origin',true);
  begin perform crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31');
    raise exception 'Un supervisor inactivo recibió Citas';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: Coordinación, Directorio, vendedor y supervisor inactivo no reciben PII de Citas';
end $$;
select pg_temp.comprobar(not has_function_privilege('anon','crm.citas_gerencia_consulta_v2_fn(date,date)','EXECUTE')
  and not has_function_privilege('service_role','crm.citas_gerencia_consulta_v2_fn(date,date)','EXECUTE')
  and not has_function_privilege('authenticated','private.citas_gerencia_consulta_corte(date,date,uuid)','EXECUTE')
  and not has_function_privilege('authenticated','private.citas_capital_del_corte(timestamptz,timestamptz,uuid)','EXECUTE'),
  'solo la RPC autorizada de Citas queda expuesta, sin lectura global ni helpers privados');
rollback to savepoint citas_valoradas;
