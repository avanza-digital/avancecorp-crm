-- Copia temporal del cuerpo instalado: sólo se sustituye el reloj. No se
-- reescribe el cálculo en el test ni se altera la función productiva.
begin;
set local statement_timeout = '60s';
do $$ declare fuente text; begin
  if current_database() <> 'gestion_diaria_f4_vista_chvrqh' then
    raise exception 'Oráculo permitido sólo en la copia F4';
  end if;
  fuente := pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure);
  if position('statement_timestamp()' in fuente) = 0 then raise exception 'Cambió el reloj del núcleo'; end if;
  fuente := replace(fuente, 'private.gestion_diaria_equipo_core(', 'pg_temp.f4_equipo_reloj(');
  fuente := replace(fuente, 'statement_timestamp()', 'current_setting(''f4.reloj'')::timestamptz');
  execute fuente;
end $$;
grant execute on function pg_temp.f4_equipo_reloj(date,uuid) to authenticated;
create temporary table f4_reloj_actor as
select e.perfil_id vendedor, e.supervisor_id supervisor from crm.equipo e
where private.rol_crm(e.perfil_id)='vendedor' and private.rol_crm(e.supervisor_id)='supervisor'
order by e.perfil_id limit 1;
grant select on f4_reloj_actor to authenticated;
create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'F4: %', mensaje; end if; end $$;
-- Un analista sin cartera, tareas ni actividad tiene que seguir apareciendo.
alter table crm.leads disable trigger user;
update crm.leads set activo=false where vendedor_id=(select vendedor from f4_reloj_actor);
alter table crm.leads enable trigger user;
alter table crm.tareas disable trigger user;
update crm.tareas set activo=false where vendedor_id=(select vendedor from f4_reloj_actor);
alter table crm.tareas enable trigger user;
alter table crm.actividades disable trigger user;
update crm.actividades set creado_en='2000-01-01T12:00:00Z' where creado_por=(select vendedor from f4_reloj_actor);
alter table crm.actividades enable trigger user;
select set_config('request.jwt.claim.sub', supervisor::text, true) from f4_reloj_actor;
set local role authenticated;
do $$ declare caso record; fila jsonb; foto jsonb; begin
  for caso in select * from (values
    ('2026-09-21T08:59:59-05:00',false),
    ('2026-09-21T09:00:00-05:00',false),
    ('2026-09-21T11:00:00-05:00',false),
    ('2026-09-21T11:00:01-05:00',true),
    ('2026-09-21T17:59:59-05:00',true),
    ('2026-09-21T18:00:00-05:00',false),
    ('2026-09-26T12:59:59-05:00',true),
    ('2026-09-26T13:00:00-05:00',false),
    ('2026-09-27T12:00:00-05:00',false)
  ) c(reloj, esperado) loop
    perform set_config('f4.reloj', caso.reloj, true);
    foto := pg_temp.f4_equipo_reloj(null,null);
    select e into fila from jsonb_array_elements(foto->'equipo') e
      where e->>'analista_id'=(select vendedor::text from f4_reloj_actor);
    perform pg_temp.afirmar(fila is not null, 'Omitió al analista sin cartera');
    perform pg_temp.afirmar((fila->>'gestiones_hoy')::integer=0
      and (fila#>>'{marcador,llamadas}')::integer=0
      and (fila->>'tareas_pendientes')::integer=0, 'Inventó actividad o pendientes');
    perform pg_temp.afirmar((fila->>'sin_llamar_2h')::boolean=caso.esperado,
      'Inactividad fuera del calendario: ' || caso.reloj);
  end loop;
  -- El día cambia a medianoche de Lima, no a medianoche UTC.
  perform set_config('f4.reloj', '2026-09-22T04:59:59Z', true);
  perform pg_temp.afirmar(pg_temp.f4_equipo_reloj(null,null)->>'dia'='2026-09-21', 'Día adelantado por UTC');
  perform set_config('f4.reloj', '2026-09-22T05:00:00Z', true);
  perform pg_temp.afirmar(pg_temp.f4_equipo_reloj(null,null)->>'dia'='2026-09-22', 'No avanzó el día de Lima');
end $$;
reset role;
-- «No evaluado» debe seguir siendo NULL, nunca «no hay pendientes».
alter table crm.sla_operacion_control disable trigger user;
update crm.sla_operacion_control set modo='observacion' where id;
alter table crm.sla_operacion_control enable trigger user;
set local role authenticated;
select pg_temp.afirmar(not exists (
  select 1 from jsonb_array_elements(crm.gestion_diaria_equipo_fn()->'equipo') e
  where e->>'primer_intento_vencido' is not null or e->>'datos_incompletos' is not null
), 'Observación se presentó como cero');
reset role;
select 'GESTION_DIARIA_CALENDARIO_OK';
rollback;
