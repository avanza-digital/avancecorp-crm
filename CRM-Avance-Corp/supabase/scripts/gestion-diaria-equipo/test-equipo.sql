-- Fixture reversible, sólo en la copia local. Lecturas siempre authenticated,
-- nunca acreditar RLS con una consulta como postgres.
begin;
set local statement_timeout = '120s';
do $$ begin
  if current_database() <> 'gestion_diaria_f4_vista_chvrqh' then
    raise exception 'Oráculo permitido sólo en la copia F4';
  end if;
end $$;
create temporary table f4_actores as
with v as (select e.perfil_id, e.supervisor_id from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'vendedor' and private.rol_crm(e.supervisor_id) = 'supervisor'
  order by e.perfil_id)
select (select perfil_id from v limit 1) v1, (select supervisor_id from v limit 1) sup,
  (select supervisor_id from v where supervisor_id <> (select supervisor_id from v limit 1) limit 1) sup_ajeno,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'gerencia' limit 1) ger,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'coordinador' limit 1) coord,
  gen_random_uuid() lead_id;
create temporary table f4_fotos(k text primary key, foto jsonb);
grant select on f4_actores to authenticated;
grant all on f4_fotos to authenticated;
create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'F4: %', mensaje; end if; end $$;
select pg_temp.afirmar(v1 is not null and sup is not null and sup_ajeno is not null and ger is not null, 'Faltan actores de dos equipos') from f4_actores;
-- Si se añade un tipo al catálogo, exigir decidir si es acción humana o
-- suceso automático/entrante antes de seguir contando actividad en F4.
select pg_temp.afirmar(not exists (
  select 1 from pg_constraint c,
    lateral regexp_matches(pg_get_constraintdef(c.oid), '''([^'']+)''::text', 'g') m
  where c.conrelid = 'crm.actividades'::regclass and c.conname = 'actividades_tipo_check'
    and m[1] <> all(array['llamada_realizada','llamada_no_contestada','whatsapp_enviado',
      'whatsapp_recibido','reunion_realizada','nota','cambio_etapa','reasignacion','conversion'])
), 'Tipo de actividad nuevo sin clasificar para F4');
select set_config('request.jwt.claim.sub', sup::text, true) from f4_actores;
set local role authenticated;
insert into f4_fotos values ('antes', crm.gestion_diaria_equipo_fn());
select pg_temp.afirmar((foto->>'supervisor_id')::uuid = (select sup from f4_actores), 'Eco supervisor') from f4_fotos;
select pg_temp.afirmar(jsonb_array_length(foto->'equipo') = (
  select cardinality(array_agg(e.perfil_id)) from crm.equipo_visible_fn() e where e.activo and e.rol_crm = 'vendedor'),
  'Roster completo aunque no haya actividad') from f4_fotos;
do $$ begin
  perform crm.gestion_diaria_equipo_fn(null, (select sup_ajeno from f4_actores));
  raise exception 'F4: aceptó equipo ajeno';
exception when insufficient_privilege then null; end $$;
do $$ begin
  perform crm.gestion_diaria_equipo_fn('infinity');
  raise exception 'F4: aceptó fecha infinita';
exception when invalid_parameter_value then null; end $$;
do $$ begin
  perform crm.gestion_diaria_equipo_fn((now() at time zone 'America/Lima')::date + 1);
  raise exception 'F4: aceptó futuro';
exception when invalid_parameter_value then null; end $$;
reset role;

-- Crear un lead por la puerta legal y luego preparar exactamente 31 llamadas
-- y 270 tareas pendientes en el fixture. Los triggers se restauran dentro del
-- mismo rollback; jamás se ejecuta este bloque en una base externa.
select set_config('request.jwt.claim.sub', ger::text, true) from f4_actores;
select crm.crear_lead_si_disponible(p_nombre_completo => 'ORACULO F4 EQUIPO', p_telefono => '999577771',
  p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => lead_id,
  p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
  p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => v1,
  p_nota => 'Fixture reversible F4', p_telefono_alternativo => null) from f4_actores;
alter table crm.actividades disable trigger user;
update crm.actividades set creado_en = creado_en - interval '2 days'
where creado_por = (select v1 from f4_actores)
  and creado_en >= ((now() at time zone 'America/Lima')::date::timestamp at time zone 'America/Lima');
insert into crm.actividades(lead_id, tipo, creado_por, creado_en, metadata)
select a.lead_id, case when i <= 13 or i > 29 then 'llamada_realizada' else 'llamada_no_contestada' end,
  a.v1, ((now() at time zone 'America/Lima')::date + time '10:00') at time zone 'America/Lima',
  case when i > 29 then '{"resultado":"numero_errado"}'::jsonb else '{}'::jsonb end
from f4_actores a cross join generate_series(1,31) i;
alter table crm.actividades enable trigger user;
alter table crm.tareas disable trigger user;
insert into crm.tareas(lead_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select a.lead_id, a.v1, 'llamada', 'Oráculo F4 ' || i, now() - interval '1 hour', a.v1
from f4_actores a cross join generate_series(1,270) i;
alter table crm.tareas enable trigger user;

select set_config('request.jwt.claim.sub', sup::text, true) from f4_actores;
set local role authenticated;
insert into f4_fotos values ('despues', crm.gestion_diaria_equipo_fn());
do $$ declare f jsonb; anterior jsonb; begin
  select e into f from f4_fotos d, jsonb_array_elements(d.foto->'equipo') e
    where d.k = 'despues' and e->>'analista_id' = (select v1::text from f4_actores);
  select e into anterior from f4_fotos d, jsonb_array_elements(d.foto->'equipo') e
    where d.k = 'antes' and e->>'analista_id' = (select v1::text from f4_actores);
  perform pg_temp.afirmar((f#>>'{marcador,llamadas}')::int = 31, 'Todas las llamadas, incluso inválidas');
  perform pg_temp.afirmar((f#>>'{marcador,contestadas}')::int = 13 and (f#>>'{marcador,utiles}')::int = 29, 'Denominador útil canónico');
  perform pg_temp.afirmar((f#>>'{marcador,tasa_contacto_pct}')::int = 45 and f#>>'{marcador,nivel}' = 'atencion', 'No calificar con porcentaje redondeado');
  perform pg_temp.afirmar((f->>'gestiones_hoy')::int = 31, 'Actividad no depende de cartera en navegador');
  perform pg_temp.afirmar((f->>'tareas_pendientes')::int = (anterior->>'tareas_pendientes')::int + 270, 'Pendientes sin tope de 200');
  perform pg_temp.afirmar((f->>'tareas_vencidas')::int = (anterior->>'tareas_vencidas')::int + 270, 'Vencidas completas');
  perform pg_temp.afirmar((f->>'requiere_atencion')::boolean, 'El analista vencido requiere atención');
end $$;
-- Jornada histórica sin fixtures: roster intacto y cero, nunca filas omitidas.
reset role;
alter table crm.actividades disable trigger user;
insert into crm.actividades(lead_id, tipo, creado_por, creado_en)
select a.lead_id, t, a.v1, now() from f4_actores a cross join unnest(array[
  'whatsapp_enviado','reunion_realizada','nota','conversion',
  'whatsapp_recibido','cambio_etapa','reasignacion']) t;
alter table crm.actividades enable trigger user;
set local role authenticated;
select pg_temp.afirmar((e->>'gestiones_hoy')::integer = 35 and (e#>>'{marcador,llamadas}')::integer = 31,
  'WhatsApp/nota/cita/conversión cuentan; entrantes/automáticas no; llamadas no cambian')
from jsonb_array_elements(crm.gestion_diaria_equipo_fn()->'equipo') e
where e->>'analista_id' = (select v1::text from f4_actores);
insert into f4_fotos values ('historico', crm.gestion_diaria_equipo_fn((now() at time zone 'America/Lima')::date - 364));
select pg_temp.afirmar(jsonb_array_length(foto->'equipo') = (select jsonb_array_length(foto->'equipo') from f4_fotos where k='antes'), 'Cero actividad mantiene roster') from f4_fotos where k='historico';
select pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(foto->'equipo') f where (f->>'sin_llamar_2h')::boolean), 'No juzga inactividad de un día pasado') from f4_fotos where k='historico';
reset role;

select set_config('request.jwt.claim.sub', v1::text, true) from f4_actores;
set local role authenticated;
do $$ begin
  perform crm.gestion_diaria_equipo_fn(); raise exception 'F4: vendedor admitido';
exception when insufficient_privilege then null; end $$;
do $$ begin
  perform private.gestion_diaria_equipo_pendientes(); raise exception 'F4: adaptador admite vendedor';
exception when insufficient_privilege then null; end $$;
reset role;
select set_config('request.jwt.claim.sub', coalesce(coord::text, ''), true) from f4_actores;
set local role authenticated;
do $$ begin
  perform crm.gestion_diaria_equipo_fn(); raise exception 'F4: coordinador admitido';
exception when insufficient_privilege then null; end $$;
reset role;
select set_config('request.jwt.claim.sub', ger::text, true) from f4_actores;
set local role authenticated;
select pg_temp.afirmar(crm.gestion_diaria_equipo_fn(null, sup)->>'supervisor_id' = sup::text, 'Gerencia puede seleccionar equipo') from f4_actores;
reset role;
-- Revocación vigente, aun con el mismo JWT y auth.uid().
-- Simular el estado final del offboarding; la vía administrativa exige antes
-- reasignar dependencias. No estamos ensayando esa mutación en esta fase.
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false where perfil_id = (select sup from f4_actores);
alter table crm.equipo enable trigger user;
select set_config('request.jwt.claim.sub', sup::text, true) from f4_actores;
set local role authenticated;
do $$ begin
  perform crm.gestion_diaria_equipo_fn(); raise exception 'F4: supervisor revocado admitido';
exception when insufficient_privilege then null; end $$;
reset role;
-- Sin identidad nunca se hereda un ámbito anterior.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $$ begin
  perform crm.gestion_diaria_equipo_fn(); raise exception 'F4: admitió identidad ausente';
exception when insufficient_privilege then null; end $$;
reset role;
-- El gate debe detectar cada defensa retirada. La excepción propia revierte
-- individualmente cada mutante, de modo que no se enmascaran unos a otros.
do $mutantes$
declare v_sql text; v_detectado boolean; v_total integer := 0;
begin
  foreach v_sql in array array[
    'grant execute on function crm.gestion_diaria_equipo_fn(date,uuid) to anon',
    'grant execute on function private.gestion_diaria_equipo_pendientes() to public',
    'grant execute on function private.gestion_diaria_equipo_core(date,uuid) to service_role',
    'revoke execute on function crm.gestion_diaria_equipo_fn(date,uuid) from authenticated',
    'alter function crm.gestion_diaria_equipo_fn(date,uuid) security definer',
    'alter function private.gestion_diaria_equipo_core(date,uuid) security definer',
    'alter function private.gestion_diaria_equipo_pendientes() security invoker',
    'alter function private.gestion_diaria_equipo_pendientes() set search_path = public',
    'alter function private.gestion_diaria_equipo_core(date,uuid) volatile'
  ] loop
    v_detectado := false;
    begin
      execute v_sql;
      begin perform private.assert_gestion_diaria_equipo();
        exception when others then v_detectado := true; end;
      raise exception 'Revertir mutante' using errcode = 'P0666';
    exception when sqlstate 'P0666' then null; end;
    perform pg_temp.afirmar(v_detectado, 'Mutante sobrevivió: ' || v_sql);
    perform private.assert_gestion_diaria_equipo();
    v_total := v_total + 1;
  end loop;
  perform pg_temp.afirmar(v_total = 9, 'Nueve mutantes independientes');
end;
$mutantes$;
select 'GESTION_DIARIA_EQUIPO_OK';
rollback;
