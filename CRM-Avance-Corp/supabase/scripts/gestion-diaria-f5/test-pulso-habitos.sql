-- Fixtures sintéticos y lecturas autenticadas. Todos los datos hacen ROLLBACK.
begin;
set local statement_timeout='90s';
-- NUCLEO_BASE
create function pg_temp.afirmar(ok boolean,mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'F5: %',mensaje; end if; end $$;
create function pg_temp.denegada(comando text,codigo text default '42501') returns void language plpgsql as $$
declare recibido text; begin
  begin execute comando; exception when others then recibido:=sqlstate; end;
  perform pg_temp.afirmar(recibido=codigo,format('esperado %s, recibido %s: %s',codigo,coalesce(recibido,'sin error'),comando));
end $$;
create temporary table f5_actores as
with vendedores as (select e.perfil_id,e.supervisor_id from crm.equipo e
  where private.rol_crm(e.perfil_id)='vendedor' and private.rol_crm(e.supervisor_id)='supervisor' order by e.perfil_id)
select (select perfil_id from vendedores limit 1) a,
  (select perfil_id from vendedores where supervisor_id<>(select supervisor_id from vendedores limit 1) limit 1) b,
  (select supervisor_id from vendedores limit 1) supervisor_a,
  (select supervisor_id from vendedores where supervisor_id<>(select supervisor_id from vendedores limit 1) limit 1) supervisor_b,
  (select perfil_id from crm.equipo where rol_crm='vendedor' and private.rol_crm(perfil_id) is null limit 1) revocado,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id)='gerencia' limit 1) gerente,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id)='coordinador' limit 1) coordinador,
  (select id from public.perfiles where activo and rol='directorio' limit 1) lector_global,
  (select id from crm.leads order by id limit 1) lead_1,
  (select id from crm.leads order by id offset 1 limit 1) lead_2,
  (statement_timestamp() at time zone 'America/Lima')::date-1 as dia;
alter table f5_actores add column c uuid;
update f5_actores set c=(select perfil_id from crm.equipo where private.rol_crm(perfil_id)='vendedor' and perfil_id not in (a,b) limit 1);
grant select on f5_actores to authenticated,anon;
select pg_temp.afirmar(a is not null and b is not null and c is not null and revocado is not null
  and gerente is not null and lector_global is not null and lead_2 is not null,'banco sin actores requeridos') from f5_actores;

-- Preparación sólo como postgres. El oráculo y las RPC se leen como authenticated.
alter table crm.actividades disable trigger user;
update crm.actividades set creado_en=((select dia-100 from f5_actores)::timestamp at time zone 'America/Lima');
alter table crm.tareas disable trigger user;
update crm.tareas set activo=false,creado_en=((select dia-100 from f5_actores)::timestamp at time zone 'America/Lima');
alter table crm.equipo disable trigger user;
update crm.equipo set supervisor_id=(select supervisor_a from f5_actores) where perfil_id=(select supervisor_b from f5_actores);
update crm.equipo set supervisor_id=null where perfil_id=(select c from f5_actores);
alter table crm.equipo enable trigger user;
alter table crm.politica_gestion_diaria disable trigger user;
insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,creado_por,motivo,cortes_activos)
select 2,p.id,(f.dia-60)::timestamp at time zone 'America/Lima',f.gerente,'F5: política sintética para probar hábitos',true
from crm.politica_gestion_diaria p cross join f5_actores f where p.version=1;
alter table crm.politica_gestion_diaria enable trigger user;

insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select f.lead_1,x.tipo,f.a,(f.dia+x.hora) at time zone 'America/Lima',jsonb_build_object('resultado',x.resultado)
from f5_actores f cross join(values
  (time '08:59','llamada_no_contestada','no_contesto'),
  (time '09:00','llamada_realizada','interesado'),
  (time '09:30','llamada_realizada','numero_errado'),
  (time '12:15','llamada_realizada','interesado')) x(hora,tipo,resultado);
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select lead_1,'llamada_realizada',b,(dia+time '10:00') at time zone 'America/Lima','{"resultado":"interesado"}'::jsonb from f5_actores
union all select lead_2,'llamada_no_contestada',b,(dia+time '10:10') at time zone 'America/Lima','{"resultado":"no_contesto"}' from f5_actores
union all select lead_1,'llamada_realizada',revocado,(dia+time '10:00') at time zone 'America/Lima','{"resultado":"interesado"}' from f5_actores
union all select lead_2,'llamada_no_contestada',null,(dia+time '10:00') at time zone 'America/Lima','{"resultado":"no_contesto"}' from f5_actores
union all select lead_2,'llamada_realizada',supervisor_a,(dia+time '10:00') at time zone 'America/Lima','{"resultado":"interesado"}' from f5_actores
union all select lead_1,'whatsapp_enviado',c,(dia+time '10:00') at time zone 'America/Lima','{}' from f5_actores;
-- Siete jornadas no consecutivas, 1..7 llamadas cada una. Media manual=4.
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select f.lead_1,'llamada_no_contestada',f.a,((f.dia-2*i)+time '10:00') at time zone 'America/Lima','{"resultado":"no_contesto"}'
from f5_actores f cross join generate_series(1,7) i cross join lateral generate_series(1,i) j;
alter table crm.actividades enable trigger user;
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,creado_en)
select f.lead_1,f.a,'llamada','F5 vencida',statement_timestamp()-interval '1 hour',
  (f.dia-100)::timestamp at time zone 'America/Lima' from f5_actores f cross join generate_series(1,1005) i;
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,creado_en)
select f.lead_1,x.id,'tarea','F5 fuera',statement_timestamp()-interval '1 hour',
  (f.dia-100)::timestamp at time zone 'America/Lima' from f5_actores f cross join lateral unnest(array[f.b,f.revocado,null::uuid]) x(id);
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,creado_en,modalidad_reunion)
select f.lead_1,x.id,'reunion','F5 cita creada',statement_timestamp()+interval '1 day',
  (f.dia+time '10:00') at time zone 'America/Lima','sin_clasificar'
from f5_actores f cross join lateral unnest(array[f.a,f.b,null::uuid]) x(id);
alter table crm.tareas enable trigger user;
create temporary table f5_fotos(tipo text,j jsonb);
grant all on f5_fotos to authenticated;
select set_config('request.jwt.claim.sub',gerente::text,true) from f5_actores;
set local role authenticated;
insert into f5_fotos select 'pulso',crm.gestion_diaria_pulso_fn(dia) from f5_actores;
insert into f5_fotos select 'habitos',crm.gestion_diaria_habitos_fn(dia,7) from f5_actores;
select pg_temp.afirmar(not exists(
  select r.analista_id from private.gestion_diaria_pulso_roster() r except
  select (e->>'analista_id')::uuid from f5_actores f cross join lateral
    jsonb_array_elements(crm.gestion_diaria_equipo_fn(f.dia,null)->'equipo') e),
  'detalle global gerencial incluye todo el roster, equipo anidado y analista sin supervisor');
select pg_temp.afirmar(not exists(select 1 from jsonb_array_elements(crm.gestion_diaria_pulso_fn(dia-1)->'equipos') e
  cross join lateral jsonb_array_elements(e->'personas') p where p->'analista_id'='null'::jsonb),
  'pendientes sin asignar de hoy no inventan un autor sin actividad en un día histórico') from f5_actores;

select pg_temp.afirmar(j#>>'{actual,llamadas}'='9' and j#>>'{actual,utiles}'='8'
  and j#>>'{actual,contestadas}'='5' and j#>>'{actual,leads_unicos}'='2'
  and j#>>'{actual,citas_agendadas}'='3','totales manuales con autor revocado, supervisor y NULL') from f5_fotos where tipo='pulso';
select pg_temp.afirmar((j#>>'{actual,tasa_contacto}')::numeric=62.5,'tasa de numeradores, no media de porcentajes') from f5_fotos where tipo='pulso';
select pg_temp.afirmar(j#>>'{actual,con_actividad}'='3','WhatsApp enviado cuenta como gestión aunque no llame') from f5_fotos where tipo='pulso';
select pg_temp.afirmar(j#>>'{referencia,cantidad}'='7' and (j#>>'{referencia,media,llamadas}')::numeric=4
  and (j#>>'{referencia,dias,6}')::date=(select dia-14 from f5_actores)
  and j#>>'{ayer,metricas,llamadas}'='0','base de siete jornadas activas no consecutivas y ayer completo') from f5_fotos where tipo='pulso';
select pg_temp.afirmar(j->>'vencidas_global'='1008','pendientes completos sin límite de mil') from f5_fotos where tipo='pulso';
select pg_temp.afirmar((select sum((e#>>'{metricas,llamadas}')::int) from jsonb_array_elements(j->'equipos') e)=(j#>>'{actual,llamadas}')::int
  and (select sum((e->>'tareas_vencidas')::int) from jsonb_array_elements(j->'equipos') e)=(j->>'vencidas_global')::int,'conservación de equipos y fila de cuadre') from f5_fotos where tipo='pulso';
select pg_temp.afirmar((select e#>>'{metricas,llamadas}' from jsonb_array_elements(j->'equipos') e where e->>'clave'=(select supervisor_a::text from f5_actores))='4'
  and (select e#>>'{metricas,llamadas}' from jsonb_array_elements(j->'equipos') e where e->>'clave'=(select supervisor_b::text from f5_actores))='2'
  and (select e#>>'{metricas,llamadas}' from jsonb_array_elements(j->'equipos') e where e->>'clave'='fuera')='3','supervisores anidados no duplican personas') from f5_fotos where tipo='pulso';
select pg_temp.afirmar(
  (select p->>'nombre_completo' from jsonb_array_elements(j->'equipos') e cross join lateral jsonb_array_elements(e->'personas') p
    where p->>'analista_id'=(select supervisor_a::text from f5_actores)) is not null
  and (select p->>'nombre_completo' from jsonb_array_elements(j->'equipos') e cross join lateral jsonb_array_elements(e->'personas') p
    where p->>'analista_id'=(select revocado::text from f5_actores)) is null,
  'nombres de otros autores sólo cuando equipo_visible_fn los autoriza') from f5_fotos where tipo='pulso';
-- Oráculo independiente: cuenta filas originales bajo el mismo rol, sin usar helpers nuevos.
select pg_temp.afirmar((j#>>'{actual,llamadas}')::bigint=(select count(*) from crm.actividades a,f5_actores f
  where a.tipo in ('llamada_realizada','llamada_no_contestada') and a.creado_en>=f.dia::timestamp at time zone 'America/Lima'
  and a.creado_en<(f.dia+1)::timestamp at time zone 'America/Lima'),'conciliación cruda') from f5_fotos where tipo='pulso';
-- Paridad de los consumidores anteriores: arrays válidos, duplicados y vacíos.
select pg_temp.afirmar(
  (select jsonb_agg(to_jsonb(x) order by x.vendedor_id) from private.gestion_diaria_llamadas(f.dia::timestamp at time zone 'America/Lima',(f.dia+1)::timestamp at time zone 'America/Lima',ids) x)
  is not distinct from
  (select jsonb_agg(to_jsonb(x) order by x.vendedor_id) from pg_temp.llamadas_base(f.dia::timestamp at time zone 'America/Lima',(f.dia+1)::timestamp at time zone 'America/Lima',ids) x),
  'paridad núcleo F3 para arrays válidos') from f5_actores f cross join lateral(values(array[f.a,f.b,f.revocado]),(array[f.a,f.a]),('{}'::uuid[]),(null::uuid[])) v(ids);
-- Extensión deliberada: NULL explícito representa al autor ausente en F5.
-- F3/F4 obtienen IDs no nulos del actor/roster; sus resultados siguen iguales.
select pg_temp.afirmar(
  (select llamadas from private.gestion_diaria_llamadas(f.dia::timestamp at time zone 'America/Lima',(f.dia+1)::timestamp at time zone 'America/Lima',array[f.a,null::uuid]) where vendedor_id is null)=1
  and (select llamadas from pg_temp.llamadas_base(f.dia::timestamp at time zone 'America/Lima',(f.dia+1)::timestamp at time zone 'America/Lima',array[f.a,null::uuid]) where vendedor_id is null)=0,
  'NULL explícito conserva la nueva semántica de autor ausente sin confundirla con paridad') from f5_actores f;
select pg_temp.afirmar(j->'umbral_tasa_baja'='null'::jsonb and jsonb_array_length(j->'personas')=(select count(*) from private.gestion_diaria_pulso_roster()),'hábitos no activa umbrales ni pierde roster') from f5_fotos where tipo='habitos';
select pg_temp.afirmar(d#>>'{jornada,hueco,minutos}'='165.0'
  and (d->>'primera_llamada_en')::timestamptz=((select dia from f5_actores)+time '08:59') at time zone 'America/Lima',
  'primera llamada completa y hueco entre llamadas dentro de jornada')
  from f5_fotos f cross join lateral jsonb_array_elements(f.j->'personas') p cross join lateral jsonb_array_elements(p->'dias') d
  where f.tipo='habitos' and p->>'analista_id'=(select a::text from f5_actores) and d->>'dia'=(select dia::text from f5_actores);
select pg_temp.afirmar(d#>'{jornada,hueco}'='null'::jsonb,'cero llamadas no inventa un hueco entre llamadas')
  from f5_fotos f cross join lateral jsonb_array_elements(f.j->'personas') p cross join lateral jsonb_array_elements(p->'dias') d
  where f.tipo='habitos' and p->>'analista_id'=(select c::text from f5_actores) and d->>'dia'=(select dia::text from f5_actores);
select pg_temp.afirmar(d#>'{cortes,segundo_corte}'='null'::jsonb,'sábado solo tiene un corte')
  from f5_fotos f cross join lateral jsonb_array_elements(f.j->'personas') p cross join lateral jsonb_array_elements(p->'dias') d
  where f.tipo='habitos' and extract(isodow from (d->>'dia')::date)=6;
select pg_temp.denegada('select crm.gestion_diaria_pulso_fn(''infinity'')','22023');
select pg_temp.denegada('select crm.gestion_diaria_pulso_fn((now() at time zone ''America/Lima'')::date+1)','22023');
select pg_temp.denegada('select crm.gestion_diaria_pulso_fn((now() at time zone ''America/Lima'')::date-366)','22023');
select pg_temp.denegada('select crm.gestion_diaria_habitos_fn(null,31)','22023');
select pg_temp.denegada('select crm.gestion_diaria_habitos_fn(null,null)','22023');
select pg_temp.afirmar(crm.gestion_diaria_habitos_fn((now() at time zone 'America/Lima')::date-365,30)->>'dias_incluidos'='1','límite histórico explícito de hábitos');
select pg_temp.afirmar(p#>>'{referencia,cantidad}'='0' and p#>'{referencia,media,llamadas}'='null'::jsonb,'sin historia es desconocido, no media cero')
  from (select crm.gestion_diaria_pulso_fn((now() at time zone 'America/Lima')::date-365) p) s;
reset role;
-- Límites de medianoche Lima: inicio incluido y final excluido.
savepoint tasas_ponderadas;
alter table crm.actividades disable trigger user;
alter table crm.tareas disable trigger user;
update crm.actividades set creado_en=((select dia-400 from f5_actores)::timestamp at time zone 'America/Lima');
update crm.tareas set creado_en=((select dia-400 from f5_actores)::timestamp at time zone 'America/Lima');
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select f.lead_1,'llamada_realizada',f.a,((f.dia-1)+time '10:00') at time zone 'America/Lima','{"resultado":"interesado"}'::jsonb
from f5_actores f cross join generate_series(1,2) n;
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select case when n%2=0 then f.lead_1 else f.lead_2 end,
  case when n<=10 then 'llamada_realizada' else 'llamada_no_contestada' end,f.a,
  ((f.dia-2)+time '10:00') at time zone 'America/Lima',
  jsonb_build_object('resultado',case when n<=10 then 'interesado' else 'no_contesto' end)
from f5_actores f cross join generate_series(1,100) n;
alter table crm.actividades enable trigger user;
alter table crm.tareas enable trigger user;
set local role authenticated;
select pg_temp.afirmar(p#>>'{referencia,cantidad}'='2' and (p#>>'{referencia,media,tasa_contacto}')::numeric=11.8
  and (p#>>'{referencia,media,llamadas_por_lead}')::numeric=34,
  'referencia pondera 12/102 útiles y 102/3 leads por día; no promedia cocientes desiguales')
from (select crm.gestion_diaria_pulso_fn(dia) p from f5_actores) q;
reset role;
rollback to savepoint tasas_ponderadas;

savepoint sla_apagado;
alter table crm.sla_operacion_control disable trigger user;
update crm.sla_operacion_control set modo='legado';
alter table crm.sla_operacion_control enable trigger user;
set local role authenticated;
select pg_temp.afirmar(p->>'modo_sla'='legado' and p->>'vencidas_global'='1008'
  and not exists(select 1 from jsonb_array_elements(p->'equipos') e where e->'primer_intento_vencido'<>'null'::jsonb),
  'SLA apagado no inventa ceros de primer intento ni pierde tareas actuales')
from (select crm.gestion_diaria_pulso_fn(dia) p from f5_actores) q;
reset role;
rollback to savepoint sla_apagado;

alter table crm.actividades disable trigger user;
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select lead_1,'llamada_no_contestada',a,dia::timestamp at time zone 'America/Lima','{}'::jsonb from f5_actores
union all select lead_1,'llamada_no_contestada',a,(dia+1)::timestamp at time zone 'America/Lima','{}' from f5_actores;
alter table crm.actividades enable trigger user;
set local role authenticated;
select pg_temp.afirmar(crm.gestion_diaria_pulso_fn(dia)#>>'{actual,llamadas}'='10','medianoche Lima [inicio,fin)') from f5_actores;
reset role;
-- Matriz de acceso: supervisor, analista y coordinación no ven operación global.
savepoint organigrama;
alter table crm.equipo disable trigger user;
update crm.equipo set activo=false where perfil_id=(select supervisor_b from f5_actores);
update crm.equipo set supervisor_id=(select revocado from f5_actores) where perfil_id=(select c from f5_actores);
update crm.equipo set supervisor_id=(select c from f5_actores) where perfil_id=(select revocado from f5_actores);
alter table crm.equipo enable trigger user;
set local role authenticated;
select pg_temp.afirmar((select r.supervisor_id from private.gestion_diaria_pulso_roster() r where r.analista_id=f.b)=f.supervisor_a,
  'atraviesa el supervisor inactivo hasta el supervisor activo más cercano') from f5_actores f;
select pg_temp.afirmar((select r.supervisor_id from private.gestion_diaria_pulso_roster() r where r.analista_id=f.c) is null,
  'ciclo sin supervisor activo termina sin inventar equipo') from f5_actores f;
reset role;
rollback to savepoint organigrama;

savepoint roster_vacio;
alter table crm.equipo disable trigger user;
update crm.equipo set activo=false where rol_crm='vendedor';
alter table crm.equipo enable trigger user;
set local role authenticated;
select pg_temp.afirmar(p#>>'{actual,analistas_activos}'='0' and p#>>'{actual,llamadas}'='10'
  and (select e#>>'{metricas,llamadas}' from jsonb_array_elements(p->'equipos') e where e->>'clave'='fuera')='10',
  'roster vacío conserva historia en fila fuera de equipos') from (select crm.gestion_diaria_pulso_fn(dia) p from f5_actores) q;
select pg_temp.afirmar(crm.gestion_diaria_habitos_fn(dia,7)->'personas'='[]'::jsonb,'hábitos sin personas activas mantiene respuesta válida') from f5_actores;
reset role;
rollback to savepoint roster_vacio;

savepoint horarios;
alter table f5_actores add column dia_habitos date;
update f5_actores set dia_habitos=dia-(extract(isodow from dia)::integer-1);
alter table crm.actividades disable trigger user;
insert into crm.actividades(lead_id,tipo,creado_por,creado_en)
select lead_1,'llamada_no_contestada',c,(dia_habitos+time '10:00') at time zone 'America/Lima' from f5_actores;
alter table crm.actividades enable trigger user;
set local role authenticated;
select pg_temp.afirmar(j#>'{0,hueco}'='null'::jsonb and (j#>>'{0,silencio_inicio_minutos}')::numeric=60
  and (j#>>'{0,silencio_final_minutos}')::numeric=30,'una llamada no forma hueco; silencios separados')
from (select private.gestion_diaria_habitos_jornada(dia_habitos,array[c],(dia_habitos+time '10:30') at time zone 'America/Lima') j from f5_actores) q;
select pg_temp.afirmar(j#>>'{0,estado}'='no_iniciada' and (j#>>'{0,silencio_inicio_minutos}')::numeric=0
  and j#>'{0,hueco}'='null'::jsonb,'antes de abrir no inventa un silencio ni hueco negativo')
from (select private.gestion_diaria_habitos_jornada(dia_habitos,array[c],(dia_habitos+time '08:59') at time zone 'America/Lima') j from f5_actores) q;
reset role;
alter table crm.actividades disable trigger user;
insert into crm.actividades(lead_id,tipo,creado_por,creado_en)
select f.lead_1,'llamada_no_contestada',f.c,(f.dia_habitos+x.hora) at time zone 'America/Lima'
from f5_actores f cross join(values(time '11:00'),(time '12:00'),(time '18:00')) x(hora);
alter table crm.actividades enable trigger user;
set local role authenticated;
select pg_temp.afirmar((j#>>'{0,hueco,minutos}')::numeric=60
  and (j#>>'{0,hueco,desde}')::timestamptz=(f.dia_habitos+time '10:00') at time zone 'America/Lima'
  and (j#>>'{0,ultima_en_jornada}')::timestamptz=(f.dia_habitos+time '12:00') at time zone 'America/Lima'
  and (j#>>'{0,silencio_final_minutos}')::numeric=360,'empate elige primer hueco y excluye llamada justo al cierre')
from f5_actores f cross join lateral(select private.gestion_diaria_habitos_jornada(f.dia_habitos,array[f.c],(f.dia_habitos+time '19:00') at time zone 'America/Lima') j) q;
reset role;
rollback to savepoint horarios;

-- Las guardas deben detectar cambios peligrosos, no sólo aceptar el candidato.
savepoint mutante_acl;
grant execute on function crm.gestion_diaria_pulso_fn(date) to anon;
select pg_temp.denegada('select private.assert_gestion_diaria_pulso()','P0001');
rollback to savepoint mutante_acl;
savepoint mutante_definer;
alter function crm.gestion_diaria_habitos_fn(date,integer) security definer;
select pg_temp.denegada('select private.assert_gestion_diaria_pulso()','P0001');
rollback to savepoint mutante_definer;
savepoint mutante_cuerpo;
create or replace function private.gestion_diaria_pulso_metricas(p_personas jsonb,p_leads integer)
returns jsonb language sql immutable security invoker set search_path='' as $$ select '{}'::jsonb $$;
select pg_temp.denegada('select private.assert_gestion_diaria_pulso()','P0001');
rollback to savepoint mutante_cuerpo;
select private.assert_gestion_diaria_pulso();

do $$ declare actor uuid; begin
  foreach actor in array (select array[a,supervisor_a,coordinador,revocado] from f5_actores) loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    set local role authenticated;
    perform pg_temp.denegada('select crm.gestion_diaria_pulso_fn()');
    perform pg_temp.denegada('select crm.gestion_diaria_habitos_fn()');
    perform pg_temp.denegada('select * from private.gestion_diaria_pulso_roster()');
    reset role;
  end loop;
end $$;
select set_config('request.jwt.claim.sub',lector_global::text,true) from f5_actores;
set local role authenticated;
select pg_temp.afirmar(crm.gestion_diaria_pulso_fn(dia)#>>'{actual,llamadas}'='10','lector global conserva acceso') from f5_actores;
reset role;
set local role anon;
select pg_temp.denegada('select crm.gestion_diaria_pulso_fn()');
select pg_temp.denegada('select crm.gestion_diaria_habitos_fn()');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select pg_temp.denegada('select crm.gestion_diaria_pulso_fn()');
reset role;
-- Revocación inmediata aunque la sesión mantenga el mismo sujeto.
alter table crm.equipo disable trigger user;
update crm.equipo set activo=false where perfil_id=(select gerente from f5_actores);
alter table crm.equipo enable trigger user;
select set_config('request.jwt.claim.sub',gerente::text,true) from f5_actores;
set local role authenticated;
select pg_temp.denegada('select crm.gestion_diaria_pulso_fn()');
reset role;
rollback;
select 'PASS: F5 conciliación, paridad, hábitos, fechas, volumen y matriz de acceso';
